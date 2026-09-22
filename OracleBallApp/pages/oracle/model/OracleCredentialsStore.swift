import Foundation
import Security

/// Stores the optional TypeSafe credential in the device Keychain.
struct OracleCredentialsStore {
  private let service: String
  private let account = "typesafe-api-key"

  init(service: String = "com.soundblaster.oracleball") {
    self.service = service
  }

  func readAPIKey() -> String? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data,
          let value = String(data: data, encoding: .utf8),
          !value.isEmpty
    else {
      return nil
    }
    return value
  }

  func saveAPIKey(_ value: String) throws {
    let data = Data(value.utf8)
    var query = baseQuery
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let status = SecItemUpdate(baseQuery as CFDictionary, query as CFDictionary)
    if status == errSecItemNotFound {
      let addStatus = SecItemAdd(query as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw OracleCredentialsError(status: addStatus) }
    } else if status != errSecSuccess {
      throw OracleCredentialsError(status: status)
    }
  }

  func deleteAPIKey() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw OracleCredentialsError(status: status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

private struct OracleCredentialsError: LocalizedError {
  let status: OSStatus

  var errorDescription: String? {
    "Could not update the secure API key storage (Keychain status \(status))."
  }
}
