import Foundation

/// Why a provider isn't showing live data. Each case maps to one footer line in the menu (068 §7.4).
public enum ProviderStatus: Codable, Sendable, Equatable {
    case ok
    /// The CLI's token expired and nobody has run the CLI since (§4.1, §4.2).
    case tokenExpired
    /// `/usr/bin/security` couldn't read the Claude token (§4.1 step 4).
    case tokenUnavailable
    /// The account needs to sign in to the CLI again (403 scope error, or a 401 after re-reading).
    case signInRequired
    /// Antigravity isn't running (§4.3).
    case notRunning
    /// The full QuotaKit app is running, so Lite is paused (§5.4).
    case paused
    /// The endpoint answered with a shape Lite doesn't understand (§8).
    case unrecognizedResponse
    case error(String)
}

/// Everything Lite knows about one provider. Persisted by `LiteStateStore`.
public struct ProviderState: Codable, Sendable, Equatable {
    public var provider: LiteProvider
    public var windows: [QuotaWindow]
    /// Plan name, shown as a pill on the card and synced as `loginMethod`.
    public var plan: String?
    public var accountEmail: String?
    public var accountIdentities: [String]
    /// When data was last fetched successfully. Projection never changes this.
    public var lastFetched: Date?
    public var status: ProviderStatus

    public init(
        provider: LiteProvider,
        windows: [QuotaWindow] = [],
        plan: String? = nil,
        accountEmail: String? = nil,
        accountIdentities: [String] = [],
        lastFetched: Date? = nil,
        status: ProviderStatus = .ok)
    {
        self.provider = provider
        self.windows = windows
        self.plan = plan
        self.accountEmail = accountEmail
        self.accountIdentities = accountIdentities
        self.lastFetched = lastFetched
        self.status = status
    }

    /// The state with every window's reset projected to `now`, for display.
    public func projected(at now: Date) -> ProviderState {
        var state = self
        state.windows = self.windows.map { $0.projected(at: now) }
        return state
    }
}
