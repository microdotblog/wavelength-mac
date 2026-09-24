import Foundation
import Observation

@Observable
final class Composer {
  enum Mode: Equatable {
    case publish(episodeID: String)
    case edit(postUID: String)
  }

  enum Phase: Equatable {
    case idle
    case exporting
    case uploading(Double)
    case posting
    case done

    var label: String {
      switch self {
      case .exporting: "Preparing audio…"
      case .uploading: "Uploading audio…"
      case .posting: "Posting to Micro.blog…"
      case .idle, .done: ""
      }
    }

    var progress: Double {
      switch self {
      case .idle: 0
      case .exporting: 0.15
      case .uploading(let fraction): 0.2 + fraction * 0.6
      case .posting: 0.9
      case .done: 1
      }
    }
  }

  static let shortPostLength = 280

  let mode: Mode
  var title = ""
  var content = ""
  var summary = ""
  var status = "published"
  var categories: [String] = []
  var syndicates: [String] = []
  var newCategory = ""
  var showsTitle = false
  var errorMessage: String?
  private(set) var availableCategories: [String] = []
  private(set) var availableSyndicates: [SyndicationTarget] = []
  private(set) var phase: Phase = .idle
  private(set) var isLoadingSource = false

  @ObservationIgnored private let session: Session
  @ObservationIgnored private let library: Library
  @ObservationIgnored private let posts: PostsStore
  @ObservationIgnored private var postURL: String?

  init(mode: Mode, session: Session, library: Library, posts: PostsStore) {
    self.mode = mode
    self.session = session
    self.library = library
    self.posts = posts

    switch mode {
    case .publish(let episodeID):
      title = library.episode(episodeID)?.title ?? ""
    case .edit(let postUID):
      if let post = posts.post(postUID) {
        postURL = post.url
        title = post.title
        content = post.content
        status = post.status
        showsTitle = !post.title.trimmed.isEmpty
      }
    }
  }

  var isEditing: Bool {
    if case .edit = mode { true } else { false }
  }

  var isBusy: Bool { phase != .idle && phase != .done }

  var actionLabel: String {
    if isEditing {
      return "Update"
    }

    return status == "draft" ? "Save Draft" : "Post"
  }

  var shouldShowTitle: Bool {
    showsTitle || content.count > Self.shortPostLength || !title.isEmpty
  }

  var hasPublishableText: Bool {
    !content.trimmed.isEmpty || !summary.trimmed.isEmpty
  }

  var allCategories: [String] {
    Array(Set(availableCategories + categories)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  func loadOptions() async {
    guard let micropub = session.micropub else { return }

    async let categories = micropub.categories()
    async let syndicates = micropub.syndicationTargets()
    availableCategories = await categories
    availableSyndicates = await syndicates
  }

  func loadSource() async {
    guard let postURL, let micropub = session.micropub else { return }

    isLoadingSource = true
    defer { isLoadingSource = false }

    guard let source = try? await micropub.source(of: postURL) else { return }

    if !source.title.isEmpty { title = source.title }
    if !source.content.isEmpty { content = source.content }
    status = source.status
    categories = source.categories
    summary = source.summary
    showsTitle = showsTitle || !title.isEmpty
  }

  func toggleCategory(_ category: String) {
    toggle(category, in: &categories)
  }

  func toggleSyndicate(_ uid: String) {
    toggle(uid, in: &syndicates)
  }

  func addNewCategory() {
    guard let category = newCategory.nonEmptyValue else { return }

    if !categories.contains(category) {
      categories.append(category)
    }

    newCategory = ""
  }

  func submit() async -> Bool {
    switch mode {
    case .publish(let episodeID):
      return await publish(episodeID)
    case .edit:
      return await update()
    }
  }

  private func publish(_ episodeID: String) async -> Bool {
    guard !isBusy else { return false }

    guard hasPublishableText else {
      errorMessage = "You need show notes or a summary to publish."
      return false
    }

    errorMessage = nil
    var exported: URL?
    defer {
      if let exported {
        try? FileManager.default.removeItem(at: exported)
      }
    }

    do {
      let micropub = try session.requireMicropub()
      phase = .exporting
      let audio = try await library.publishableAudio(episodeID)
      exported = audio
      let size = SegmentFolder.fileSize(audio)

      if Formatting.isOverUploadLimit(size) {
        throw APIError(message: Formatting.uploadLimitMessage(size))
      }

      phase = .uploading(0)
      let audioURL = try await micropub.uploadAudio(audio, filename: Formatting.audioUploadFilename(for: title)) { [weak self] fraction in
        Task { @MainActor in
          if case .uploading = self?.phase {
            self?.phase = .uploading(fraction)
          }
        }
      }

      phase = .posting
      let postURL = try await micropub.create(Micropub.NewPost(
        title: title.trimmed,
        content: content.trimmed,
        audioURL: audioURL,
        status: status,
        summary: summary.trimmed,
        categories: categories,
        syndicates: syndicates
      ))

      if status == "published", !postURL.isEmpty {
        let postID = try? await micropub.source(of: postURL)?.uid
        try library.markPublished(episodeID, postID: postID, postURL: postURL)
        await posts.refresh()
      }

      phase = .done
      return true
    } catch {
      errorMessage = error.localizedDescription
      phase = .idle
      return false
    }
  }

  private func update() async -> Bool {
    guard !isBusy else { return false }

    guard let postURL else {
      errorMessage = "This post is no longer available."
      return false
    }

    guard hasPublishableText else {
      errorMessage = "You need show notes or a summary to publish."
      return false
    }

    errorMessage = nil
    phase = .posting

    do {
      try await session.requireMicropub("update a post").update(Micropub.PostUpdate(
        url: postURL,
        title: title,
        content: content,
        status: status,
        summary: summary,
        categories: categories
      ))
      await posts.refresh()
      phase = .done
      return true
    } catch {
      errorMessage = error.localizedDescription
      phase = .idle
      return false
    }
  }

  private func toggle(_ value: String, in list: inout [String]) {
    guard let value = value.nonEmptyValue else { return }

    if let index = list.firstIndex(of: value) {
      list.remove(at: index)
    } else {
      list.append(value)
    }
  }
}

extension SegmentFolder {
  nonisolated static func fileSize(_ url: URL) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
  }
}
