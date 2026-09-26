import Foundation

/// Legacy typed Sakana balance retained so cached snapshots and synced records remain decodable
/// after Sakana's fetcher moved to the bundled plugin. New fetches use declarative details.
public struct SakanaPayAsYouGoSnapshot: Codable, Equatable, Sendable {
    public let creditBalance: Double
    public let periodUsageTotal: Double?
    public let periodLabel: String?

    public init(
        creditBalance: Double,
        periodUsageTotal: Double? = nil,
        periodLabel: String? = nil)
    {
        self.creditBalance = creditBalance
        self.periodUsageTotal = periodUsageTotal
        self.periodLabel = periodLabel
    }

    public var balanceDetail: String {
        UsageFormatter.usdString(self.creditBalance)
    }
}
