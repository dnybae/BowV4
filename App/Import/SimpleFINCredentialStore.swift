import Foundation
import Security

struct SimpleFINCredentialStore {
  private var service: String { (Bundle.main.bundleIdentifier ?? "Bow") + ".simplefin" }
  private var account = "access-url"

  func load() throws -> URL? {
    var result: CFTypeRef?
    let status = SecItemCopyMatching([
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne
    ] as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess,
          let data = result as? Data,
          let string = String(data: data, encoding: .utf8),
          let url = URL(string: string) else {
      throw SimpleFINError.credentialStorage
    }
    return url
  }

  func save(_ url: URL) throws {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account
    ]
    SecItemDelete(query as CFDictionary)
    var item = query
    item[kSecValueData] = Data(url.absoluteString.utf8)
    item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
      throw SimpleFINError.credentialStorage
    }
  }

  func delete() throws {
    let status = SecItemDelete([
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account
    ] as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw SimpleFINError.credentialStorage
    }
  }
}
