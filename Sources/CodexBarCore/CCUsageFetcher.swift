import Foundation

public enum CCUsageError: LocalizedError, Sendable {
    case unsupportedProvider(UsageProvider)
    case timedOut(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedProvider(provider):
            return "Cost summary is not supported for \(provider.rawValue)."
        case let .timedOut(seconds):
            if seconds >= 60, seconds % 60 == 0 {
                return "Cost refresh timed out after \(seconds / 60)m."
            }
            return "Cost refresh timed out after \(seconds)s."
        }
    }
}

public struct CCUsageFetcher: Sendable {
    public init() {}

    public func loadTokenSnapshot(
        provider: UsageProvider,
        now: Date = Date(),
        forceRefresh: Bool = false) async throws -> CCUsageTokenSnapshot
    {
        guard provider == .codex || provider == .claude else {
            throw CCUsageError.unsupportedProvider(provider)
        }

        let until = now
        // Rolling window: last 30 days (inclusive). Use -29 for inclusive boundaries.
        let since = Calendar.current.date(byAdding: .day, value: -29, to: now) ?? now

        var options = CostUsageScanner.Options()
        if forceRefresh {
            options.refreshMinIntervalSeconds = 0
        }
        let daily = await Task.detached(priority: .utility) {
            CostUsageScanner.loadDailyReport(
                provider: provider,
                since: since,
                until: until,
                now: now,
                options: options)
        }.value

        return Self.tokenSnapshot(from: daily, now: now)
    }

    static func tokenSnapshot(from daily: CCUsageDailyReport, now: Date) -> CCUsageTokenSnapshot {
        let currentDay = daily.data.max { lhs, rhs in
            let lDate = CCUsageDateParser.parse(lhs.date) ?? .distantPast
            let rDate = CCUsageDateParser.parse(rhs.date) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.date < rhs.date
        }
        let totalFromSummary = daily.summary?.totalCostUSD
        let totalFromEntries = daily.data.compactMap(\.costUSD).reduce(0, +)
        let last30DaysCostUSD = totalFromSummary ?? (totalFromEntries > 0 ? totalFromEntries : nil)

        return CCUsageTokenSnapshot(
            sessionTokens: currentDay?.totalTokens,
            sessionCostUSD: currentDay?.costUSD,
            last30DaysCostUSD: last30DaysCostUSD,
            daily: daily.data,
            updatedAt: now)
    }

    static func selectCurrentSession(from sessions: [CCUsageSessionReport.Entry])
        -> CCUsageSessionReport.Entry?
    {
        if sessions.isEmpty { return nil }
        return sessions.max { lhs, rhs in
            let lDate = CCUsageDateParser.parse(lhs.lastActivity) ?? .distantPast
            let rDate = CCUsageDateParser.parse(rhs.lastActivity) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.session < rhs.session
        }
    }

    static func selectMostRecentMonth(from months: [CCUsageMonthlyReport.Entry])
        -> CCUsageMonthlyReport.Entry?
    {
        if months.isEmpty { return nil }
        return months.max { lhs, rhs in
            let lDate = CCUsageDateParser.parseMonth(lhs.month) ?? .distantPast
            let rDate = CCUsageDateParser.parseMonth(rhs.month) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.month < rhs.month
        }
    }
}
