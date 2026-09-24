import Foundation

nonisolated struct APIError: LocalizedError, Sendable {
  let message: String
  var status: Int?

  var errorDescription: String? { message }

  var isUnauthorized: Bool { status == 401 || status == 403 }
}

typealias JSONObject = [String: Any]

nonisolated enum HTTP {
  static let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 60
    configuration.timeoutIntervalForResource = 60 * 30
    return URLSession(configuration: configuration)
  }()

  static func formEncode(_ pairs: [(String, String)]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "*-._ ")

    let body = pairs.map { key, value in
      "\(encode(key, allowed))=\(encode(value, allowed))"
    }
    .joined(separator: "&")

    return Data(body.utf8)
  }

  static func request(
    _ url: URL,
    method: String = "GET",
    token: String? = nil,
    form: [(String, String)]? = nil,
    json: JSONObject? = nil
  ) throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    if let token = token.nonEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    if let form {
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      request.httpBody = formEncode(form)
    } else if let json {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: json)
    }

    return request
  }

  static func send(_ request: URLRequest) async throws -> (JSONObject?, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw APIError(message: "Micro.blog returned an unexpected response.")
    }

    return (parse(data), http)
  }

  static func parse(_ data: Data) -> JSONObject? {
    guard !data.isEmpty else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
  }

  static func isFailure(_ payload: JSONObject?, _ response: HTTPURLResponse) -> Bool {
    guard (200..<300).contains(response.statusCode) else { return true }

    if let error = payload?["error"], !(error is NSNull) {
      return true
    }

    return false
  }

  static func errorMessage(_ payload: JSONObject?, fallback: String) -> String {
    let description = (payload?["error_description"] as? String).nonEmpty
    let error = (payload?["error"] as? String).nonEmpty
    return description ?? error ?? fallback
  }

  static func location(_ response: HTTPURLResponse, _ payload: JSONObject?) -> String {
    let header = (response.value(forHTTPHeaderField: "Location")).nonEmpty
    return header ?? (payload?["url"] as? String).nonEmpty ?? ""
  }

  private static func encode(_ value: String, _ allowed: CharacterSet) -> String {
    (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
      .replacingOccurrences(of: " ", with: "+")
  }
}

nonisolated extension JSONObject {
  func string(_ key: String) -> String {
    if let value = self[key] as? String {
      return value.trimmed
    }

    if let value = self[key] as? NSNumber {
      return value.stringValue
    }

    return ""
  }

  func object(_ key: String) -> JSONObject? {
    self[key] as? JSONObject
  }

  func objects(_ key: String) -> [JSONObject] {
    self[key] as? [JSONObject] ?? []
  }

  func property(_ name: String) -> String {
    let value = object("properties")?[name]

    if let array = value as? [Any] {
      return "\(array.first ?? "")".trimmed
    }

    if let string = value as? String {
      return string.trimmed
    }

    return ""
  }

  func propertyArray(_ name: String) -> [String] {
    let value = object("properties")?[name] as? [Any] ?? []
    return value.map { "\($0)".trimmed }.filter { !$0.isEmpty }
  }
}
