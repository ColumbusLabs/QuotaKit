import Foundation
import Testing
@testable import CodexBarCore

struct AdminAPIUsageLocalDaySelectionTests {
    @Test
    func `Claude Admin current day includes UTC bucket containing positive timezone morning`() throws {
        let calendar = try Self.calendar(timeZoneIdentifier: "Australia/Sydney")
        let now = try Self.date(year: 2026, month: 5, day: 18, hour: 8, timeZoneIdentifier: "Australia/Sydney")
        let staleUTCStart = try Self.date(year: 2026, month: 5, day: 16, hour: 0, timeZoneIdentifier: "UTC")
        let overlappingUTCStart = try Self.date(year: 2026, month: 5, day: 17, hour: 0, timeZoneIdentifier: "UTC")
        let usage = ClaudeAdminAPIUsageSnapshot(
            daily: [
                Self.bucket(day: "2026-05-16", start: staleUTCStart, cost: 9, input: 900, total: 1125),
                Self.bucket(day: "2026-05-17", start: overlappingUTCStart, cost: 2.5, input: 200, total: 260),
            ],
            updatedAt: now)

        let today = usage.summary(forLocalDayContaining: now, calendar: calendar)

        #expect(today.costUSD == 2.5)
        #expect(today.inputTokens == 200)
        #expect(today.totalTokens == 260)
    }

    @Test
    func `Claude Admin current day does not sum adjacent UTC buckets after negative timezone rollover`() throws {
        let calendar = try Self.calendar(timeZoneIdentifier: "America/Los_Angeles")
        let now = try Self.date(
            year: 2026,
            month: 6,
            day: 22,
            hour: 20,
            timeZoneIdentifier: "America/Los_Angeles")
        let previousUTCStart = try Self.date(year: 2026, month: 6, day: 22, hour: 0, timeZoneIdentifier: "UTC")
        let currentUTCStart = try Self.date(year: 2026, month: 6, day: 23, hour: 0, timeZoneIdentifier: "UTC")
        let usage = ClaudeAdminAPIUsageSnapshot(
            daily: [
                Self.bucket(day: "2026-06-22", start: previousUTCStart, cost: 2.5, input: 200, total: 260),
                Self.bucket(day: "2026-06-23", start: currentUTCStart, cost: 4.5, input: 400, total: 510),
            ],
            updatedAt: now)

        let today = usage.summary(forLocalDayContaining: now, calendar: calendar)

        #expect(today.costUSD == 4.5)
        #expect(today.inputTokens == 400)
        #expect(today.totalTokens == 510)
    }

    private static func bucket(
        day: String,
        start: Date,
        cost: Double,
        input: Int,
        total: Int) -> ClaudeAdminAPIUsageSnapshot.DailyBucket
    {
        ClaudeAdminAPIUsageSnapshot.DailyBucket(
            day: day,
            startTime: start,
            endTime: start.addingTimeInterval(86400),
            costUSD: cost,
            inputTokens: input,
            cacheCreationInputTokens: 20,
            cacheReadInputTokens: 10,
            outputTokens: 30,
            totalTokens: total,
            costItems: [],
            models: [])
    }

    private static func calendar(timeZoneIdentifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZoneIdentifier))
        return calendar
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        timeZoneIdentifier: String) throws -> Date
    {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: timeZoneIdentifier)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return try #require(components.date)
    }
}
