import Foundation
import Observation

@Observable
final class Session {
  enum Phase {
    case idle
    case connecting
    case verifying
  }

  private(set) var token: String?
  private(set) var profile: UserProfile?
  private(set) var destinations: [BlogDestination] = []
  private(set) var selectedDestination: BlogDestination?
  private(set) var phase: Phase = .idle
  private(set) var isHydrated = false
  private(set) var isLoadingDestinations = false
  var errorMessage: String?
  var destinationErrorMessage: String?

  var isSignedIn: Bool { token.nonEmpty != nil }
  var isBusy: Bool { phase != .idle }

  var destinationUID: String? {
    selectedDestination?.uid ?? profile?.defaultSite
  }

  var destinationName: String {
    selectedDestination?.name ?? profile?.defaultSite ?? "Micro.blog"
  }

  var displayName: String {
    profile?.name ?? profile?.username ?? "Micro.blog account"
  }

  var micropub: Micropub? {
    guard let token = token.nonEmpty else { return nil }
    return Micropub(token: token, destination: destinationUID)
  }

  func requireMicropub(_ action: String = "publish") throws -> Micropub {
    guard let micropub else {
      throw APIError(message: "You need to be signed in to Micro.blog to \(action).")
    }

    return micropub
  }

  func hydrate() async {
    guard !isHydrated else { return }

    let stored = Keychain.load()
    token = stored.userToken.nonEmpty

    if let uid = stored.selectedDestinationUID.nonEmpty {
      selectedDestination = BlogDestination(uid: uid, name: stored.selectedDestinationName.nonEmpty ?? uid)
    }

    isHydrated = true

    guard let token else { return }

    phase = .verifying
    defer { phase = .idle }

    do {
      let verification = try await MicroBlogAuth.verify(token: token)
      applyVerification(verification, fallbackToken: token)
      await loadDestinations()
    } catch let error as APIError where error.isUnauthorized {
      clearSession(message: "Your Micro.blog session expired. Please sign in again.")
    } catch {
      return
    }
  }

  func signIn(authenticate: (URL) async throws -> URL) async {
    guard !isBusy else { return }

    errorMessage = nil
    phase = .connecting
    defer { phase = .idle }

    let state = MicroBlogAuth.makeState()
    let callback: URL

    do {
      callback = try await authenticate(MicroBlogAuth.authorizationURL(state: state))
    } catch {
      if !isCancellation(error) {
        errorMessage = "Micro.blog sign in did not complete. Please try again."
      }
      return
    }

    if let legacyToken = MicroBlogAuth.legacyToken(from: callback) {
      phase = .idle
      await signIn(token: legacyToken)
      return
    }

    let parameters = MicroBlogAuth.callbackParameters(callback)

    guard !parameters.code.isEmpty else {
      errorMessage = "Micro.blog did not return an authorization code. Please try again."
      return
    }

    guard parameters.state == state else {
      errorMessage = "Micro.blog sign in could not be verified. Please try again."
      return
    }

    phase = .verifying

    do {
      let exchange = try await MicroBlogAuth.exchange(code: parameters.code)
      profile = exchange.profile
      store(token: exchange.accessToken)

      if let verification = try? await MicroBlogAuth.verify(token: exchange.accessToken) {
        applyVerification(verification, fallbackToken: exchange.accessToken)
      }

      await loadDestinations()
    } catch {
      clearSession(message: "We could not finish signing you in. Please try again.")
    }
  }

  @discardableResult
  func signIn(token rawToken: String) async -> Bool {
    let candidate = rawToken.trimmed
    errorMessage = nil

    guard !candidate.isEmpty else {
      errorMessage = "Enter a Micro.blog token to sign in."
      return false
    }

    phase = .verifying
    defer { phase = .idle }

    do {
      let verification = try await MicroBlogAuth.verify(token: candidate)
      applyVerification(verification, fallbackToken: candidate)
      await loadDestinations()
      return true
    } catch let error as APIError where error.isUnauthorized {
      clearSession(message: "That Micro.blog token is not valid. Please try again.")
      return false
    } catch {
      clearSession(message: "We could not sign you in with that token. Please try again.")
      return false
    }
  }

  func handleOpenURL(_ url: URL) async {
    if let legacyToken = MicroBlogAuth.legacyToken(from: url) {
      await signIn(token: legacyToken)
    }
  }

  func loadDestinations() async {
    guard let micropub else {
      destinationErrorMessage = "You need to be signed in to load your blogs."
      return
    }

    isLoadingDestinations = true
    destinationErrorMessage = nil
    defer { isLoadingDestinations = false }

    do {
      let loaded = try await micropub.config()

      guard micropub.token == token else { return }

      destinations = loaded

      let saved = selectedDestination.flatMap { saved in loaded.first { $0.uid == saved.uid } }
      let fallback = loaded.first(where: \.isDefault) ?? loaded.first
      selectedDestination = saved ?? fallback
      persist()
    } catch {
      destinations = []
      destinationErrorMessage = error.localizedDescription
    }
  }

  func select(_ destination: BlogDestination) {
    selectedDestination = destination
    persist()
  }

  func signOut() {
    Keychain.clear()
    token = nil
    profile = nil
    destinations = []
    selectedDestination = nil
    errorMessage = nil
  }

  func clearSession(message: String?) {
    signOut()
    errorMessage = message
  }

  private func applyVerification(_ verification: MicroBlogAuth.Verification, fallbackToken: String) {
    store(token: verification.token ?? fallbackToken)

    var merged = verification.profile
    merged.name = merged.name ?? profile?.name ?? merged.username
    merged.username = merged.username ?? profile?.username
    merged.photo = merged.photo ?? profile?.photo
    merged.url = merged.url ?? profile?.url
    profile = merged
  }

  private func store(token newToken: String) {
    token = newToken.trimmed
    persist()
  }

  private func persist() {
    Keychain.save(StoredTokens(
      userToken: token,
      selectedDestinationUID: selectedDestination?.uid,
      selectedDestinationName: selectedDestination?.name
    ))
  }

  private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError {
      return true
    }

    let nsError = error as NSError
    return nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && nsError.code == 1
  }
}
