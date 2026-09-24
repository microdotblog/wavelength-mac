import Foundation

nonisolated enum DiscoverAPI {
  static let discoverURL = URL(string: "https://micro.blog/posts/discover")!
  static let listenLaterURL = URL(string: "https://micro.blog/posts/bookmarks/listenlater")!
  static let bookmarksURL = URL(string: "https://micro.blog/posts/bookmarks")!
  static let podcastsTopic = "podcasts"
  static let discoverPageSize = 40
  static let listenLaterPageSize = 25

  static func discover(topic: String = podcastsTopic, before id: String? = nil, token: String?) async throws -> [DiscoverPost] {
    let url = discoverURL.appending(path: topic)
    return try await fetch(url, before: id, token: token, fallback: "We could not load Discover posts.")
  }

  static func listenLater(before id: String? = nil, token: String) async throws -> [DiscoverPost] {
    try await fetch(listenLaterURL, before: id, token: token, fallback: "We could not load Listen Later.")
  }

  static func save(id: String, token: String) async throws {
    var components = URLComponents(url: bookmarksURL, resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "id", value: id)]
    let request = try HTTP.request(components.url!, method: "POST", token: token)
    let (payload, response) = try await HTTP.send(request)

    if HTTP.isFailure(payload, response) {
      throw APIError(
        message: HTTP.errorMessage(payload, fallback: "We could not save that Listen Later episode."),
        status: response.statusCode
      )
    }
  }

  static func remove(id: String, token: String) async throws {
    let request = try HTTP.request(bookmarksURL.appending(path: id), method: "DELETE", token: token)
    let (payload, response) = try await HTTP.send(request)

    if HTTP.isFailure(payload, response) {
      throw APIError(
        message: HTTP.errorMessage(payload, fallback: "We could not remove that Listen Later episode."),
        status: response.statusCode
      )
    }
  }

  static func posts(from payload: JSONObject?) -> [DiscoverPost] {
    (payload?.objects("items") ?? []).compactMap(post)
  }

  static func avatarURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmed

    guard !trimmed.isEmpty else { return nil }

    if let match = trimmed.firstMatch(of: #/cdn\.micro\.blog\/photos\/\d+\/(.+)$/#.ignoresCase()),
       let decoded = String(match.output.1).removingPercentEncoding?.nonEmptyValue {
      return URL(string: decoded)
    }

    return URL(string: trimmed)
  }

  static func title(from html: String) -> String {
    let preview = previewText(html)

    guard !preview.isEmpty else { return "" }

    let title = preview
      .replacing(#/\s*:\s*[\w.-]+\.(com|blog|org|net|io|co|dev|app|micro\.blog)\/?\s*$/#.ignoresCase(), with: "")
      .trimmed

    return title.isEmpty ? preview : title
  }

  static func imageURL(from html: String) -> URL? {
    guard let match = html.firstMatch(of: #/<img[^>]+src=["']([^"']+)["']/#.ignoresCase()) else {
      return nil
    }

    return URL(string: PostContent.decodeEntities(String(match.output.1)).trimmed)
  }

  private static func previewText(_ html: String) -> String {
    let text = PostContent.decodeEntities(
      html
        .replacing(#/<\s*br\s*\/?>/#.ignoresCase(), with: " ")
        .replacing(#/<\s*\/\s*p\s*>/#.ignoresCase(), with: " ")
        .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmed
    )

    if text.count <= 280 {
      return text
    }

    return String(text.prefix(277)).trimmed + "..."
  }

  private static func post(from item: JSONObject) -> DiscoverPost? {
    let id = item.string("id")
    let url = item.string("url")

    guard !id.isEmpty, !url.isEmpty else { return nil }

    let html = item.string("content_html")
    let microblog = item.object("_microblog") ?? [:]
    let audio = microblog.object("audio") ?? [:]
    let author = item.object("author") ?? [:]
    let duration = Double(audio.string("duration_seconds")).map { Int($0) } ?? 0

    return DiscoverPost(
      id: id,
      url: url,
      title: title(from: html),
      summary: Formatting.collapseWhitespace(item.string("summary")),
      authorName: author.string("name"),
      authorUsername: author.object("_microblog")?.string("username") ?? "",
      authorAvatar: avatarURL(author.string("avatar")),
      authorURL: URL(string: author.string("url")),
      audioURL: URL(string: audio.string("url")),
      imageURL: imageURL(from: html),
      durationSeconds: max(duration, 0),
      durationDisplay: audio.string("duration_display"),
      dateRelative: microblog.string("date_relative"),
      publishedAt: item.string("date_published"),
      isPodcast: microblog["is_podcast"] as? Bool == true,
      isSaved: microblog["is_favorite"] as? Bool == true || microblog["is_bookmark"] as? Bool == true
    )
  }

  private static func fetch(_ url: URL, before id: String?, token: String?, fallback: String) async throws -> [DiscoverPost] {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!

    if let id = id.nonEmpty {
      components.queryItems = [URLQueryItem(name: "before_id", value: id)]
    }

    let request = try HTTP.request(components.url!, token: token)
    let (payload, response) = try await HTTP.send(request)

    if HTTP.isFailure(payload, response) {
      throw APIError(message: HTTP.errorMessage(payload, fallback: fallback), status: response.statusCode)
    }

    return posts(from: payload)
  }
}
