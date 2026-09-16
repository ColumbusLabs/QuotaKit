import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageDayWindowTests {
    @Test
    func `explicit producer bounds win over the updatedAt anchor`() throws {
        let calendar = try Self.utcCalendar()
        let updatedAt = try Self.date(2026, 9, 10, calendar: calendar)
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            historyDays: 30,
            historySinceDayKey: "2026-08-17",
            historyUntilDayKey: "2026-09-15",
            daily: [],
            updatedAt: updatedAt)

        let window = snapshot.historyDayWindow(calendar: calendar)

        #expect(window.sinceKey == "2026-08-17")
        #expect(window.untilKey == "2026-09-15")
    }

    @Test(arguments: [1, 7, 30, 365])
    func `fallback window derives from updatedAt and historyDays`(days: Int) throws {
        let calendar = try Self.utcCalendar()
        let updatedAt = try Self.date(2026, 9, 15, calendar: calendar)
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            historyDays: days,
            daily: [],
            updatedAt: updatedAt)

        let window = snapshot.historyDayWindow(calendar: calendar)

        #expect(window.untilKey == "2026-09-15")
        #expect(window.contains("2026-09-15"))
        #expect(!window.contains("2026-09-16"))
        let expectedSince = calendar.date(byAdding: .day, value: -(days - 1), to: updatedAt) ?? updatedAt
        #expect(window.sinceKey == CostUsageLocalDay.key(from: expectedSince, calendar: calendar))
    }

    @Test
    func `fallback window clamps historyDays to the producer range`() throws {
        let calendar = try Self.utcCalendar()
        let updatedAt = try Self.date(2026, 9, 15, calendar: calendar)
        let clamped = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            historyDays: 0,
            daily: [],
            updatedAt: updatedAt)
        let unbounded = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            historyDays: 5000,
            daily: [],
            updatedAt: updatedAt)

        let clampedWindow = clamped.historyDayWindow(calendar: calendar)
        let unboundedWindow = unbounded.historyDayWindow(calendar: calendar)

        #expect(clampedWindow.sinceKey == "2026-09-15")
        #expect(unboundedWindow.sinceKey == "2025-09-16")
    }

    @Test
    func `window day arithmetic follows the calendar across DST`() throws {
        let calendar = try Self.losAngelesCalendar()

        #expect(CostUsageDayWindow.dayKey("2026-03-07", advancedBy: 1, calendar: calendar) == "2026-03-08")
        #expect(CostUsageDayWindow.dayKey("2026-03-08", advancedBy: 1, calendar: calendar) == "2026-03-09")
        #expect(CostUsageDayWindow.dayKey("2026-10-31", advancedBy: 1, calendar: calendar) == "2026-11-01")
        #expect(CostUsageDayWindow.dayKey("2026-11-01", advancedBy: 1, calendar: calendar) == "2026-11-02")
        #expect(CostUsageDayWindow.dayKey("2026-03-08", advancedBy: -1, calendar: calendar) == "2026-03-07")
        #expect(CostUsageDayWindow.dayKey("not-a-day", advancedBy: 1, calendar: calendar) == nil)
        #expect(CostUsageDayWindow.dayKey("2026-03-08", advancedBy: 0, calendar: calendar) == "2026-03-08")
    }

    @Test
    func `entry dates normalize day keys and timestamps into the window`() throws {
        let calendar = try Self.utcCalendar()
        let window = CostUsageDayWindow(sinceKey: "2026-09-01", untilKey: "2026-09-15")

        #expect(window.contains(entryDate: "2026-09-01", calendar: calendar))
        #expect(window.contains(entryDate: "2026-09-15T23:59:59Z", calendar: calendar))
        #expect(!window.contains(entryDate: "2026-08-31T23:59:59Z", calendar: calendar))
        #expect(!window.contains(entryDate: "2026-09-16", calendar: calendar))
        #expect(window.normalizedDayKey(forEntryDate: " 2026-09-05 ", calendar: calendar) == "2026-09-05")
        #expect(window.normalizedDayKey(forEntryDate: "junk", calendar: calendar) == nil)
        #expect(!window.contains(entryDate: "junk", calendar: calendar))
    }

    @Test
    func `fallback window anchors on the bucket calendar day`() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-07-16T06:30:00Z"))
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            historyDays: 1,
            daily: [],
            updatedAt: instant)
        let losAngeles = try Self.losAngelesCalendar()
        let shanghai = try Self.shanghaiCalendar()

        #expect(snapshot.historyDayWindow(calendar: losAngeles).untilKey == "2026-07-15")
        #expect(snapshot.historyDayWindow(calendar: shanghai).untilKey == "2026-07-16")
    }

    private nonisolated static func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return calendar
    }

    private nonisolated static func losAngelesCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        return calendar
    }

    private nonisolated static func shanghaiCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        return calendar
    }

    private nonisolated static func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 12)))
    }
}
