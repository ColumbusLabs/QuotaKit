#if os(macOS) || os(Linux)

// MARK: - Cursor Cost Report

/// A windowed Cursor cost report: the API-rate per-day breakdown plus the Cursor-metered
/// total (what the plan actually deducts) over the same window.
///
/// `daily` carries vendor list-price costs (`tokenUsage.totalCents`); `meteredCostUSD` sums
/// each event's `chargedCents` and is `nil` when the events reported no metered amount.
public struct CursorCostReport: Sendable {
    public let daily: CostUsageDailyReport
    public let meteredCostUSD: Double?
    public let credentialScopeFingerprint: String

    public init(
        daily: CostUsageDailyReport,
        meteredCostUSD: Double?,
        credentialScopeFingerprint: String)
    {
        self.daily = daily
        self.meteredCostUSD = meteredCostUSD
        self.credentialScopeFingerprint = credentialScopeFingerprint
    }
}

#endif
