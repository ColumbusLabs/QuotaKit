import Foundation
import LiteCore
import Security

/// Lite's own Keychain item holding the last Claude token it read (068 §4.1 step 2).
///
/// Lite creates this item, so reading it doesn't prompt and saves a `security` run on every launch. The no-UI flags
/// are added anyway so a mismatched signature fails quietly (treated as "no cache") instead of showing a dialog.
struct LiteKeychainTokenCache: ClaudeTokenCaching {
    static let service = "com.columbuslabs.quotakit.lite.cache"
    static let account = "claude"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func loadCachedToken() -> Data? {
        var query = self.baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        LiteKeychainNoUIQuery.apply(to: &query)

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func saveCachedToken(_ data: Data) {
        var query = self.baseQuery
        LiteKeychainNoUIQuery.apply(to: &query)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var item = self.baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "QuotaKit Lite Claude token cache"
        SecItemAdd(item as CFDictionary, nil)
    }

    func clearCachedToken() {
        var query = self.baseQuery
        LiteKeychainNoUIQuery.apply(to: &query)
        SecItemDelete(query as CFDictionary)
    }
}
