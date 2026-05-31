import Foundation

// Provider-specific sync envelope blocks added in iOS 1.10.0 / Mac 0.31.0
// (sync 025) to carry upstream v0.30.0 DeepSeek web-session usage+cost to iOS.
// Optional + synthesized `Codable` (a missing key decodes as `nil`), so the
// block rides inside the existing zlib payload with no CloudKit schema change
// and stays wire-compatible both directions. See Research/025 §01 design §2.1.

// MARK: - DeepSeek web-session usage + cost + balance (upstream v0.30.0 #1166)

/// DeepSeek web-session usage/cost summary plus account balance. Populated only
/// on the `deepseek` provider snapshot when Mac parsed the web usage/cost data
/// (`UsageSnapshot.deepseekUsage`, transient upstream). Before this iOS had no
/// DeepSeek card; now it renders today/month tokens·cost·requests + balance +
/// a 30-day mini chart. All numeric fields beyond the always-present counters
/// are optional so a free-tier account / older Mac payload degrades silently.
public struct SyncDeepSeekUsage: Codable, Sendable, Equatable {
    /// Tokens used today (UTC day per upstream parser).
    public let todayTokens: Int
    /// Tokens used in the current calendar month.
    public let monthTokens: Int
    /// Spend today, when cost data is available (nil otherwise).
    public let todayCost: Double?
    /// Spend in the current calendar month.
    public let monthCost: Double?
    /// Request count today.
    public let todayRequests: Int
    /// Request count in the current calendar month.
    public let monthRequests: Int
    /// Most-used model label, when reported.
    public let topModel: String?
    /// ISO currency code for the cost values (e.g. "USD", "CNY").
    public let currency: String
    /// Account total balance in USD, when scraped (nil otherwise).
    public let totalBalanceUSD: Double?
    /// Granted (free/promo) balance in USD.
    public let grantedBalanceUSD: Double?
    /// Topped-up (paid) balance in USD.
    public let toppedUpBalanceUSD: Double?
    /// Up to ~30 days of per-day usage for the mini chart (may be empty).
    public let daily: [SyncDeepSeekDaily]
    public let updatedAt: Date

    public init(
        todayTokens: Int,
        monthTokens: Int,
        todayCost: Double?,
        monthCost: Double?,
        todayRequests: Int,
        monthRequests: Int,
        topModel: String?,
        currency: String,
        totalBalanceUSD: Double?,
        grantedBalanceUSD: Double?,
        toppedUpBalanceUSD: Double?,
        daily: [SyncDeepSeekDaily],
        updatedAt: Date)
    {
        self.todayTokens = todayTokens
        self.monthTokens = monthTokens
        self.todayCost = todayCost
        self.monthCost = monthCost
        self.todayRequests = todayRequests
        self.monthRequests = monthRequests
        self.topModel = topModel
        self.currency = currency
        self.totalBalanceUSD = totalBalanceUSD
        self.grantedBalanceUSD = grantedBalanceUSD
        self.toppedUpBalanceUSD = toppedUpBalanceUSD
        self.daily = daily
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.todayTokens = try container.decode(Int.self, forKey: .todayTokens)
        self.monthTokens = try container.decode(Int.self, forKey: .monthTokens)
        self.todayCost = try container.decodeIfPresent(Double.self, forKey: .todayCost)
        self.monthCost = try container.decodeIfPresent(Double.self, forKey: .monthCost)
        self.todayRequests = try container.decode(Int.self, forKey: .todayRequests)
        self.monthRequests = try container.decode(Int.self, forKey: .monthRequests)
        self.topModel = try container.decodeIfPresent(String.self, forKey: .topModel)
        self.currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        self.totalBalanceUSD = try container.decodeIfPresent(Double.self, forKey: .totalBalanceUSD)
        self.grantedBalanceUSD = try container.decodeIfPresent(Double.self, forKey: .grantedBalanceUSD)
        self.toppedUpBalanceUSD = try container.decodeIfPresent(Double.self, forKey: .toppedUpBalanceUSD)
        // `?? []` so a payload that omitted the array still decodes to "no chart".
        self.daily = try container.decodeIfPresent([SyncDeepSeekDaily].self, forKey: .daily) ?? []
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

/// A single day's DeepSeek usage point for the 30-day mini chart.
public struct SyncDeepSeekDaily: Codable, Sendable, Equatable {
    /// `"yyyy-MM-dd"` day key.
    public let dayKey: String
    public let totalTokens: Int
    public let cost: Double?
    public let requestCount: Int

    public init(dayKey: String, totalTokens: Int, cost: Double?, requestCount: Int) {
        self.dayKey = dayKey
        self.totalTokens = totalTokens
        self.cost = cost
        self.requestCount = requestCount
    }
}
