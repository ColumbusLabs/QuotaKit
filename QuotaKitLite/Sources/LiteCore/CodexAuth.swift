import CodexBarSync
import Foundation

/// Why `auth.json` couldn't be turned into usable credentials (068 §4.2 step 1).
public enum CodexAuthError: Error, Sendable, Equatable {
    /// No `auth.json` at the expected path: the user never ran `codex login`.
    case notFound
    /// The file exists but couldn't be read, or isn't a JSON object. Codex publishes it atomically, so this is
    /// usually transient or a permissions problem.
    case unreadable
    /// The file has no ChatGPT OAuth access token, for example an API-key-only login. Only a ChatGPT login has
    /// a rate limit to show.
    case noOAuthTokens
}

/// The parts of Codex's `auth.json` that Lite uses. Lite is read-only: it never refreshes or writes tokens
/// (068 §4.2), so there is no refresh token here.
///
/// Mirrors `CodexOAuthCredentialsStore`
/// (`Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthCredentials.swift`).
/// The access token is a secret: `description` and `debugDescription` redact it, and nothing in LiteCore logs it.
public struct CodexAuth: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    /// `tokens.account_id`, or a JWT claim when the file omits it. Sent as `ChatGPT-Account-Id`.
    public let accountID: String?
    /// From the `id_token` claims. Never from the access token.
    public let email: String?
    /// The access token's JWT `exp`, when it has a readable one.
    public let expiresAt: Date?
    /// `last_refresh`. Used only when the access token has no readable `exp`.
    public let lastRefresh: Date?

    public init(
        accessToken: String,
        accountID: String? = nil,
        email: String? = nil,
        expiresAt: Date? = nil,
        lastRefresh: Date? = nil)
    {
        self.accessToken = accessToken
        self.accountID = accountID
        self.email = email
        self.expiresAt = expiresAt
        self.lastRefresh = lastRefresh
    }

    public var description: String {
        "CodexAuth(redacted)"
    }

    public var debugDescription: String {
        self.description
    }

    /// How old `last_refresh` may get before a token without a readable `exp` counts as expired. The full app
    /// uses the same 8 days (`CodexOAuthCredentials.needsRefresh`).
    static let maxAgeWithoutExpiry: TimeInterval = 8 * 24 * 60 * 60

    /// True once the access token can no longer be used. Lite doesn't refresh, so an expired token means "run
    /// `codex` once" (068 §4.2 step 2). Unlike the full app, which treats the last 5 minutes as expired because
    /// it would refresh them, Lite uses the token until `exp`; a 401 right at the edge is handled by the
    /// re-read in `CodexProbe`.
    public func isExpired(now: Date) -> Bool {
        if let expiresAt {
            return expiresAt <= now
        }
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) > Self.maxAgeWithoutExpiry
    }

    /// `codex:email:<normalized>`, exactly what the full app's `AccountIdentityComputer.codex` writes for this
    /// login: its ambient OAuth path leaves `accountOrganization` nil, so it never emits `codex:account:`. Matching
    /// byte for byte is what lets iOS merge a Lite card with a full-app card (068 §2.2).
    public var accountIdentities: [String] {
        AccountIdentityNormalize.normalize(self.email).map { ["codex:email:\($0)"] } ?? []
    }
}

/// Finds and reads Codex's `auth.json`. The environment and home directory are injected so tests can use
/// temporary directories.
public struct CodexAuthReader: Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser)
    {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    /// `$CODEX_HOME/auth.json`, else `~/.codex/auth.json`, as in `CodexHomeScope.ambientHomeURL`. A blank
    /// `CODEX_HOME` counts as unset. The scheduler watches this file's directory (§5.1).
    public var authFileURL: URL {
        let home: URL = if let raw = self.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !raw.isEmpty
        {
            URL(fileURLWithPath: raw, isDirectory: true)
        } else {
            self.homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        }
        return home.appendingPathComponent("auth.json")
    }

    public func read() -> Result<CodexAuth, CodexAuthError> {
        let data: Data
        do {
            data = try Data(contentsOf: self.authFileURL)
        } catch {
            let nsError = error as NSError
            let missing = (nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.fileReadNoSuchFile
                .rawValue)
                || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
            return .failure(missing ? .notFound : .unreadable)
        }
        return Self.parse(data)
    }

    /// Parses the file's contents. Accepts the variants the full app does: snake_case or camelCase token keys,
    /// and an account ID that is missing from `tokens`. Ignores `OPENAI_API_KEY`, even beside OAuth tokens: an
    /// API key has no ChatGPT rate limit.
    public static func parse(_ data: Data) -> Result<CodexAuth, CodexAuthError> {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.unreadable)
        }
        guard let tokens = json["tokens"] as? [String: Any],
              let accessToken = Self.string(in: tokens, "access_token", "accessToken")
        else {
            return .failure(.noOAuthTokens)
        }
        let idToken = Self.string(in: tokens, "id_token", "idToken")
        let accountID = Self.nonEmpty(Self.string(in: tokens, "account_id", "accountId"))
            ?? Self.accountIDFromJWT(idToken: idToken, accessToken: accessToken)
        return .success(CodexAuth(
            accessToken: accessToken,
            accountID: accountID,
            email: Self.email(fromIDToken: idToken),
            expiresAt: JWTClaims.expiration(of: accessToken),
            lastRefresh: Self.parseLastRefresh(json["last_refresh"])))
    }

    // MARK: - Helpers

    private static func string(
        in dictionary: [String: Any],
        _ snakeCaseKey: String,
        _ camelCaseKey: String) -> String?
    {
        for key in [snakeCaseKey, camelCaseKey] {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func parseLastRefresh(_ raw: Any?) -> Date? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// Same claim order as the full app's `accountIDFromJWT`: the ID token, then the access token; within a
    /// token the top-level `chatgpt_account_id`, then `https://api.openai.com/auth`, then the first organization.
    private static func accountIDFromJWT(idToken: String?, accessToken: String) -> String? {
        for token in [idToken, accessToken].compactMap(\.self) {
            guard let payload = JWTClaims.payload(of: token) else { continue }
            if let accountID = Self.nonEmpty(payload["chatgpt_account_id"] as? String) {
                return accountID
            }
            if let auth = payload["https://api.openai.com/auth"] as? [String: Any],
               let accountID = Self.nonEmpty(auth["chatgpt_account_id"] as? String)
            {
                return accountID
            }
            if let organizations = payload["organizations"] as? [[String: Any]],
               let accountID = organizations.compactMap({ Self.nonEmpty($0["id"] as? String) }).first
            {
                return accountID
            }
        }
        return nil
    }

    /// Same claims as the full app's `resolveAccountEmail`: `email`, then `https://api.openai.com/profile`.`email`.
    private static func email(fromIDToken idToken: String?) -> String? {
        guard let idToken, let payload = JWTClaims.payload(of: idToken) else { return nil }
        let profile = payload["https://api.openai.com/profile"] as? [String: Any]
        return Self.nonEmpty((payload["email"] as? String) ?? (profile?["email"] as? String))
    }
}

/// Unverified JWT payload reading. The tokens come from the user's own CLI, so this is a hint, not
/// authentication; the server still authenticates the bearer token.
enum JWTClaims {
    /// Codex's own timestamp range (chrono 0.4), as in the full app.
    private static let expirationRange: ClosedRange<Int64> = -8_334_601_228_800...8_210_266_876_799

    private struct ExpirationClaim: Decodable {
        let exp: Int64?
    }

    /// The decoded payload, or nil unless the token has three dot-separated parts and a JSON-object payload.
    static func payload(of token: String) -> [String: Any]? {
        guard let data = payloadData(of: token, requireAllParts: false) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The integer `exp` claim as a date. Nil when the token isn't a well-formed JWT, `exp` is absent or isn't
    /// an integer, or it is outside Codex's date range. The caller then falls back to `last_refresh` age.
    static func expiration(of token: String) -> Date? {
        guard let data = payloadData(of: token, requireAllParts: true),
              let claim = try? JSONDecoder().decode(ExpirationClaim.self, from: data),
              let exp = claim.exp,
              expirationRange.contains(exp)
        else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(exp))
    }

    private static func payloadData(of token: String, requireAllParts: Bool) -> Data? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !requireAllParts || parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        return Data(base64Encoded: encoded)
    }
}
