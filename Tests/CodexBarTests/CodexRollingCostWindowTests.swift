import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Regression coverage for the Codex rolling cost window used by the catch-up publication
/// helpers. The producer builds an inclusive local-day window ending on the day it runs; when
/// the day rolls over the oldest date must expire while every in-window date keeps its
/// monotonic lower-bound protection.
@MainActor
@Suite(.serialized)
struct CodexRollingCostWindowTests {
    // MARK: - Reproduction 1: established history must trim the expired day

    @Test
    func `established history trims the expired day when the verified current day advances`() throws {
        let calendar = try Self.utcCalendar()
        let establishedEnd = try Self.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try Self.date(2026, 9, 16, hour: 9, calendar: calendar)
        let established = Self.fixture(
            rows: Self.uniformRows(endingAt: establishedEnd, days: 30, calendar: calendar, cost: 1, tokens: 100),
            endDate: establishedEnd,
            historyDays: 30,
            calendar: calendar,
            established: true,
            sessionCostUSD: 1,
            sessionTokens: 100)
        let candidate = Self.fixture(
            rows: [Self.row(dayKey: "2026-09-16", cost: 1, tokens: 100)],
            endDate: candidateEnd,
            historyDays: 30,
            calendar: calendar,
            established: false,
            sessionCostUSD: 1,
            sessionTokens: 100)
            .build()

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established.build(),
            calendar: calendar))

        #expect(overlaid.daily.count == 30)
        #expect(overlaid.daily.first?.date == "2026-08-18")
        #expect(overlaid.daily.last?.date == "2026-09-16")
        #expect(!overlaid.daily.contains { $0.date == "2026-08-17" })
        #expect(overlaid.last30DaysCostUSD == 30)
        #expect(overlaid.last30DaysTokens == 3000)
        #expect(overlaid.historyDays == 30)
        #expect(overlaid.historySinceDayKey == "2026-08-18")
        #expect(overlaid.historyUntilDayKey == "2026-09-16")
        #expect(overlaid.historyCoverageIsEstablished)

        // The stored aggregate must match an independent rolling recomputation over the same
        // producer window instead of overstating the total by the expired day.
        let summary = overlaid.summary(forLastDays: 30, calendar: calendar)
        #expect(summary.totalCostUSD == overlaid.last30DaysCostUSD)
        #expect(summary.totalTokens == overlaid.last30DaysTokens)
        #expect(summary.entryCount == 30)
    }

    // MARK: - Reproduction 2: valid partial progress across a rolling-window rollover

    @Test
    func `partial catch-up accepts rollover when the oldest day legitimately expires`() throws {
        let calendar = try Self.utcCalendar()
        let priorEnd = try Self.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try Self.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = Self.fixture(
            rows: Self.uniformRows(endingAt: priorEnd, days: 30, calendar: calendar, cost: 1, tokens: 100),
            endDate: priorEnd,
            historyDays: 30,
            calendar: calendar,
            established: false,
            sessionCostUSD: 1,
            sessionTokens: 100)
            .build()
        var candidateRows = current.daily.filter { $0.date != "2026-08-17" }
        candidateRows.append(Self.row(dayKey: "2026-09-16", cost: 11, tokens: 1100))
        let candidate = Self.fixture(
            rows: candidateRows,
            endDate: candidateEnd,
            historyDays: 30,
            calendar: calendar,
            established: false,
            sessionCostUSD: 11,
            sessionTokens: 1100)
            .build()
        #expect(candidate.last30DaysCostUSD == 40)
        #expect(candidate.last30DaysTokens == 4000)

        let advanced = UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar)

        let accepted = try #require(advanced)
        #expect(accepted.historySinceDayKey == "2026-08-18")
        #expect(accepted.historyUntilDayKey == "2026-09-16")
        #expect(accepted.historyCoverageIsEstablished == false)
    }

    @Test
    func `partial catch-up still rejects an in-window cost regression`() throws {
        let calendar = try Self.utcCalendar()
        let priorEnd = try Self.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try Self.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = Self.fixture(
            rows: Self.uniformRows(endingAt: priorEnd, days: 30, calendar: calendar, cost: 1, tokens: 100),
            endDate: priorEnd,
            historyDays: 30,
            calendar: calendar,
            established: false,
            sessionCostUSD: 1,
            sessionTokens: 100)
            .build()
        var candidateRows = current.daily.filter { $0.date != "2026-08-17" }
        candidateRows = candidateRows.map { entry in
            entry.date == "2026-09-10" ? Self.row(dayKey: entry.date, cost: 0.5, tokens: 100) : entry
        }
        candidateRows.append(Self.row(dayKey: "2026-09-16", cost: 11, tokens: 1100))
        let candidate = Self.fixture(
            rows: candidateRows,
            endDate: candidateEnd,
            historyDays: 30,
            calendar: calendar,
            established: false,
            sessionCostUSD: 11,
            sessionTokens: 1100)
            .build()

        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar) == nil)
    }

    // MARK: - Fixtures

    private struct SnapshotFixture {
        var rows: [CostUsageDailyReport.Entry]
        var endDate: Date
        var historyDays: Int
        var calendar: Calendar
        var established: Bool
        var sessionCostUSD: Double?
        var sessionTokens: Int?
        var includeWindowKeys = true
        var currencyCode = "USD"
        var historyLabel: String?
        var meteredCostUSD: Double?
        var costProvenance: CostProvenance = .unknown
        var credentialScopeFingerprint: String?
        var ownership: CostUsageTokenOwnership = .accountScoped
        var projects: [CostUsageProjectBreakdown] = []
        var sessions: [CostUsageSessionBreakdown] = []
        var hourly: [CostUsageHourlyEntry] = []
        var updatedAt: Date?

        func build() -> CostUsageTokenSnapshot {
            let window = CodexRollingCostWindowTests.window(
                endingAt: self.endDate,
                days: self.historyDays,
                calendar: self.calendar)
            let allCarryCost = self.rows.allSatisfy { $0.costUSD != nil }
            let allCarryTokens = self.rows.allSatisfy { $0.totalTokens != nil }
            return CostUsageTokenSnapshot(
                sessionTokens: self.sessionTokens,
                sessionCostUSD: self.sessionCostUSD,
                last30DaysTokens: allCarryTokens ? self.rows.compactMap(\.totalTokens).reduce(0, +) : nil,
                last30DaysCostUSD: allCarryCost ? self.rows.compactMap(\.costUSD).reduce(0, +) : nil,
                currencyCode: self.currencyCode,
                historyDays: self.historyDays,
                historyCoverageIsEstablished: self.established,
                historySinceDayKey: self.includeWindowKeys ? window.sinceKey : nil,
                historyUntilDayKey: self.includeWindowKeys ? window.untilKey : nil,
                historyLabel: self.historyLabel,
                meteredCostUSD: self.meteredCostUSD,
                costProvenance: self.costProvenance,
                credentialScopeFingerprint: self.credentialScopeFingerprint,
                ownership: self.ownership,
                daily: self.rows,
                projects: self.projects,
                sessions: self.sessions,
                hourly: self.hourly,
                updatedAt: self.updatedAt ?? self.endDate)
        }
    }

    private static func fixture(
        rows: [CostUsageDailyReport.Entry],
        endDate: Date,
        historyDays: Int,
        calendar: Calendar,
        established: Bool,
        sessionCostUSD: Double? = nil,
        sessionTokens: Int? = nil) -> SnapshotFixture
    {
        SnapshotFixture(
            rows: rows,
            endDate: endDate,
            historyDays: historyDays,
            calendar: calendar,
            established: established,
            sessionCostUSD: sessionCostUSD,
            sessionTokens: sessionTokens)
    }

    private nonisolated static func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return calendar
    }

    private nonisolated static func date(
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

    private nonisolated static func window(
        endingAt end: Date,
        days: Int,
        calendar: Calendar) -> (sinceKey: String, untilKey: String)
    {
        let untilKey = CostUsageLocalDay.key(from: end, calendar: calendar)
        let sinceDate = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: end) ?? end
        return (CostUsageLocalDay.key(from: sinceDate, calendar: calendar), untilKey)
    }

    private nonisolated static func row(dayKey: String, cost: Double?, tokens: Int?) -> CostUsageDailyReport.Entry {
        CostUsageDailyReport.Entry(
            date: dayKey,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: tokens,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }

    private nonisolated static func uniformRows(
        endingAt end: Date,
        days: Int,
        calendar: Calendar,
        cost: Double,
        tokens: Int) -> [CostUsageDailyReport.Entry]
    {
        (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return Self.row(
                dayKey: CostUsageLocalDay.key(from: date, calendar: calendar),
                cost: cost,
                tokens: tokens)
        }
    }
}
