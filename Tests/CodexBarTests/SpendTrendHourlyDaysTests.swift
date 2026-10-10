import Foundation
import Testing
@testable import CodexBar

struct SpendTrendHourlyDaysTests {
    @Test
    func `navigation memo is shared across group copies without changing equality`() throws {
        let first = try Self.date("2026-10-01T01:00:00Z")
        let second = try Self.date("2026-10-03T02:00:00Z")
        let bounds = try Self.date("2026-10-01T00:00:00Z")...Self.date("2026-10-04T00:00:00Z")
        let original = Self.group(
            points: [Self.point(first), Self.point(second)],
            bounds: bounds)
        let rebuilt = Self.group(
            points: [Self.point(first), Self.point(second)],
            bounds: bounds)
        let copy = original

        #expect(original == rebuilt)
        let dates = SpendTrendChartModel.hourlyDays(original)
        #expect(try dates == [Self.date("2026-10-01T00:00:00Z"), Self.date("2026-10-03T00:00:00Z")])
        #expect(original == rebuilt)
        #expect(SpendTrendChartModel.hourlyDays(copy) == dates)
        Self.expectSameBuffer(dates, SpendTrendChartModel.hourlyDays(copy))
        #expect(SpendTrendChartModel.hourlyDays(rebuilt) == dates)
        #expect(original == rebuilt)
    }

    @Test
    func `concurrent first navigation reads return the shared date array`() async throws {
        let first = try Self.date("2026-10-01T01:00:00Z")
        let group = try Self.group(
            points: [Self.point(first), Self.point(first.addingTimeInterval(86400))],
            bounds: Self.date("2026-10-01T00:00:00Z")...Self.date("2026-10-03T00:00:00Z"))
        let results = await withTaskGroup(of: [Date].self) { tasks in
            for _ in 0..<16 {
                tasks.addTask { SpendTrendChartModel.hourlyDays(group) }
            }
            var values: [[Date]] = []
            for await value in tasks {
                values.append(value)
            }
            return values
        }

        let expected = try #require(results.first)
        #expect(expected.count == 2)
        for result in results {
            #expect(result == expected)
            Self.expectSameBuffer(result, expected)
        }
    }

    private static func date(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    private static func point(_ hour: Date) -> SpendDashboardModel.HourlyPoint {
        SpendDashboardModel.HourlyPoint(
            sourceID: "demo-codex",
            provider: .codex,
            providerName: "Demo account",
            hour: hour,
            cost: 1,
            stackStart: 0,
            stackEnd: 1)
    }

    private static func group(
        points: [SpendDashboardModel.HourlyPoint],
        bounds: ClosedRange<Date>) -> SpendDashboardModel.CurrencyGroup
    {
        SpendDashboardModel.CurrencyGroup(
            currencyCode: "USD",
            providers: [],
            models: [],
            dailyPoints: [],
            totalTokens: nil,
            totalCost: nil,
            coveredDayCount: 0,
            chartDomain: bounds,
            modelHistoryCompleteness: .incomplete,
            hourlyPoints: points,
            timeZone: .gmt)
    }

    private static func expectSameBuffer(_ lhs: [Date], _ rhs: [Date]) {
        lhs.withUnsafeBufferPointer { left in
            rhs.withUnsafeBufferPointer { right in
                #expect(left.baseAddress == right.baseAddress)
            }
        }
    }
}
