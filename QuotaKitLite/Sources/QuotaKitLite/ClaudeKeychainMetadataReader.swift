import Foundation
import LiteCore
import Security

/// The attributes-only change check on Claude Code's Keychain item (068 §4.1 step 3).
///
/// Asks only for attributes (`kSecReturnAttributes`), never for data (`kSecReturnData`), with the no-UI flags. Phase 0
/// showed this never prompts, even right after Claude Code rewrites the item and its ACL.
struct ClaudeKeychainMetadataReader: ClaudeKeychainMetadataReading {
    static let service = "Claude Code-credentials"

    func claudeCredentialsItemState() -> ClaudeKeychainItemState {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        LiteKeychainNoUIQuery.apply(to: &query)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return .notFound
        default:
            return .unavailable
        }

        let rows: [[String: Any]] = if let rows = result as? [[String: Any]] {
            rows
        } else if let row = result as? [String: Any] {
            [row]
        } else {
            []
        }
        guard !rows.isEmpty else { return .notFound }
        // Like the full app's `claudeKeychainCandidatesProbeWithoutPrompt`, the newest item is the one that matters.
        let newest = rows.compactMap { $0[kSecAttrModificationDate as String] as? Date }.max()
        return .found(modifiedAt: newest)
    }
}
