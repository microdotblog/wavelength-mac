import Foundation

nonisolated struct Micropub: Sendable {
  static let endpoint = URL(string: "https://micro.blog/micropub")!
  static let mediaEndpoint = URL(string: "https://micro.blog/micropub/media")!

  let token: String
  let destination: String?

  struct NewPost: Sendable {
    var title: String
    var content: String
    var audioURL: String
    var status: String
    var summary: String
    var categories: [String]
    var syndicates: [String]
  }

  struct PostUpdate: Sendable {
    var url: String
    var title: String
    var content: String
    var status: String
    var summary: String
    var categories: [String]
    var audioURL: String?
  }

  static func audioMimeType(for url: URL) -> String {
    url.pathExtension.lowercased() == "mp3" ? "audio/mpeg" : "audio/mp4"
  }

  static func destinations(from payload: JSONObject?) -> [BlogDestination] {
    (payload?.objects("destination") ?? []).compactMap { item in
      let uid = item.string("uid")

      guard !uid.isEmpty else { return nil }

      let name = item.string("name").nonEmptyValue ?? URL(string: uid)?.host() ?? uid
      return BlogDestination(uid: uid, name: name, isDefault: item["microblog-default"] as? Bool == true)
    }
  }

  static func posts(from payload: JSONObject?) -> [Post] {
    (payload?.objects("items") ?? [])
      .compactMap { item -> Post? in
        let uid = item.property("uid")
        let url = item.property("url")
        let status = item.property("post-status").nonEmptyValue ?? "published"

        guard !uid.isEmpty, !url.isEmpty, status != "draft" else { return nil }

        return Post(
          uid: uid,
          url: url,
          title: item.property("name"),
          content: item.property("content"),
          summary: item.property("summary"),
          status: status,
          publishedAt: item.property("published"),
          categories: item.propertyArray("category")
        )
      }
      .sorted { $0.publishedAt > $1.publishedAt }
  }

  static func source(from payload: JSONObject) -> PostSource {
    PostSource(
      uid: payload.property("uid"),
      url: payload.property("url"),
      title: payload.property("name"),
      content: payload.property("content"),
      summary: payload.property("summary"),
      status: payload.property("post-status").nonEmptyValue ?? "published",
      categories: payload.propertyArray("category")
    )
  }

  static func newPostForm(_ post: NewPost, destination: String?) -> [(String, String)] {
    var form: [(String, String)] = [
      ("audio", post.audioURL.trimmed),
      ("content", post.content),
      ("h", "entry"),
      ("name", post.title),
    ]

    if let destination = destination.nonEmpty {
      form.append(("mp-destination", destination))
    }

    if let status = post.status.nonEmptyValue {
      form.append(("post-status", status))
    }

    if let summary = post.summary.nonEmptyValue {
      form.append(("summary", summary))
    }

    form += post.categories.compactMap(\.nonEmptyValue).map { ("category[]", $0) }
    form += post.syndicates.compactMap(\.nonEmptyValue).map { ("mp-syndicate-to[]", $0) }

    return form
  }

  static func updateBody(_ update: PostUpdate, destination: String?) -> JSONObject {
    var replace: JSONObject = [
      "category": update.categories.compactMap(\.nonEmptyValue),
      "content": [update.content],
      "name": [update.title],
      "post-status": [update.status.nonEmptyValue ?? "published"],
      "summary": [update.summary.trimmed],
    ]

    if let audioURL = update.audioURL.nonEmpty {
      replace["audio"] = [audioURL]
    }

    var body: JSONObject = [
      "action": "update",
      "replace": replace,
      "url": update.url.trimmed,
    ]

    if let destination = destination.nonEmpty {
      body["mp-destination"] = destination
    }

    return body
  }

  func config() async throws -> [BlogDestination] {
    guard let payload = try await query("config", includeDestination: false) else {
      throw APIError(message: "We could not load your blogs.")
    }

    return Self.destinations(from: payload)
  }

  func categories() async -> [String] {
    let payload = try? await query("category")

    if let list = payload?["categories"] as? [Any] {
      return list.map { "\($0)".trimmed }.filter { !$0.isEmpty }
    }

    return []
  }

  func syndicationTargets() async -> [SyndicationTarget] {
    let payload = try? await query("syndicate-to")

    return (payload?.objects("syndicate-to") ?? []).compactMap { target in
      let uid = target.string("uid")
      guard !uid.isEmpty else { return nil }
      return SyndicationTarget(uid: uid, name: target.string("name").nonEmptyValue ?? uid)
    }
  }

  func posts() async throws -> [Post] {
    guard let payload = try await query("source") else {
      throw APIError(message: "We could not load your posts.")
    }

    return Self.posts(from: payload)
  }

  func source(of postURL: String) async throws -> PostSource? {
    guard let payload = try await query("source", url: postURL) else {
      return nil
    }

    return Self.source(from: payload)
  }

  @concurrent func uploadAudio(
    _ fileURL: URL,
    filename: String,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> String {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw APIError(message: "This episode has no audio to upload.")
    }

    let boundary = "Wavelength-\(UUID().uuidString)"
    let bodyURL = FileManager.default.temporaryDirectory.appending(path: "upload-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: bodyURL) }

    try Self.writeMultipartBody(
      to: bodyURL,
      boundary: boundary,
      destination: destination,
      fileURL: fileURL,
      filename: filename.nonEmptyValue ?? fileURL.lastPathComponent
    )

    var request = try HTTP.request(Self.mediaEndpoint, method: "POST", token: token)
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let delegate = UploadProgressDelegate(progress: progress)
    let (data, response) = try await HTTP.session.upload(for: request, fromFile: bodyURL, delegate: delegate)

    guard let http = response as? HTTPURLResponse else {
      throw APIError(message: "We could not upload the episode audio.")
    }

    let payload = HTTP.parse(data)

    if HTTP.isFailure(payload, http) {
      throw APIError(
        message: HTTP.errorMessage(payload, fallback: "We could not upload the episode audio."),
        status: http.statusCode
      )
    }

    let audioURL = HTTP.location(http, payload)

    guard !audioURL.isEmpty else {
      throw APIError(message: "Micro.blog did not return an audio URL.")
    }

    return audioURL
  }

  func create(_ post: NewPost) async throws -> String {
    guard !post.audioURL.trimmed.isEmpty else {
      throw APIError(message: "The episode audio must be uploaded before posting.")
    }

    let request = try HTTP.request(
      Self.endpoint,
      method: "POST",
      token: token,
      form: Self.newPostForm(post, destination: destination)
    )
    let (payload, response) = try await HTTP.send(request)

    if HTTP.isFailure(payload, response) {
      throw APIError(
        message: HTTP.errorMessage(payload, fallback: "We could not publish the episode."),
        status: response.statusCode
      )
    }

    return HTTP.location(response, payload)
  }

  func update(_ update: PostUpdate) async throws {
    guard !update.url.trimmed.isEmpty else {
      throw APIError(message: "A post URL is required to update this post.")
    }

    let body = Self.updateBody(update, destination: destination)
    let request = try HTTP.request(Self.endpoint, method: "POST", token: token, json: body)
    let (payload, response) = try await HTTP.send(request)

    if HTTP.isFailure(payload, response) {
      throw APIError(
        message: HTTP.errorMessage(payload, fallback: "We could not update the post."),
        status: response.statusCode
      )
    }
  }

  func delete(postURL: String) async throws {
    guard !postURL.trimmed.isEmpty else {
      throw APIError(message: "A post URL is required to delete the published post.")
    }

    var form = [("action", "delete"), ("url", postURL.trimmed)]

    if let destination = destination.nonEmpty {
      form.append(("mp-destination", destination))
    }

    let request = try HTTP.request(Self.endpoint, method: "POST", token: token, form: form)
    let (payload, response) = try await HTTP.send(request)

    if HTTP.isFailure(payload, response) {
      throw APIError(
        message: HTTP.errorMessage(payload, fallback: "We could not delete the published post."),
        status: response.statusCode
      )
    }
  }

  private func query(_ name: String, url: String? = nil, includeDestination: Bool = true) async throws -> JSONObject? {
    var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
    var items = [URLQueryItem(name: "q", value: name)]

    if let url = url.nonEmpty {
      items.append(URLQueryItem(name: "url", value: url))
    }

    if includeDestination, let destination = destination.nonEmpty {
      items.append(URLQueryItem(name: "mp-destination", value: destination))
    }

    components.queryItems = items

    let request = try HTTP.request(components.url!, token: token)
    let (payload, response) = try await HTTP.send(request)

    if HTTP.isFailure(payload, response) {
      if response.statusCode == 401 || response.statusCode == 403 {
        throw APIError(message: "Your Micro.blog session expired. Please sign in again.", status: response.statusCode)
      }

      return nil
    }

    return payload
  }

  static func writeMultipartBody(to bodyURL: URL, boundary: String, destination: String?, fileURL: URL, filename: String) throws {
    FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
    let handle = try FileHandle(forWritingTo: bodyURL)
    defer { try? handle.close() }

    if let destination = destination.nonEmpty {
      try handle.write(contentsOf: Data(
        "--\(boundary)\r\nContent-Disposition: form-data; name=\"mp-destination\"\r\n\r\n\(destination)\r\n".utf8
      ))
    }

    let safeFilename = filename.replacingOccurrences(of: "\"", with: "")
    try handle.write(contentsOf: Data(
      "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\nContent-Type: \(Self.audioMimeType(for: URL(filePath: safeFilename)))\r\n\r\n".utf8
    ))

    let source = try FileHandle(forReadingFrom: fileURL)
    defer { try? source.close() }

    while let chunk = try source.read(upToCount: 1 << 20), !chunk.isEmpty {
      try handle.write(contentsOf: chunk)
    }

    try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
  }
}

private nonisolated final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
  let progress: (@Sendable (Double) -> Void)?

  init(progress: (@Sendable (Double) -> Void)?) {
    self.progress = progress
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    guard totalBytesExpectedToSend > 0 else { return }
    progress?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
  }
}
