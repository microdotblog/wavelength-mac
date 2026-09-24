import Foundation

nonisolated enum MicroBlogAuth {
  static let authURL = URL(string: "https://micro.blog/indieauth/auth")!
  static let tokenURL = URL(string: "https://micro.blog/indieauth/token")!
  static let verifyURL = URL(string: "https://micro.blog/account/verify")!
  static let clientID = "https://micro.blog/wavelength/"
  static let scope = "read write"
  static let scheme = "wavelength"
  static let redirectURI = "wavelength://auth/callback"

  struct Verification: Sendable {
    var token: String?
    var profile: UserProfile
  }

  struct TokenExchange: Sendable {
    var accessToken: String
    var profile: UserProfile
  }

  static func makeState() -> String {
    (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
  }

  static func authorizationURL(state: String) -> URL {
    var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: scope),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "wavelength", value: "1"),
      URLQueryItem(name: "app", value: "1"),
    ]
    return components.url!
  }

  static func callbackParameters(_ url: URL) -> (code: String, state: String) {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let code = items.first { $0.name == "code" }?.value?.trimmed ?? ""
    let state = items.first { $0.name == "state" }?.value?.trimmed ?? ""
    return (code, state)
  }

  static func legacyToken(from url: URL) -> String? {
    guard url.scheme == scheme, url.host() == "micropub" || url.host() == "signin" else {
      return nil
    }

    return url.pathComponents.filter { $0 != "/" }.last.nonEmpty
  }

  static func exchange(code: String) async throws -> TokenExchange {
    let request = try HTTP.request(tokenURL, method: "POST", form: [
      ("client_id", clientID),
      ("code", code),
      ("grant_type", "authorization_code"),
      ("redirect_uri", redirectURI),
    ])
    let (payload, response) = try await HTTP.send(request)

    if HTTP.isFailure(payload, response) {
      throw APIError(
        message: HTTP.errorMessage(payload, fallback: "Micro.blog token exchange failed."),
        status: response.statusCode
      )
    }

    let accessToken = payload?.string("access_token") ?? ""

    guard !accessToken.isEmpty else {
      throw APIError(message: "Micro.blog did not return an access token.")
    }

    let profile = payload?.object("profile") ?? [:]
    let me = payload?.string("me")

    return TokenExchange(
      accessToken: accessToken,
      profile: UserProfile(
        username: profile.string("nickname").replacingOccurrences(of: "@", with: "").nonEmptyValue,
        name: profile.string("name").nonEmptyValue,
        photo: URL(string: profile.string("photo")),
        url: URL(string: profile.string("url").nonEmptyValue ?? me ?? "")
      )
    )
  }

  static func verify(token: String) async throws -> Verification {
    let trimmed = token.trimmed

    guard !trimmed.isEmpty else {
      throw APIError(message: "A Micro.blog token is required before verification.")
    }

    let request = try HTTP.request(verifyURL, method: "POST", token: trimmed, form: [("token", trimmed)])
    let (payload, response) = try await HTTP.send(request)

    if HTTP.isFailure(payload, response) {
      throw APIError(
        message: HTTP.errorMessage(payload, fallback: "Micro.blog verify failed."),
        status: response.statusCode
      )
    }

    let body = payload ?? [:]
    let photo = body.string("avatar").nonEmptyValue ?? body.string("photo")

    return Verification(
      token: body.string("token").nonEmptyValue,
      profile: UserProfile(
        username: body.string("username").replacingOccurrences(of: "@", with: "").nonEmptyValue,
        name: body.string("name").nonEmptyValue,
        photo: URL(string: photo),
        url: URL(string: body.string("url").nonEmptyValue ?? body.string("me")),
        defaultSite: body.string("default_site").nonEmptyValue,
        hasSite: body["has_site"] as? Bool
      )
    )
  }
}

extension String {
  nonisolated var nonEmptyValue: String? {
    let value = trimmed
    return value.isEmpty ? nil : value
  }
}
