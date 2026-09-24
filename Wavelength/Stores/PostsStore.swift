import Foundation
import Observation

@Observable
final class PostsStore {
  enum Filter: String, CaseIterable, Identifiable {
    case all
    case posts
    case podcasts
    case narrated

    var id: String { rawValue }

    var label: String {
      switch self {
      case .all: "All"
      case .posts: "Posts"
      case .podcasts: "Podcasts"
      case .narrated: "Narrated"
      }
    }

    var kind: PostKind? {
      switch self {
      case .all: nil
      case .posts: .post
      case .podcasts: .podcast
      case .narrated: .narrated
      }
    }

    var emptyTitle: String {
      switch self {
      case .all: "No posts yet"
      case .posts: "No text posts"
      case .podcasts: "No podcasts yet"
      case .narrated: "No narrated posts yet"
      }
    }
  }

  enum AttachPhase {
    case idle
    case uploading
    case removing
  }

  private(set) var posts: [Post] = []
  private(set) var isLoading = false
  private(set) var didHydrate = false
  private(set) var attachPhase: AttachPhase = .idle
  var filter: Filter = .all
  var errorMessage: String?

  @ObservationIgnored private let session: Session

  init(session: Session) {
    self.session = session
  }

  var sortedPosts: [Post] {
    posts.sorted { $0.publishedAt > $1.publishedAt }
  }

  var filteredPosts: [Post] {
    guard let kind = filter.kind else { return sortedPosts }
    return sortedPosts.filter { $0.kind == kind }
  }

  var narratedPosts: [Post] {
    sortedPosts.filter { $0.kind == .narrated }
  }

  var isAttaching: Bool { attachPhase != .idle }

  func post(_ uid: String?) -> Post? {
    guard let uid = uid.nonEmpty else { return nil }
    return posts.first { $0.uid == uid }
  }

  func refresh() async {
    guard !isLoading else { return }

    guard let micropub = session.micropub else {
      posts = []
      didHydrate = true
      return
    }

    isLoading = true
    errorMessage = nil
    defer {
      isLoading = false
      didHydrate = true
    }

    do {
      posts = try await micropub.posts()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func delete(_ uid: String) async throws {
    guard let post = post(uid) else {
      throw APIError(message: "This post is no longer available.")
    }

    try await session.requireMicropub("delete a post").delete(postURL: post.url)
    posts.removeAll { $0.uid == uid }
  }

  func attachNarration(to uid: String, audio fileURL: URL) async throws {
    guard let post = post(uid) else {
      throw APIError(message: "This post is no longer available.")
    }

    let micropub = try session.requireMicropub("add narration")
    attachPhase = .uploading
    defer { attachPhase = .idle }

    let audioURL = try await micropub.uploadAudio(fileURL, filename: "narration.m4a")

    guard let source = try await micropub.source(of: post.url) else {
      throw APIError(message: "We could not load this post to add narration.")
    }

    let content = PostContent.applyNarration(to: source.content, audioURL: audioURL)
    try await micropub.update(Micropub.PostUpdate(
      url: post.url,
      title: source.title,
      content: content,
      status: source.status,
      summary: source.summary,
      categories: source.categories,
      audioURL: audioURL
    ))

    replaceContent(of: uid, with: content)
  }

  func removeNarration(from uid: String) async throws {
    guard let post = post(uid) else {
      throw APIError(message: "This post is no longer available.")
    }

    let micropub = try session.requireMicropub("remove narration")
    attachPhase = .removing
    defer { attachPhase = .idle }

    guard let source = try await micropub.source(of: post.url) else {
      throw APIError(message: "We could not load this post to remove narration.")
    }

    let content = PostContent.applyNarration(to: source.content, audioURL: "")
    try await micropub.update(Micropub.PostUpdate(
      url: post.url,
      title: source.title,
      content: content,
      status: source.status,
      summary: source.summary,
      categories: source.categories
    ))

    replaceContent(of: uid, with: content)
  }

  func reset() {
    posts = []
    didHydrate = false
    errorMessage = nil
  }

  private func replaceContent(of uid: String, with content: String) {
    guard let index = posts.firstIndex(where: { $0.uid == uid }) else { return }
    posts[index].content = content
  }
}
