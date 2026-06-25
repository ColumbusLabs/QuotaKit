import CryptoKit
import Foundation

/// Shared normalization for account-identity strings used in
/// `accountIdentities: [String]?` on `ProviderUsageSnapshot`.
///
/// Both the Mac (`AccountIdentityComputer.normalize` in CodexBarCore)
/// and iOS (`CloudSyncReader.effectiveIdentifiers` in CodexBarMobile)
/// call this so cross-version merging via `email` synthesis matches
/// byte-for-byte. If only one side normalizes, accounts with non-ASCII
/// characters (`café@example.com`), trailing whitespace, mixed case,
/// or any decomposed-Unicode characters silently split into separate
/// cards on iOS.
///
/// Steps:
/// - lowercase
/// - Unicode NFC (canonical composition)
/// - trim whitespace
/// - URL-percent-encode (so `:` / `|` / `/` can't accidentally collide
///   with the `{provider}:{scheme}:{value}` separator)
/// - cap at `maxAccountIdentifierLength` (256 chars) using a readable
///   prefix plus SHA-256 suffix, so pathological inputs stay bounded
///   without allowing prefix collisions
public enum AccountIdentityNormalize {
    public static let maxAccountIdentifierLength = 256
    private static let hashMarker = "#sha256#"
    private static let sha256HexLength = 64

    public static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        let nfc = lowered.precomposedStringWithCanonicalMapping
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: ":|/"))
        guard let encoded = nfc.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        if encoded.count > Self.maxAccountIdentifierLength {
            return Self.capWithDigest(encoded)
        }
        return encoded
    }

    private static func capWithDigest(_ encoded: String) -> String {
        let digest = SHA256.hash(data: Data(encoded.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let prefixLength = Self.maxAccountIdentifierLength
            - Self.hashMarker.count
            - Self.sha256HexLength
        return String(encoded.prefix(prefixLength)) + Self.hashMarker + digest
    }
}
