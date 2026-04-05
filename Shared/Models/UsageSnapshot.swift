import Foundation

/// A single rate-limit window snapshot for iCloud sync.
public struct SyncRateWindow: Codable, Sendable, Equatable {
    public let label: String?
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let resetDescription: String?

    public var remainingPercent: Double {
        max(0, 100 - self.usedPercent)
    }

    public init(
        label: String? = nil,
        usedPercent: Double,
        windowMinutes: Int?,
        resetsAt: Date?,
        resetDescription: String?)
    {
        self.label = label
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        self.usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        self.windowMinutes = try container.decodeIfPresent(Int.self, forKey: .windowMinutes)
        self.resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        self.resetDescription = try container.decodeIfPresent(String.self, forKey: .resetDescription)
    }
}

/// A single day's cost/token data point for iCloud sync.
public struct SyncCostBreakdown: Codable, Sendable, Equatable {
    public let label: String
    public let costUSD: Double

    public init(label: String, costUSD: Double) {
        self.label = label
        self.costUSD = costUSD
    }
}

/// A single day's cost/token data point for iCloud sync.
public struct SyncDailyPoint: Codable, Sendable, Equatable {
    public let dayKey: String
    public let costUSD: Double
    public let totalTokens: Int
    public let modelBreakdowns: [SyncCostBreakdown]
    public let serviceBreakdowns: [SyncCostBreakdown]

    public init(
        dayKey: String,
        costUSD: Double,
        totalTokens: Int,
        modelBreakdowns: [SyncCostBreakdown] = [],
        serviceBreakdowns: [SyncCostBreakdown] = [])
    {
        self.dayKey = dayKey
        self.costUSD = costUSD
        self.totalTokens = totalTokens
        self.modelBreakdowns = modelBreakdowns
        self.serviceBreakdowns = serviceBreakdowns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dayKey = try container.decode(String.self, forKey: .dayKey)
        self.costUSD = try container.decode(Double.self, forKey: .costUSD)
        self.totalTokens = try container.decode(Int.self, forKey: .totalTokens)
        self.modelBreakdowns =
            try container.decodeIfPresent([SyncCostBreakdown].self, forKey: .modelBreakdowns) ?? []
        self.serviceBreakdowns =
            try container.decodeIfPresent([SyncCostBreakdown].self, forKey: .serviceBreakdowns) ?? []
    }
}

/// Aggregated cost/token summary for iCloud sync.
public struct SyncCostSummary: Codable, Sendable, Equatable {
    public let sessionCostUSD: Double?
    public let sessionTokens: Int?
    public let last30DaysCostUSD: Double?
    public let last30DaysTokens: Int?
    public let daily: [SyncDailyPoint]

    public init(
        sessionCostUSD: Double?,
        sessionTokens: Int?,
        last30DaysCostUSD: Double?,
        last30DaysTokens: Int?,
        daily: [SyncDailyPoint])
    {
        self.sessionCostUSD = sessionCostUSD
        self.sessionTokens = sessionTokens
        self.last30DaysCostUSD = last30DaysCostUSD
        self.last30DaysTokens = last30DaysTokens
        self.daily = daily
    }
}

/// Provider budget/spend snapshot for iCloud sync.
public struct SyncBudgetSnapshot: Codable, Sendable, Equatable {
    public let usedAmount: Double
    public let limitAmount: Double
    public let currencyCode: String
    public let period: String?
    public let resetsAt: Date?

    public init(
        usedAmount: Double,
        limitAmount: Double,
        currencyCode: String,
        period: String?,
        resetsAt: Date?)
    {
        self.usedAmount = usedAmount
        self.limitAmount = limitAmount
        self.currencyCode = currencyCode
        self.period = period
        self.resetsAt = resetsAt
    }
}

/// A single data point in the subscription utilization history.
public struct SyncUtilizationEntry: Codable, Sendable, Equatable {
    public let capturedAt: Date
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(capturedAt: Date, usedPercent: Double, resetsAt: Date?) {
        self.capturedAt = capturedAt
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// A named series of utilization history entries (e.g. "session", "weekly", "opus").
public struct SyncUtilizationSeries: Codable, Sendable, Equatable {
    public let name: String
    public let windowMinutes: Int
    public let entries: [SyncUtilizationEntry]

    public init(name: String, windowMinutes: Int, entries: [SyncUtilizationEntry]) {
        self.name = name
        self.windowMinutes = windowMinutes
        self.entries = entries
    }
}

/// A single provider's usage snapshot for iCloud sync.
public struct ProviderUsageSnapshot: Codable, Sendable, Equatable {
    public let providerID: String
    public let providerName: String
    public let primary: SyncRateWindow?
    public let secondary: SyncRateWindow?
    /// Dynamic list of all rate windows (replaces primary/secondary when present).
    public let rateWindows: [SyncRateWindow]
    public let accountEmail: String?
    public let loginMethod: String?
    public let statusMessage: String?
    public let isError: Bool
    public let lastUpdated: Date
    public let costSummary: SyncCostSummary?
    public let budget: SyncBudgetSnapshot?
    /// Subscription utilization history (session/weekly/opus) for chart display.
    public let utilizationHistory: [SyncUtilizationSeries]?

    /// All available rate windows. Prefers `rateWindows` if non-empty, otherwise falls back to primary/secondary.
    public var allRateWindows: [SyncRateWindow] {
        if !self.rateWindows.isEmpty { return self.rateWindows }
        return [self.primary, self.secondary].compactMap(\.self)
    }

    public init(
        providerID: String,
        providerName: String,
        primary: SyncRateWindow?,
        secondary: SyncRateWindow?,
        accountEmail: String?,
        loginMethod: String?,
        statusMessage: String?,
        isError: Bool,
        lastUpdated: Date,
        costSummary: SyncCostSummary? = nil,
        budget: SyncBudgetSnapshot? = nil,
        rateWindows: [SyncRateWindow] = [],
        utilizationHistory: [SyncUtilizationSeries]? = nil)
    {
        self.providerID = providerID
        self.providerName = providerName
        self.primary = primary
        self.secondary = secondary
        self.rateWindows = rateWindows
        self.accountEmail = accountEmail
        self.loginMethod = loginMethod
        self.statusMessage = statusMessage
        self.isError = isError
        self.lastUpdated = lastUpdated
        self.costSummary = costSummary
        self.budget = budget
        self.utilizationHistory = utilizationHistory
    }

    /// Backward-compatible decoder: old payloads without `rateWindows`/`costSummary`/`budget` still decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providerID = try container.decode(String.self, forKey: .providerID)
        self.providerName = try container.decode(String.self, forKey: .providerName)
        self.primary = try container.decodeIfPresent(SyncRateWindow.self, forKey: .primary)
        self.secondary = try container.decodeIfPresent(SyncRateWindow.self, forKey: .secondary)
        self.rateWindows = try container.decodeIfPresent([SyncRateWindow].self, forKey: .rateWindows) ?? []
        self.accountEmail = try container.decodeIfPresent(String.self, forKey: .accountEmail)
        self.loginMethod = try container.decodeIfPresent(String.self, forKey: .loginMethod)
        self.statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)
        self.isError = try container.decode(Bool.self, forKey: .isError)
        self.lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        self.costSummary = try container.decodeIfPresent(SyncCostSummary.self, forKey: .costSummary)
        self.budget = try container.decodeIfPresent(SyncBudgetSnapshot.self, forKey: .budget)
        self.utilizationHistory = try container.decodeIfPresent([SyncUtilizationSeries].self, forKey: .utilizationHistory)
    }
}

/// Full sync payload pushed from Mac to iOS via iCloud.
public struct SyncedUsageSnapshot: Codable, Sendable, Equatable {
    public let providers: [ProviderUsageSnapshot]
    public let syncTimestamp: Date
    public let deviceName: String
    /// Stable UUID identifying the source Mac. Used as CloudKit record name.
    public let deviceID: String?
    /// Mac app version (e.g. "0.18.0-beta.3")
    public let appVersion: String?
    /// Mobile version (e.g. "1.0.0")
    public let mobileVersion: String?
    /// When false, iOS should suppress push notifications for this snapshot.
    public let notificationPushEnabled: Bool?

    private enum CodingKeys: String, CodingKey {
        case providers, syncTimestamp, deviceName, deviceID, appVersion
        case mobileVersion, notificationPushEnabled
        /// Legacy key for backward compatibility with older synced data.
        case syncVersion
    }

    public init(
        providers: [ProviderUsageSnapshot],
        syncTimestamp: Date,
        deviceName: String,
        deviceID: String? = nil,
        appVersion: String? = nil,
        mobileVersion: String? = nil,
        notificationPushEnabled: Bool? = nil)
    {
        self.providers = providers
        self.syncTimestamp = syncTimestamp
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.appVersion = appVersion
        self.mobileVersion = mobileVersion
        self.notificationPushEnabled = notificationPushEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providers = try container.decode([ProviderUsageSnapshot].self, forKey: .providers)
        self.syncTimestamp = try container.decode(Date.self, forKey: .syncTimestamp)
        self.deviceName = try container.decode(String.self, forKey: .deviceName)
        self.deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID)
        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        // Read from "mobileVersion" first; fall back to legacy "syncVersion" key.
        self.mobileVersion = try container.decodeIfPresent(String.self, forKey: .mobileVersion)
            ?? container.decodeIfPresent(String.self, forKey: .syncVersion)
        self.notificationPushEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationPushEnabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.providers, forKey: .providers)
        try container.encode(self.syncTimestamp, forKey: .syncTimestamp)
        try container.encode(self.deviceName, forKey: .deviceName)
        try container.encodeIfPresent(self.deviceID, forKey: .deviceID)
        try container.encodeIfPresent(self.appVersion, forKey: .appVersion)
        try container.encodeIfPresent(self.mobileVersion, forKey: .mobileVersion)
        try container.encodeIfPresent(self.notificationPushEnabled, forKey: .notificationPushEnabled)
    }
}
