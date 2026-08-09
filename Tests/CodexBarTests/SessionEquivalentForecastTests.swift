import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct SessionEquivalentForecastTests {
    private static let weeklyReset = Date(timeIntervalSince1970: 2_000_000_000)

    @Test
    func `uses the median of the latest seven completed session windows`() throws {
        let fixture = Self.historyFixture(burns: [5, 4, 8, 6, 10, 12, 14, 16])

        let estimate = try #require(SessionEquivalentBurnEstimator.estimate(
            histories: fixture.histories,
            currentSessionResetsAt: fixture.currentSessionReset,
            now: fixture.currentSessionReset.addingTimeInterval(-3600)))

        #expect(estimate.sampleCount == 7)
        #expect(estimate.medianWeeklyPercentPerWindow == 10)
    }

    @Test
    func `requires three completed windows with measurable burn`() {
        let fixture = Self.historyFixture(burns: [8, 12])

        let estimate = SessionEquivalentBurnEstimator.estimate(
            histories: fixture.histories,
            currentSessionResetsAt: fixture.currentSessionReset,
            now: fixture.currentSessionReset.addingTimeInterval(-3600))

        #expect(estimate == nil)
    }

    @Test
    func `rejects invalid burn estimates`() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let session = Self.window(used: 20, minutes: 300, resetsAt: now.addingTimeInterval(3600))
        let weekly = Self.window(used: 50, minutes: 10080, resetsAt: now.addingTimeInterval(2 * 24 * 3600))

        for burn in [0.0, .infinity, -.infinity, .nan] {
            #expect(SessionEquivalentForecast.make(
                sessionWindow: session,
                weeklyWindow: weekly,
                burnEstimate: SessionEquivalentBurnEstimate(
                    medianWeeklyPercentPerWindow: burn,
                    sampleCount: 3),
                now: now,
                workDays: nil) == nil)
        }
    }

    @Test
    func `rejects a synthetic Claude session placeholder`() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let session = RateWindow(
            usedPercent: 0,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(3600),
            resetDescription: nil,
            isSyntheticPlaceholder: true)
        let weekly = Self.window(used: 50, minutes: 10080, resetsAt: now.addingTimeInterval(2 * 24 * 3600))

        #expect(SessionEquivalentForecast.make(
            sessionWindow: session,
            weeklyWindow: weekly,
            burnEstimate: SessionEquivalentBurnEstimate(medianWeeklyPercentPerWindow: 10, sampleCount: 3),
            now: now,
            workDays: nil) == nil)
    }

    @Test
    func `floors five hour windows at exact boundaries`() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let session = Self.window(used: 20, minutes: 300, resetsAt: now.addingTimeInterval(3600))
        let burn = SessionEquivalentBurnEstimate(medianWeeklyPercentPerWindow: 10, sampleCount: 3)
        let below = try #require(SessionEquivalentForecast.make(
            sessionWindow: session,
            weeklyWindow: Self.window(
                used: 60,
                minutes: 10080,
                resetsAt: now.addingTimeInterval(10 * 5 * 3600 - 1)),
            burnEstimate: burn,
            now: now,
            workDays: nil))
        let exact = try #require(SessionEquivalentForecast.make(
            sessionWindow: session,
            weeklyWindow: Self.window(
                used: 60,
                minutes: 10080,
                resetsAt: now.addingTimeInterval(10 * 5 * 3600)),
            burnEstimate: burn,
            now: now,
            workDays: nil))

        #expect(below.windowsUntilReset == 9)
        #expect(exact.windowsUntilReset == 10)
    }

    @Test
    func `work day setting excludes weekend capacity`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 17,
            hour: 12)))
        let reset = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 20,
            hour: 12)))
        let session = Self.window(used: 20, minutes: 300, resetsAt: now.addingTimeInterval(3600))
        let weekly = Self.window(used: 60, minutes: 10080, resetsAt: reset)
        let burn = SessionEquivalentBurnEstimate(medianWeeklyPercentPerWindow: 10, sampleCount: 3)

        let everyDay = try #require(SessionEquivalentForecast.make(
            sessionWindow: session,
            weeklyWindow: weekly,
            burnEstimate: burn,
            now: now,
            workDays: nil,
            calendar: calendar))
        let weekdays = try #require(SessionEquivalentForecast.make(
            sessionWindow: session,
            weeklyWindow: weekly,
            burnEstimate: burn,
            now: now,
            workDays: 5,
            calendar: calendar))

        #expect(everyDay.windowsUntilReset == 14)
        #expect(weekdays.windowsUntilReset == 4)
    }

    @Test
    func `formats session quota estimate and reset windows`() {
        let detail = UsagePaceText.sessionEquivalentDetail(forecast: SessionEquivalentForecast(
            estimatedWindowsToExhaustWeekly: 4,
            windowsUntilReset: 9,
            sampleCount: 7,
            weeklyResetsAt: Self.weeklyReset,
            weeklyUsedPercent: 60))

        #expect(detail.leftText == "Est. 4 session quotas left")
        #expect(detail.rightText == "9 windows until reset")
        #expect(detail.accessibilityLabel == "Est. 4 session quotas left · 9 windows until reset")
    }

    @Test
    func `forecast applies only to the matching generic weekly identity`() {
        let weekly = Self.window(used: 60, minutes: 10080, resetsAt: Self.weeklyReset)
        let forecast = SessionEquivalentForecast(
            estimatedWindowsToExhaustWeekly: 4,
            windowsUntilReset: 9,
            sampleCount: 7,
            weeklyResetsAt: Self.weeklyReset,
            weeklyUsedPercent: 60,
            weeklyWindowID: "cursor-weekly")

        #expect(forecast.applies(to: weekly, windowID: "cursor-weekly"))
        #expect(!forecast.applies(to: weekly, windowID: "cursor-team-weekly"))
    }

    @MainActor
    @Test
    func `retained generic provider resolves named session and weekly windows`() throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            extraRateWindows: [
                NamedRateWindow(
                    id: "cursor-session",
                    title: "Session",
                    window: Self.window(used: 20, minutes: 300, resetsAt: now.addingTimeInterval(3600))),
                NamedRateWindow(
                    id: "cursor-weekly",
                    title: "Weekly",
                    window: Self.window(
                        used: 40,
                        minutes: 10080,
                        resetsAt: now.addingTimeInterval(3 * 24 * 3600))),
            ],
            updatedAt: now)

        let windows = try #require(store.sessionEquivalentWindows(provider: .cursor, snapshot: snapshot))

        #expect(windows.session.usedPercent == 20)
        #expect(windows.weekly.usedPercent == 40)
        #expect(windows.weeklyWindowID == "cursor-weekly")
        #expect(windows.historyIdentity != nil)
    }

    private static func window(used: Double, minutes: Int, resetsAt: Date) -> RateWindow {
        RateWindow(
            usedPercent: used,
            windowMinutes: minutes,
            resetsAt: resetsAt,
            resetDescription: nil)
    }

    private static func historyFixture(burns: [Double])
        -> (histories: [PlanUtilizationSeriesHistory], currentSessionReset: Date)
    {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let duration: TimeInterval = 5 * 3600
        let weeklyReset = start.addingTimeInterval(7 * 24 * 3600)
        var sessionEntries: [PlanUtilizationHistoryEntry] = []
        var weeklyEntries: [PlanUtilizationHistoryEntry] = []
        var weeklyUsed = 0.0

        for (index, burn) in burns.enumerated() {
            let windowStart = start.addingTimeInterval(Double(index) * duration)
            let reset = windowStart.addingTimeInterval(duration)
            sessionEntries.append(planEntry(
                at: windowStart.addingTimeInterval(30 * 60),
                usedPercent: 20,
                resetsAt: reset))
            sessionEntries.append(planEntry(
                at: reset.addingTimeInterval(-30 * 60),
                usedPercent: 100,
                resetsAt: reset))
            weeklyEntries.append(planEntry(at: windowStart, usedPercent: weeklyUsed, resetsAt: weeklyReset))
            weeklyUsed += burn
            weeklyEntries.append(planEntry(at: reset, usedPercent: weeklyUsed, resetsAt: weeklyReset))
        }

        return (
            histories: [
                planSeries(name: .session, windowMinutes: 300, entries: sessionEntries),
                planSeries(name: .weekly, windowMinutes: 10080, entries: weeklyEntries),
            ],
            currentSessionReset: start.addingTimeInterval(Double(burns.count + 1) * duration))
    }
}
