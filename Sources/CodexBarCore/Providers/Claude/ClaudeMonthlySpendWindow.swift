import Foundation

extension UsageSnapshot {
    /// Presentation only: Claude reports no reset for monthly caps, so use the cost observation's UTC month.
    package var claudeMonthlySpendWindow: NamedRateWindow? {
        guard self.loginMethod(for: .claude) != "Admin API",
              let cost = self.providerCost,
              cost.limit.isFinite, cost.limit > 0,
              cost.used.isFinite,
              let utc = TimeZone(secondsFromGMT: 0)
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let resetsAt = cost.resetsAt ?? calendar.dateInterval(of: .month, for: cost.updatedAt)?.end
        let usedPercent = max(0, min(100, (cost.used / cost.limit) * 100))
        return NamedRateWindow(
            id: "claude-extra-usage",
            title: "Extra usage",
            window: RateWindow(
                usedPercent: usedPercent,
                windowMinutes: ProviderPaceCapability.monthlyWindowSentinelMinutes,
                resetsAt: resetsAt,
                resetDescription: nil))
    }
}
