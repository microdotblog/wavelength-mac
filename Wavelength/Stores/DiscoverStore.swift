import Foundation
import Observation

@Observable
final class DiscoverStore {
  enum Feed: String, CaseIterable, Identifiable {
    case discover
    case listenLater

    var id: String { rawValue }

    var title: String {
      switch self {
      case .discover: "Discover"
      case .listenLater: "Listen Later"
      }
    }

    var emptyTitle: String {
      switch self {
      case .discover: "No podcasts yet"
      case .listenLater: "Nothing saved yet"
      }
    }

    var emptyBody: String {
      switch self {
      case .discover: "Published podcast posts from Discover will show up here."
      case .listenLater: "Episodes you save for later on Micro.blog will show up here."
      }
    }
  }

  struct FeedState {
    var posts: [DiscoverPost] = []
    var isLoading = false
    var isLoadingMore = false
    var hasMore = true
    var didHydrate = false
    var errorMessage: String?
  }

  private(set) var discover = FeedState()
  private(set) var listenLater = FeedState()

  @ObservationIgnored private let session: Session

  init(session: Session) {
    self.session = session
  }

  func state(_ feed: Feed) -> FeedState {
    feed == .discover ? discover : listenLater
  }

  func visiblePosts(_ feed: Feed) -> [DiscoverPost] {
    switch feed {
    case .discover:
      discover.posts.filter(\.isPlayable).sorted { $0.publishedAt > $1.publishedAt }
    case .listenLater:
      listenLater.posts
    }
  }

  func post(_ id: String?) -> DiscoverPost? {
    guard let id else { return nil }
    return discover.posts.first { $0.id == id } ?? listenLater.posts.first { $0.id == id }
  }

  func refresh(_ feed: Feed) async {
    guard !state(feed).isLoading else { return }

    update(feed) {
      $0.isLoading = true
      $0.hasMore = true
      $0.errorMessage = nil
    }

    do {
      let posts = try await fetch(feed, before: nil)
      update(feed) {
        $0.posts = posts
        $0.hasMore = posts.count >= pageSize(feed)
      }
    } catch {
      update(feed) {
        $0.posts = []
        $0.hasMore = false
        $0.errorMessage = error.localizedDescription
      }
    }

    update(feed) {
      $0.isLoading = false
      $0.didHydrate = true
    }
  }

  func loadMore(_ feed: Feed) async {
    let current = state(feed)

    guard current.hasMore, !current.isLoading, !current.isLoadingMore, let lastID = current.posts.last?.id else {
      return
    }

    update(feed) { $0.isLoadingMore = true }

    do {
      let posts = try await fetch(feed, before: lastID)
      update(feed) { state in
        let existing = Set(state.posts.map(\.id))
        state.posts += posts.filter { !existing.contains($0.id) }
        state.hasMore = posts.count >= pageSize(feed)
      }
    } catch {
      update(feed) { $0.errorMessage = error.localizedDescription }
    }

    update(feed) { $0.isLoadingMore = false }
  }

  func saveForLater(_ post: DiscoverPost) async throws {
    guard let token = session.token else {
      throw APIError(message: "You need to be signed in to Micro.blog to save Listen Later episodes.")
    }

    try await DiscoverAPI.save(id: post.id, token: token)
    setSaved(true, id: post.id, url: post.url)
    listenLater.didHydrate = false
  }

  func removeFromLater(_ post: DiscoverPost) async throws {
    guard let token = session.token else {
      throw APIError(message: "You need to be signed in to Micro.blog to remove Listen Later episodes.")
    }

    try await DiscoverAPI.remove(id: post.id, token: token)
    listenLater.posts.removeAll { $0.id == post.id }
    setSaved(false, id: post.id, url: post.url)
  }

  func reset() {
    discover = FeedState()
    listenLater = FeedState()
  }

  private func setSaved(_ saved: Bool, id: String, url: String) {
    for index in discover.posts.indices where discover.posts[index].id == id || discover.posts[index].url == url {
      discover.posts[index].isSaved = saved
    }

    for index in listenLater.posts.indices where listenLater.posts[index].id == id {
      listenLater.posts[index].isSaved = saved
    }
  }

  private func fetch(_ feed: Feed, before id: String?) async throws -> [DiscoverPost] {
    switch feed {
    case .discover:
      return try await DiscoverAPI.discover(before: id, token: session.token)
    case .listenLater:
      guard let token = session.token else {
        throw APIError(message: "You need to be signed in to Micro.blog to load Listen Later.")
      }
      return try await DiscoverAPI.listenLater(before: id, token: token)
    }
  }

  private func pageSize(_ feed: Feed) -> Int {
    feed == .discover ? DiscoverAPI.discoverPageSize : DiscoverAPI.listenLaterPageSize
  }

  private func update(_ feed: Feed, _ change: (inout FeedState) -> Void) {
    switch feed {
    case .discover: change(&discover)
    case .listenLater: change(&listenLater)
    }
  }
}
