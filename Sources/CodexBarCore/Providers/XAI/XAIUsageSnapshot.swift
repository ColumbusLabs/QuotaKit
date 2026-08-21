import Foundation

/// Prepaid balance plus daily USD spend from the xAI Management API billing
/// endpoints. Mirrors the Groq/OpenAI daily cost-history shape so it renders
/// through the shared cost-history inline dashboard.
public struct XAIUsageSnapshot: Codable, Equatable, Sendable {
    public struct DailyBucket: Codable, Equatable, Sendable, Identifiable {
        /// UTC day in `yyyy-MM-dd` (usage is requested in `Etc/GMT`); the inline
        /// dashboard derives its axis labels from this exact format.
        public let day: String
        public let costUSD: Double

        public var id: String {
            self.day
        }

        public init(day: String, costUSD: Double) {
            self.day = day
            self.costUSD = costUSD
        }
    }

    /// Remaining prepaid credit in dollars. The balance endpoint reports an
    /// inverted ledger in string USD cents (a $10 top-up is "-1000"), so this
    /// is `-cents / 100`; a negative value means the team is in deficit.
    public let balanceUSD: Double
    public let daily: [DailyBucket]
    public let historyDays: Int
    /// True when the usage endpoint reported its cardinality cap; daily sums
    /// may then be incomplete and must not be presented as exact.
    public let limitReached: Bool
    /// True only when the usage-history request completed successfully. An
    /// empty successful response is known zero; failed enrichment is unknown.
    public let historyAvailable: Bool
    public let updatedAt: Date

    public init(
        balanceUSD: Double,
        daily: [DailyBucket],
        historyDays: Int = 30,
        limitReached: Bool = false,
        historyAvailable: Bool = true,
        updatedAt: Date)
    {
        self.balanceUSD = balanceUSD
        self.daily = daily.sorted { $0.day < $1.day }
        self.historyDays = max(1, min(365, historyDays))
        self.limitReached = limitReached
        self.historyAvailable = historyAvailable
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case balanceUSD
        case daily
        case historyDays
        case limitReached
        case historyAvailable
        case updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let daily = try container.decode([DailyBucket].self, forKey: .daily)
        self.balanceUSD = try container.decode(Double.self, forKey: .balanceUSD)
        self.daily = daily.sorted { $0.day < $1.day }
        self.historyDays = try max(1, min(365, container.decode(Int.self, forKey: .historyDays)))
        self.limitReached = try container.decode(Bool.self, forKey: .limitReached)
        // Legacy snapshots had no availability bit. Non-empty history proves success;
        // legacy empty history stays unavailable rather than being promoted to $0.
        self.historyAvailable = try container.decodeIfPresent(Bool.self, forKey: .historyAvailable)
            ?? !daily.isEmpty
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.balanceUSD, forKey: .balanceUSD)
        try container.encode(self.daily, forKey: .daily)
        try container.encode(self.historyDays, forKey: .historyDays)
        try container.encode(self.limitReached, forKey: .limitReached)
        try container.encode(self.historyAvailable, forKey: .historyAvailable)
        try container.encode(self.updatedAt, forKey: .updatedAt)
    }

    public var historyWindowPeriodLabel: String {
        let base = self.historyDays == 1 ? "Today" : "Last \(self.historyDays) days"
        return self.limitReached ? "\(base) (partial)" : base
    }

    public var windowCostUSD: Double {
        self.daily.reduce(0) { $0 + $1.costUSD }
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: self.balanceUSD,
                limit: 0,
                currencyCode: "USD",
                period: "Prepaid credits",
                updatedAt: self.updatedAt),
            details: [.makeSection(
                title: "Billing summary",
                rows: [
                    .makeRow(label: "Prepaid balance", value: UsageFormatter.usdString(self.balanceUSD)),
                    .makeRow(
                        label: self.historyWindowPeriodLabel,
                        value: UsageFormatter.usdString(self.windowCostUSD)),
                ],
                chart: self.historyAvailable ? .makeChart(
                    title: "Daily spend",
                    unit: "USD",
                    points: self.daily.map { ($0.day, $0.costUSD) }) : nil)],
            xaiUsage: self,
            updatedAt: self.updatedAt,
            identity: ProviderIdentitySnapshot(
                providerID: .xai,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: "Management API"),
            dataConfidence: self.limitReached ? .estimated : .exact)
    }

    /// Nil only when history was unavailable. A successful empty response is a
    /// confirmed zero and intentionally projects an empty daily series.
    public func costHistorySnapshot() -> CostUsageTokenSnapshot? {
        guard self.historyAvailable else { return nil }
        let entries = self.daily.map { bucket in
            CostUsageDailyReport.Entry(
                date: bucket.day,
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: nil,
                costUSD: bucket.costUSD,
                modelsUsed: nil,
                modelBreakdowns: nil)
        }
        let today = self.daily.first { $0.day == Self.utcDayString(from: self.updatedAt) }
        return CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: today?.costUSD,
            last30DaysTokens: nil,
            last30DaysCostUSD: self.windowCostUSD,
            historyDays: self.historyDays,
            historyLabel: self.limitReached ? self.historyWindowPeriodLabel : nil,
            daily: entries,
            updatedAt: self.updatedAt)
    }

    private static func utcDayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
