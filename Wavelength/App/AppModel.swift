import Foundation
import Observation

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
  case podcasts
  case narrations
  case posts
  case discover
  case listenLater

  var id: String { rawValue }

  var title: String {
    switch self {
    case .podcasts: "Podcasts"
    case .narrations: "Narrations"
    case .posts: "Posts"
    case .discover: "Discover"
    case .listenLater: "Listen Later"
    }
  }

  var symbol: String {
    switch self {
    case .podcasts: "waveform"
    case .narrations: "mic"
    case .posts: "text.bubble"
    case .discover: "sparkles"
    case .listenLater: "bookmark"
    }
  }

  var feed: DiscoverStore.Feed? {
    switch self {
    case .discover: .discover
    case .listenLater: .listenLater
    default: nil
    }
  }
}

enum Sheet: Identifiable, Equatable {
  case publish(episodeID: String)
  case editPost(postUID: String)
  case editNarration(postUID: String, source: URL)

  var id: String {
    switch self {
    case .publish(let id): "publish-\(id)"
    case .editPost(let uid): "edit-\(uid)"
    case .editNarration(let uid, _): "narration-\(uid)"
    }
  }
}

@Observable
final class AppModel {
  let session = Session()
  let posts: PostsStore
  let library: Library
  let discover: DiscoverStore
  let nowPlaying = NowPlaying()
  let recorder = Recorder()
  let narration = NarrationDraft()
  let toasts = Toasts()
  let signInCard = SignInCard()

  var sidebar: SidebarItem = .podcasts
  var selectedEpisodeID: String?
  var selectedPostUID: String?
  var selectedDiscoverID: String?
  var isRecordingNewEpisode = false
  var sheet: Sheet?
  var pendingNarrationTakes: [String: RecordedTake] = [:]
  @ObservationIgnored private var didStart = false
  @ObservationIgnored var openMainWindow: () -> Void = {}

  init() {
    posts = PostsStore(session: session)
    library = Library(session: session, posts: posts)
    discover = DiscoverStore(session: session)
  }

  func start() async {
    guard !didStart else { return }

    didStart = true
    library.refresh()
    await session.hydrate()

    if session.isSignedIn {
      await posts.refresh()
    }
  }

  func showMainWindow() {
    openMainWindow()
    signInCard.close()
    Task { await didSignIn() }
  }

  func didSignIn() async {
    discover.reset()
    await posts.refresh()
  }

  func signOut() {
    nowPlaying.stop()
    recorder.cancel()
    narration.discard()
    session.signOut()
    posts.reset()
    discover.reset()
    selectedPostUID = nil
    selectedDiscoverID = nil
    sheet = nil
    isRecordingNewEpisode = false
    signInCard.show(self)
  }

  func startNewEpisode() {
    sidebar = .podcasts
    selectedEpisodeID = nil
    isRecordingNewEpisode = true
  }

  func finishNewEpisode(_ take: RecordedTake) {
    do {
      let episode = try library.create(from: take)
      isRecordingNewEpisode = false
      selectedEpisodeID = episode.id
    } catch {
      try? FileManager.default.removeItem(at: take.url)
      toasts.show(error.localizedDescription)
    }
  }

  func select(episode id: String) {
    sidebar = .podcasts
    isRecordingNewEpisode = false
    selectedEpisodeID = id
  }

  func select(post uid: String, in item: SidebarItem = .posts) {
    sidebar = item
    selectedPostUID = uid
  }

  func duplicate(episode id: String) {
    do {
      let copy = try library.duplicate(id)
      select(episode: copy.id)
    } catch {
      toasts.show(error.localizedDescription)
    }
  }

  func delete(episode id: String, deletingPost: Bool) async {
    let wasPublished = library.episode(id)?.isPublished ?? false

    if selectedEpisodeID == id {
      selectedEpisodeID = nil
    }

    do {
      try await library.delete(id, deletingPost: deletingPost)

      if deletingPost {
        toasts.show("Episode and post deleted.")
      } else {
        toasts.show(wasPublished ? "Episode removed from this Mac." : "Episode deleted.")
      }
    } catch {
      toasts.show(error.localizedDescription)
    }
  }

  func delete(post uid: String) async {
    do {
      try await posts.delete(uid)

      if selectedPostUID == uid {
        selectedPostUID = nil
      }

      toasts.show("Post deleted.")
    } catch {
      toasts.show(error.localizedDescription)
    }
  }

  func removeNarration(from uid: String) async {
    do {
      try await posts.removeNarration(from: uid)
      toasts.show("Narration deleted.")
    } catch {
      toasts.show(error.localizedDescription)
    }
  }
}

@Observable
final class Toasts {
  struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
  }

  private(set) var current: Toast?

  func show(_ message: String) {
    let toast = Toast(message: message)
    current = toast

    Task {
      try? await Task.sleep(for: .seconds(3))

      if current == toast {
        current = nil
      }
    }
  }
}
