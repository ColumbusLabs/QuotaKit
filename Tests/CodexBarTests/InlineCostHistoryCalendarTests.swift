import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct InlineCostHistoryCalendarTests {
    @Test(arguments: [UsageProvider.claude, .pi])
    func `local history providers preserve calendar slots and unpriced days`(provider: UsageProvider) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)))
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 100,
            sessionCostUSD: 3,
            last30DaysTokens: 300,
            last30DaysCostUSD: 7,
            historyDays: 4,
            daily: [
                CostUsageDailyReport.Entry(
                    date: "2026-07-12",
                    inputTokens: 100,
                    outputTokens: 0,
                    totalTokens: 100,
                    costUSD: 3,
                    modelsUsed: [],
                    modelBreakdowns: nil),
                CostUsageDailyReport.Entry(
                    date: "2026-07-14",
                    inputTokens: 100,
                    outputTokens: 0,
                    totalTokens: 100,
                    costUSD: nil,
                    modelsUsed: [],
                    modelBreakdowns: nil),
                CostUsageDailyReport.Entry(
                    date: "2026-07-15",
                    inputTokens: 100,
                    outputTokens: 0,
                    totalTokens: 100,
                    costUSD: 4,
                    modelsUsed: [],
                    modelBreakdowns: nil),
            ],
            updatedAt: now)
        let metadata = try #require(ProviderDefaults.metadata[provider])
        let model = UsageMenuCardView.Model.make(.init(
            provider: provider,
            metadata: metadata,
            snapshot: UsageSnapshot(primary: nil, secondary: nil, updatedAt: now),
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: snapshot,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: true,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            costUsageBucketCalendar: calendar,
            now: now))
        let points = try #require(model.inlineUsageDashboard?.points)
        #expect(points.map(\.id) == ["2026-07-12", "2026-07-13", "2026-07-14", "2026-07-15"])
        #expect(points.map { $0.value as Double? } == [3, 0, nil, 4])
        #expect(points.map { $0.hoverDetail?.tokenCount } == [100, 0, 100, 100])
    }
}
