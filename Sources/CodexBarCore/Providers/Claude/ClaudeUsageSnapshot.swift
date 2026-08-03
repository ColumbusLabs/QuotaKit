import Foundation

public protocol ClaudeUsageFetching: Sendable {
    func loadLatestUsage(model: String) async throws -> ClaudeUsageSnapshot
    func debugRawProbe(model: String) async -> String
    func detectVersion() -> String?
}

public struct ClaudeUsageSnapshot: Sendable {
    public enum PrimaryWindowKind: Equatable, Sendable {
        case usage
        case spendLimit
    }

    public let primary: RateWindow
    public let primaryWindowKind: PrimaryWindowKind
    public let secondary: RateWindow?
    public let opus: RateWindow?
    public let extraRateWindows: [NamedRateWindow]
    public let providerCost: ProviderCostSnapshot?
    public let updatedAt: Date
    public let accountEmail: String?
    public let accountOrganization: String?
    public let loginMethod: String?
    public let rawText: String?
    /// Present only when the credential used for this OAuth fetch matches the current Claude Keychain item.
    public let oauthKeychainPersistentRefHash: String?
    /// One-way, high-entropy ownership evidence derived from the exact credential used for this OAuth fetch.
    public let oauthHistoryOwnerIdentifier: String?
    /// The authority that owned the credential used for this OAuth fetch.
    public let oauthCredentialOwner: ClaudeOAuthCredentialOwner?
    /// True when a prompt-free comparison proved this credential differs from Claude Code's Keychain entry.
    public let oauthKeychainCredentialMismatch: Bool
    /// True when a prompt-free probe proved Claude Code has no Keychain credential.
    public let oauthKeychainCredentialAbsent: Bool
    /// True when a Claude CLI credential won routing but the prompt-free Keychain comparison was unavailable.
    public let oauthKeychainCredentialUnavailable: Bool

    public init(
        primary: RateWindow,
        primaryWindowKind: PrimaryWindowKind = .usage,
        secondary: RateWindow?,
        opus: RateWindow?,
        extraRateWindows: [NamedRateWindow] = [],
        providerCost: ProviderCostSnapshot? = nil,
        updatedAt: Date,
        accountEmail: String?,
        accountOrganization: String?,
        loginMethod: String?,
        rawText: String?,
        oauthKeychainPersistentRefHash: String? = nil,
        oauthHistoryOwnerIdentifier: String? = nil,
        oauthCredentialOwner: ClaudeOAuthCredentialOwner? = nil,
        oauthKeychainCredentialMismatch: Bool = false,
        oauthKeychainCredentialAbsent: Bool = false,
        oauthKeychainCredentialUnavailable: Bool = false)
    {
        self.primary = primary
        self.primaryWindowKind = primaryWindowKind
        self.secondary = secondary
        self.opus = opus
        self.extraRateWindows = extraRateWindows
        self.providerCost = providerCost
        self.updatedAt = updatedAt
        self.accountEmail = accountEmail
        self.accountOrganization = accountOrganization
        self.loginMethod = loginMethod
        self.rawText = rawText
        self.oauthKeychainPersistentRefHash = oauthKeychainPersistentRefHash
        self.oauthHistoryOwnerIdentifier = oauthHistoryOwnerIdentifier
        self.oauthCredentialOwner = oauthCredentialOwner
        self.oauthKeychainCredentialMismatch = oauthKeychainCredentialMismatch
        self.oauthKeychainCredentialAbsent = oauthKeychainCredentialAbsent
        self.oauthKeychainCredentialUnavailable = oauthKeychainCredentialUnavailable
    }
}
