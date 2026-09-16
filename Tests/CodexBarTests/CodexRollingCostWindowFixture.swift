import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Shared fixture builders for the Codex rolling-window publication tests.
enum CodexRollingCostWindowFixture {
    nonisolated static func snapshot(
        rows: [CostUsageDailyReport.Entry],
        endDate: Date,
        historyDays: Int = 30,
        calendar: Calendar,
        established: Bool,
        sessionCostUSD: Double? = nil,
        sessionTokens: Int? = nil,
        sessionRequests: Int? = nil,
        includeWindowKeys: Bool = true,
        currencyCode: String = "USD",
        historyLabel: String? = nil,
        meteredCostUSD: Double? = nil,
        costProvenance: CostProvenance = .unknown,
        credentialScopeFingerprint: String? = nil,
        ownership: CostUsageTokenOwnership = .accountScoped,
        projects: [CostUsageProjectBreakdown] = [],
        sessions: [CostUsageSessionBreakdown] = [],
        hourly: [CostUsageHourlyEntry] = [],
        updatedAt: Date? = nil,
        last30DaysCostUSDOverride: Double? = nil,
        last30DaysTokensOverride: Int? = nil) -> CostUsageTokenSnapshot
    {
        let window = Self.window(endingAt: endDate, days: historyDays, calendar: calendar)
        // Mirror the canonical cost-completeness rule: a window aggregate is only complete when
        // every row has a cost and no unpriced requests remain.
        let allCarryCost = !rows.isEmpty && rows.allSatisfy {
            $0.costUSD != nil && ($0.unpricedRequestCount ?? 0) == 0
        }
        let allCarryTokens = rows.allSatisfy { $0.totalTokens != nil }
        return CostUsageTokenSnapshot(
            sessionTokens: sessionTokens,
            sessionCostUSD: sessionCostUSD,
            sessionRequests: sessionRequests,
            last30DaysTokens: last30DaysTokensOverride
                ?? (allCarryTokens ? rows.compactMap(\.totalTokens).reduce(0, +) : nil),
            last30DaysCostUSD: last30DaysCostUSDOverride
                ?? (allCarryCost ? rows.compactMap(\.costUSD).reduce(0, +) : nil),
            currencyCode: currencyCode,
            historyDays: historyDays,
            historyCoverageIsEstablished: established,
            historySinceDayKey: includeWindowKeys ? window.sinceKey : nil,
            historyUntilDayKey: includeWindowKeys ? window.untilKey : nil,
            historyLabel: historyLabel,
            meteredCostUSD: meteredCostUSD,
            costProvenance: costProvenance,
            credentialScopeFingerprint: credentialScopeFingerprint,
            ownership: ownership,
            daily: rows,
            projects: projects,
            sessions: sessions,
            hourly: hourly,
            updatedAt: updatedAt ?? endDate)
    }

    nonisolated static func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return calendar
    }

    nonisolated static func losAngelesCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        return calendar
    }

    nonisolated static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 12,
        calendar: Calendar) throws -> Date
    {
        try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour)))
    }

    nonisolated static func window(
        endingAt end: Date,
        days: Int,
        calendar: Calendar) -> (sinceKey: String, untilKey: String)
    {
        let untilKey = CostUsageLocalDay.key(from: end, calendar: calendar)
        let sinceDate = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: end) ?? end
        return (CostUsageLocalDay.key(from: sinceDate, calendar: calendar), untilKey)
    }

    nonisolated static func row(
        _ dayKey: String,
        cost: Double?,
        tokens: Int?,
        requests: Int? = nil,
        unpricedRequests: Int? = nil) -> CostUsageDailyReport.Entry
    {
        CostUsageDailyReport.Entry(
            date: dayKey,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: tokens,
            requestCount: requests,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil,
            unpricedRequestCount: unpricedRequests)
    }

    nonisolated static func replacing(
        _ rows: [CostUsageDailyReport.Entry],
        dayKey: String,
        cost: Double?,
        tokens: Int?) -> [CostUsageDailyReport.Entry]
    {
        rows.map { $0.date == dayKey ? Self.row(dayKey, cost: cost, tokens: tokens) : $0 }
    }

    nonisolated static func uniformRows(
        endingAt end: Date,
        days: Int,
        calendar: Calendar,
        cost: Double,
        tokens: Int,
        requests: Int? = nil) -> [CostUsageDailyReport.Entry]
    {
        (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return Self.row(
                CostUsageLocalDay.key(from: date, calendar: calendar),
                cost: cost,
                tokens: tokens,
                requests: requests)
        }
    }

    @MainActor static func makeStore(suite: String) throws -> UsageStore {
        let settings = testSettingsStore(suiteName: "CodexRollingCostWindowTests-\(suite)")
        settings.costUsageEnabled = true
        settings.costUsageHistoryDays = 30
        let metadata = try #require(ProviderRegistry.shared.metadata[.codex])
        settings.setProviderEnabled(provider: .codex, metadata: metadata, enabled: true)
        return UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
    }

    @MainActor static func waitUntil(
        timeout: TimeInterval = 1,
        _ condition: @MainActor () -> Bool) async
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for condition")
    }
}
