import Foundation
import OSLog
import Security

nonisolated struct StoredTokens: Codable, Sendable {
  var userToken: String?
  var selectedDestinationUID: String?
  var selectedDestinationName: String?

  enum CodingKeys: String, CodingKey {
    case userToken = "user_token"
    case selectedDestinationUID = "selected_destination_uid"
    case selectedDestinationName = "selected_destination_name"
  }
}

nonisolated enum Keychain {
  static let service = "blog.micro.wavelength"
  static let account = "WavelengthTokens"
  private static let log = Logger(subsystem: "blog.micro.wavelength", category: "Keychain")

  static func load() -> StoredTokens {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    if status != errSecSuccess, status != errSecItemNotFound {
      log.error("Keychain read failed: \(status)")
    }

    guard status == errSecSuccess,
          let data = result as? Data,
          let tokens = try? JSONDecoder().decode(StoredTokens.self, from: data) else {
      return StoredTokens()
    }

    return tokens
  }

  static func save(_ tokens: StoredTokens) {
    guard tokens.userToken.nonEmpty != nil else {
      clear()
      return
    }

    guard let data = try? JSONEncoder().encode(tokens) else { return }

    let update = [kSecValueData as String: data]
    let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)

    if status == errSecItemNotFound {
      var insert = baseQuery
      insert[kSecValueData as String] = data
      let added = SecItemAdd(insert as CFDictionary, nil)

      if added != errSecSuccess {
        log.error("Keychain write failed: \(added)")
      }
    } else if status != errSecSuccess {
      log.error("Keychain update failed: \(status)")
    }
  }

  static func clear() {
    SecItemDelete(baseQuery as CFDictionary)
  }

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
