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
/// - cap at `maxAccountIdentifierLength` (256 chars) to bound cache
///   growth on pathological inputs
public enum AccountIdentityNormalize {
    public static let maxAccountIdentifierLength = 256

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
            return String(encoded.prefix(Self.maxAccountIdentifierLength))
        }
        return encoded
    }
}
