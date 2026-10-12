import Foundation

/// The parts of Claude Code's OAuth credentials that Lite uses (068 §4.1 step 1).
///
/// Parsed from `claudeAiOauth` in `~/.claude/.credentials.json` or in the `Claude Code-credentials` Keychain
/// item, which hold the same JSON. Lite deliberately never parses or stores the refresh token: it never refreshes,
/// because rotating the refresh token signs the Claude CLI out (§2.1).
public struct ClaudeCredentials: Sendable, Equatable {
    public var accessToken: String
    public var expiresAt: Date?
    public var scopes: [String]
    public var subscriptionType: String?
    public var rateLimitTier: String?

    public init(
        accessToken: String,
        expiresAt: Date?,
        scopes: [String] = [],
        subscriptionType: String? = nil,
        rateLimitTier: String? = nil)
    {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    /// True once `now` reaches `expiresAt`.
    ///
    /// A missing `expiresAt` is not treated as expired, unlike the full app's `ClaudeOAuthCredentials.isExpired`.
    /// The full app can refresh such a token; Lite can't, so it lets the server decide and handles the 401
    /// (§4.1) instead of showing "token expired" forever for a credential shape it doesn't recognise.
    public func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// The plan name exactly as the full app writes it to `loginMethod`, for example "Claude Max 20x".
    public var plan: String? {
        ClaudePlanName.displayName(subscriptionType: self.subscriptionType, rateLimitTier: self.rateLimitTier)
    }

    /// Parses Claude Code's credentials JSON, matching `ClaudeOAuthCredentials.parse(data:)` in the full app:
    /// the access token is trimmed and must be non-empty, and `expiresAt` is in milliseconds since 1970.
    public static func parse(_ data: Data) throws(ClaudeCredentialsError) -> ClaudeCredentials {
        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: data)
        } catch {
            throw .invalidJSON
        }
        guard let oauth = root.claudeAiOauth else { throw .missingOAuth }
        let accessToken = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !accessToken.isEmpty else { throw .missingAccessToken }
        return ClaudeCredentials(
            accessToken: accessToken,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            scopes: oauth.scopes ?? [],
            subscriptionType: oauth.subscriptionType,
            rateLimitTier: oauth.rateLimitTier)
    }

    private struct Root: Decodable {
        let claudeAiOauth: OAuth?
    }

    private struct OAuth: Decodable {
        let accessToken: String?
        let expiresAt: Double?
        let scopes: [String]?
        let subscriptionType: String?
        let rateLimitTier: String?
    }
}

extension ClaudeCredentials: CustomStringConvertible, CustomDebugStringConvertible {
    /// Never includes the token, so an accidental `print` or log line can't leak it.
    public var description: String {
        "ClaudeCredentials(accessToken: <redacted>, expiresAt: \(self.expiresAt.map { "\($0)" } ?? "nil"))"
    }

    public var debugDescription: String {
        self.description
    }
}

/// Why credentials JSON couldn't be used.
public enum ClaudeCredentialsError: Error, Sendable, Equatable {
    /// Not JSON, or a field has the wrong type.
    case invalidJSON
    /// No `claudeAiOauth` object, for example a Keychain item that only holds MCP OAuth state.
    case missingOAuth
    /// `claudeAiOauth.accessToken` is missing or blank.
    case missingAccessToken
}

/// Port of the full app's `ClaudePlan.oauthLoginMethod(subscriptionType:rateLimitTier:)` (`ClaudePlan.swift`), so
/// Lite's plan string matches the `loginMethod` the full app syncs to iOS byte for byte.
enum ClaudePlanName {
    private enum Plan {
        case max
        case pro
        case team
        case enterprise
        case ultra

        var branded: String {
            switch self {
            case .max: "Claude Max"
            case .pro: "Claude Pro"
            case .team: "Claude Team"
            case .enterprise: "Claude Enterprise"
            case .ultra: "Claude Ultra"
            }
        }
    }

    static func displayName(subscriptionType: String?, rateLimitTier: String?) -> String? {
        guard let plan = self.plan(subscriptionType: subscriptionType) ?? self.plan(rateLimitTier: rateLimitTier)
        else { return nil }
        if plan == .max, let multiplier = self.maxUsageMultiplier(rateLimitTier: rateLimitTier) {
            return "\(plan.branded) \(multiplier)"
        }
        return plan.branded
    }

    /// `ClaudePlan.fromCompatibilityLoginMethod`: whole words of the subscription type.
    private static func plan(subscriptionType: String?) -> Plan? {
        let words = self.words(subscriptionType)
        if words.contains("max") { return .max }
        if words.contains("pro") { return .pro }
        if words.contains("team") { return .team }
        if words.contains("enterprise") { return .enterprise }
        if words.contains("ultra") { return .ultra }
        return nil
    }

    /// `ClaudePlan.fromRateLimitTier`: substrings of the rate-limit tier.
    private static func plan(rateLimitTier: String?) -> Plan? {
        let tier = self.normalized(rateLimitTier)
        if tier.contains("max") { return .max }
        if tier.contains("pro") { return .pro }
        if tier.contains("team") { return .team }
        if tier.contains("enterprise") { return .enterprise }
        return nil
    }

    /// `ClaudePlan.maxUsageMultiplier`: the word after "max" when it looks like "20x".
    private static func maxUsageMultiplier(rateLimitTier: String?) -> String? {
        let words = self.words(rateLimitTier)
        guard let maxIndex = words.firstIndex(of: "max"), words.indices.contains(maxIndex + 1) else { return nil }
        let multiplier = words[maxIndex + 1]
        guard multiplier.last == "x", Int(multiplier.dropLast()) != nil else { return nil }
        return multiplier
    }

    private static func normalized(_ text: String?) -> String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func words(_ text: String?) -> [String] {
        self.normalized(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}

/// Reads Claude Code's plain-text credentials file (068 §4.1 step 1).
public protocol ClaudeCredentialsFileReading: Sendable {
    /// The file's bytes, or nil when it doesn't exist or can't be read.
    func readCredentialsFile() -> Data?
}

/// `$CLAUDE_CONFIG_DIR/.credentials.json` when that variable is set and non-empty, else
/// `~/.claude/.credentials.json`. On the owner's Mac this file doesn't exist (Phase 0), so the token comes from the
/// Keychain.
public struct ClaudeCredentialsFile: ClaudeCredentialsFileReading {
    public let url: URL

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser)
    {
        self.url = Self.url(environment: environment, homeDirectory: homeDirectory)
    }

    public static func url(environment: [String: String], homeDirectory: URL) -> URL {
        let root: URL = if let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        }
        return root.appendingPathComponent(".credentials.json")
    }

    public func readCredentialsFile() -> Data? {
        try? Data(contentsOf: self.url)
    }
}
