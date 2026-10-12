import Foundation
import LiteCore
import Testing

/// Cases and expected values copied from Tests/CodexBarTests/UsagePaceTests.swift, so the port stays
/// identical to the full app.
struct UsagePaceTests {
    private static let epoch = Date(timeIntervalSince1970: 0)

    private static func weekly(
        used: Double,
        resetIn seconds: TimeInterval,
        now: Date = Self.epoch,
        workDays: Int? = nil,
        calendar: Calendar = .current) -> UsagePace?
    {
        UsagePace.weekly(
            usedPercent: used,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(seconds),
            now: now,
            workDays: workDays,
            calendar: calendar)
    }

    @Test
    func `weekly pace computes delta and eta`() throws {
        let pace = try #require(Self.weekly(used: 50, resetIn: 4 * 24 * 3600))

        #expect(abs(pace.expectedUsedPercent - 42.857) < 0.01)
        #expect(abs(pace.deltaPercent - 7.143) < 0.01)
        #expect(pace.stage == .ahead)
        #expect(pace.willLastToReset == false)
        #expect(abs((pace.etaSeconds ?? 0) - (3 * 24 * 3600)) < 1)
    }

    @Test
    func `weekly pace marks lasts to reset when usage is low`() throws {
        let pace = try #require(Self.weekly(used: 5, resetIn: 4 * 24 * 3600))

        #expect(pace.willLastToReset)
        #expect(pace.etaSeconds == nil)
        #expect(pace.stage == .farBehind)
        #expect(abs((pace.speedMultiplierToReset ?? 0) - 14.25) < 0.01)
    }

    @Test
    func `weekly pace speed headroom uses remaining burn capacity`() throws {
        let pace = try #require(Self.weekly(used: 70, resetIn: 0.7 * 24 * 3600))

        #expect(abs(pace.expectedUsedPercent - 90) < 0.01)
        #expect(pace.willLastToReset)
        #expect(abs((pace.speedMultiplierToReset ?? 0) - 3.857) < 0.01)
    }

    @Test
    func `weekly pace hides when reset missing or outside window`() {
        let missing = UsagePace.weekly(usedPercent: 10, windowMinutes: 10080, resetsAt: nil, now: Self.epoch)
        let tooFar = Self.weekly(used: 10, resetIn: 9 * 24 * 3600)

        #expect(missing == nil)
        #expect(tooFar == nil)
    }

    @Test
    func `weekly pace hides when usage exists but no elapsed`() {
        #expect(Self.weekly(used: 12, resetIn: 7 * 24 * 3600) == nil)
    }

    @Test
    func `weekly pace keeps deficit sign without workdays`() throws {
        // Typed outside the macro: Xcode 26.3's compiler can't type-check the literal arithmetic inside #require.
        let resetIn: TimeInterval = 2 * 24 * 3600 + 19 * 3600
        let pace = try #require(Self.weekly(used: 88, resetIn: resetIn))

        #expect(abs(pace.expectedUsedPercent - (101.0 / 168.0 * 100.0)) < 0.01)
        #expect(pace.deltaPercent > 25)
        #expect(pace.stage == .farAhead)
        #expect(pace.willLastToReset == false)
    }

    @Test
    func `session pace computes delta and eta for five hour window`() throws {
        let pace = try #require(UsagePace.weekly(
            usedPercent: 50,
            windowMinutes: 300,
            resetsAt: Self.epoch.addingTimeInterval(2 * 3600),
            now: Self.epoch,
            defaultWindowMinutes: 300))

        #expect(abs(pace.expectedUsedPercent - 60.0) < 0.01)
        #expect(abs(pace.deltaPercent - -10.0) < 0.01)
        #expect(pace.stage == .behind)
        #expect(pace.willLastToReset)
    }

    // MARK: - Workday-aware pace

    @Test
    func `workday aware pace shows on track for five day user on friday`() throws {
        let calendar = Self.utcCalendar
        let resetsAt = try Self.date(year: 2026, month: 6, day: 14, hour: 0, calendar: calendar)
        let now = resetsAt.addingTimeInterval(-30 * 3600)

        let pace7 = try #require(Self.weekly(used: 100, resetIn: 30 * 3600, now: now))
        let pace5 = try #require(Self.weekly(
            used: 100,
            resetIn: 30 * 3600,
            now: now,
            workDays: 5,
            calendar: calendar))

        #expect(pace7.deltaPercent > 15)
        #expect(abs(pace5.expectedUsedPercent - 95) < 0.01)
        #expect(abs(pace5.deltaPercent) <= 5)
    }

    @Test
    func `workday aware pace shows on track midweek`() throws {
        let calendar = Self.utcCalendar
        let resetsAt = try Self.date(year: 2026, month: 6, day: 14, hour: 0, calendar: calendar)
        let now = resetsAt.addingTimeInterval(-72 * 3600)

        let pace5 = try #require(Self.weekly(
            used: 60,
            resetIn: 72 * 3600,
            now: now,
            workDays: 5,
            calendar: calendar))

        #expect(abs(pace5.expectedUsedPercent - 60) < 0.01)
        #expect(abs(pace5.deltaPercent) < 0.01)
    }

    @Test
    func `workday aware exhausted quota does not last through weekend`() throws {
        let calendar = Self.utcCalendar
        let resetsAt = try Self.date(year: 2026, month: 6, day: 14, hour: 0, calendar: calendar)
        let now = try Self.date(year: 2026, month: 6, day: 13, hour: 12, calendar: calendar)

        let pace = try #require(UsagePace.weekly(
            usedPercent: 100,
            windowMinutes: 10080,
            resetsAt: resetsAt,
            now: now,
            workDays: 5,
            calendar: calendar))

        #expect(pace.willLastToReset == false)
        #expect(pace.etaSeconds == 0)
    }

    @Test
    func `workday aware eta maps work time across a weekend`() throws {
        let calendar = Self.utcCalendar
        let resetsAt = try Self.date(year: 2026, month: 6, day: 17, hour: 0, calendar: calendar)
        let now = try Self.date(year: 2026, month: 6, day: 12, hour: 12, calendar: calendar)

        let pace = try #require(UsagePace.weekly(
            usedPercent: 60,
            windowMinutes: 10080,
            resetsAt: resetsAt,
            now: now,
            workDays: 5,
            calendar: calendar))

        // 40 work hours remain at the observed rate: 12 hours Friday, all Monday, then 4 hours Tuesday.
        #expect(pace.willLastToReset == false)
        #expect(abs((pace.etaSeconds ?? 0) - (88 * 3600)) < 1)
    }

    @Test
    func `workday aware pace stays flat on non workdays`() throws {
        let calendar = Self.utcCalendar
        let resetsAt = try Self.date(year: 2026, month: 6, day: 17, hour: 0, calendar: calendar)
        let saturday = try Self.date(year: 2026, month: 6, day: 13, hour: 12, calendar: calendar)
        let sunday = try Self.date(year: 2026, month: 6, day: 14, hour: 12, calendar: calendar)

        func pace(at now: Date) throws -> UsagePace {
            try #require(UsagePace.weekly(
                usedPercent: 60,
                windowMinutes: 10080,
                resetsAt: resetsAt,
                now: now,
                workDays: 5,
                calendar: calendar))
        }

        #expect(try abs(pace(at: saturday).expectedUsedPercent - 60) < 0.01)
        #expect(try pace(at: sunday).expectedUsedPercent == pace(at: saturday).expectedUsedPercent)
    }

    @Test
    func `workday aware pace does not declare zero usage safe before first workday`() throws {
        let calendar = Self.utcCalendar
        let resetsAt = try Self.date(year: 2026, month: 6, day: 14, hour: 0, calendar: calendar)
        let now = try Self.date(year: 2026, month: 6, day: 7, hour: 12, calendar: calendar)

        let pace = try #require(UsagePace.weekly(
            usedPercent: 0,
            windowMinutes: 10080,
            resetsAt: resetsAt,
            now: now,
            workDays: 5,
            calendar: calendar))

        #expect(pace.expectedUsedPercent == 0)
        #expect(pace.willLastToReset == false)
        #expect(pace.etaSeconds == nil)
    }

    @Test
    func `workday aware pace splits a non midnight reset at local day boundaries`() throws {
        let calendar = Self.utcCalendar
        let resetsAt = try Self.date(year: 2026, month: 6, day: 14, hour: 20, calendar: calendar)
        let now = try Self.date(year: 2026, month: 6, day: 8, hour: 12, calendar: calendar)

        let pace = try #require(UsagePace.weekly(
            usedPercent: 10,
            windowMinutes: 10080,
            resetsAt: resetsAt,
            now: now,
            workDays: 5,
            calendar: calendar))

        #expect(abs(pace.expectedUsedPercent - 10) < 0.01)
        #expect(abs(pace.deltaPercent) < 0.01)
    }

    @Test
    func `workday setting falls back to linear for 1, 7 and nil, and ignores session windows`() throws {
        let linear = try #require(Self.weekly(used: 50, resetIn: 4 * 24 * 3600))
        for workDays in [1, 7] {
            let pace = try #require(Self.weekly(used: 50, resetIn: 4 * 24 * 3600, workDays: workDays))
            #expect(abs(pace.expectedUsedPercent - linear.expectedUsedPercent) < 0.01)
        }

        let session = UsagePace.weekly(
            usedPercent: 50,
            windowMinutes: 300,
            resetsAt: Self.epoch.addingTimeInterval(2 * 3600),
            now: Self.epoch,
            workDays: 5)
        #expect(abs((session?.expectedUsedPercent ?? 0) - 60) < 0.01)
    }

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func date(year: Int, month: Int, day: Int, hour: Int, calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour)))
    }
}
