import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct SpendDashboardMidnightDSTTests {
    @Test
    func `coverage and selected chart bounds use complete civil days around midnight DST`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Santiago"))
        let transition = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12)))
        let next = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12)))
        let nextStart = calendar.startOfDay(for: next)
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 1,
            sessionCostUSD: 1,
            last30DaysTokens: 2,
            last30DaysCostUSD: 2,
            historyDays: 2,
            historyCoverageIsEstablished: true,
            daily: ["2026-09-06", "2026-09-07"].map {
                .init(
                    date: $0,
                    inputTokens: 1,
                    outputTokens: 0,
                    totalTokens: 1,
                    costUSD: 1,
                    modelsUsed: nil,
                    modelBreakdowns: nil)
            },
            updatedAt: next)
        let covered = SpendDashboardModel.build(
            inputs: [.init(provider: .codex, displayName: "Codex", snapshot: snapshot)],
            requestedDays: 2,
            now: next,
            calendar: calendar)
        #expect(covered.groups.first?.coveredDayCount == 2)
        let selected = SpendDashboardModel.build(
            inputs: [.init(provider: .codex, displayName: "Codex", snapshot: snapshot)],
            requestedDays: 2,
            now: transition,
            calendar: calendar,
            selectedDay: transition)
        #expect(selected.groups.first?.chartDomain.upperBound == nextStart)
        #expect(selected.groups.first?.hourlyChartDomain?.upperBound == nextStart)
    }
}
