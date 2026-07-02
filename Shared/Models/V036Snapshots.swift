import Foundation

// Provider-specific sync envelope blocks added after upstream v0.36.1 to carry
// CrossModel's wallet balance and UTC usage windows to iOS. Optional fields on
// ProviderUsageSnapshot keep the existing wire payload backward-compatible.

// MARK: - CrossModel wallet + usage windows

public struct SyncCrossModelUsageWindow: Codable, Sendable, Equatable {
    public let cost: Double
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let requestCount: Int
    public let successCount: Int

    public init(
        cost: Double,
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        requestCount: Int,
        successCount: Int)
    {
        self.cost = cost
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.requestCount = requestCount
        self.successCount = successCount
    }
}

public struct SyncCrossModelUsage: Codable, Sendable, Equatable {
    public let currency: String
    public let balance: Double
    public let uncollected: Double
    public let daily: SyncCrossModelUsageWindow?
    public let weekly: SyncCrossModelUsageWindow?
    public let monthly: SyncCrossModelUsageWindow?
    public let updatedAt: Date

    public init(
        currency: String,
        balance: Double,
        uncollected: Double,
        daily: SyncCrossModelUsageWindow?,
        weekly: SyncCrossModelUsageWindow?,
        monthly: SyncCrossModelUsageWindow?,
        updatedAt: Date)
    {
        self.currency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.balance = balance
        self.uncollected = uncollected
        self.daily = daily
        self.weekly = weekly
        self.monthly = monthly
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.currency = try (container.decodeIfPresent(String.self, forKey: .currency) ?? "USD")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        self.balance = try container.decode(Double.self, forKey: .balance)
        self.uncollected = try container.decodeIfPresent(Double.self, forKey: .uncollected) ?? 0
        self.daily = try container.decodeIfPresent(SyncCrossModelUsageWindow.self, forKey: .daily)
        self.weekly = try container.decodeIfPresent(SyncCrossModelUsageWindow.self, forKey: .weekly)
        self.monthly = try container.decodeIfPresent(SyncCrossModelUsageWindow.self, forKey: .monthly)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
