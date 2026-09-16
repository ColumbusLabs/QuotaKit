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
struct CodexRollingCostWindowPartialTests {
    // MARK: - Reproduction 2: valid partial progress across a rolling-window rollover

    @Test
    func `partial catch-up accepts rollover when the oldest day legitimately expires`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            calendar: calendar,
            established: false,
            sessionCostUSD: 1,
            sessionTokens: 100)
        var candidateRows = current.daily.filter { $0.date != "2026-08-17" }
        candidateRows.append(CodexRollingCostWindowFixture.row("2026-09-16", cost: 11, tokens: 1100))
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: candidateRows,
            endDate: candidateEnd,
            calendar: calendar,
            established: false,
            sessionCostUSD: 11,
            sessionTokens: 1100)
        #expect(candidate.last30DaysCostUSD == 40)
        #expect(candidate.last30DaysTokens == 4000)

        let accepted = try #require(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar))

        #expect(accepted.historySinceDayKey == "2026-08-18")
        #expect(accepted.historyUntilDayKey == "2026-09-16")
        #expect(accepted.historyCoverageIsEstablished == false)
    }

    // MARK: - Partial history matrix

    @Test(arguments: [1, 7, 30, 365])
    func `partial rollover accepts the expired oldest day for every window length`(days: Int) throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: days,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            historyDays: days,
            calendar: calendar,
            established: false)
        var candidateRows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: candidateEnd,
            days: days,
            calendar: calendar,
            cost: 1,
            tokens: 100)
        candidateRows = CodexRollingCostWindowFixture.replacing(
            candidateRows,
            dayKey: "2026-09-16",
            cost: 11,
            tokens: 1100)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: candidateRows,
            endDate: candidateEnd,
            historyDays: days,
            calendar: calendar,
            established: false)

        let accepted = try #require(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar))

        #expect(accepted == candidate)
        #expect(accepted.historyDays == days)
        #expect(accepted.historyCoverageIsEstablished == false)
    }

    @Test
    func `partial accepts unchanged same-window values`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, hour: 8, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, hour: 23, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: current.daily,
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)

        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar) == candidate)
    }

    @Test
    func `partial rejects an in-window row that disappears`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            calendar: calendar,
            established: false)
        let candidateRows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: candidateEnd,
            days: 30,
            calendar: calendar,
            cost: 1,
            tokens: 100)
            .filter { $0.date != "2026-09-10" }
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: candidateRows,
            endDate: candidateEnd,
            calendar: calendar,
            established: false)

        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar) == nil)
    }

    @Test
    func `partial rejects an in-window cost regression`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            calendar: calendar,
            established: false)
        var candidateRows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: candidateEnd,
            days: 30,
            calendar: calendar,
            cost: 1,
            tokens: 100)
        candidateRows = CodexRollingCostWindowFixture.replacing(
            candidateRows,
            dayKey: "2026-09-10",
            cost: 0.5,
            tokens: 100)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: candidateRows,
            endDate: candidateEnd,
            calendar: calendar,
            established: false)

        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar) == nil)
    }

    @Test
    func `partial rejects an in-window token regression`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            calendar: calendar,
            established: false)
        var candidateRows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: candidateEnd,
            days: 30,
            calendar: calendar,
            cost: 1,
            tokens: 100)
        candidateRows = CodexRollingCostWindowFixture.replacing(
            candidateRows,
            dayKey: "2026-09-10",
            cost: 1,
            tokens: 50)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: candidateRows,
            endDate: candidateEnd,
            calendar: calendar,
            established: false)

        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar) == nil)
    }

    @Test
    func `partial rejects a missing cost on a previously priced in-window row`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            calendar: calendar,
            established: false)
        var candidateRows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: candidateEnd,
            days: 30,
            calendar: calendar,
            cost: 1,
            tokens: 100)
        candidateRows = CodexRollingCostWindowFixture.replacing(
            candidateRows,
            dayKey: "2026-09-10",
            cost: nil,
            tokens: 100)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: candidateRows,
            endDate: candidateEnd,
            calendar: calendar,
            established: false)

        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar) == nil)
    }

    @Test
    func `partial rejects missing tokens on a previously counted in-window row`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            calendar: calendar,
            established: false)
        var candidateRows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: candidateEnd,
            days: 30,
            calendar: calendar,
            cost: 1,
            tokens: 100)
        candidateRows = CodexRollingCostWindowFixture.replacing(
            candidateRows,
            dayKey: "2026-09-10",
            cost: 1,
            tokens: nil)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: candidateRows,
            endDate: candidateEnd,
            calendar: calendar,
            established: false)

        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar) == nil)
    }

    @Test
    func `partial accepts an aggregate decrease explained by an expensive expired day`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        var priorRows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: priorEnd,
            days: 7,
            calendar: calendar,
            cost: 1,
            tokens: 100)
        priorRows = CodexRollingCostWindowFixture.replacing(priorRows, dayKey: "2026-09-09", cost: 50, tokens: 5000)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: priorRows,
            endDate: priorEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: candidateEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)

        #expect(current.last30DaysCostUSD == 56)
        #expect(current.last30DaysTokens == 5600)
        #expect(candidate.last30DaysCostUSD == 7)
        #expect(candidate.last30DaysTokens == 700)

        let accepted = try #require(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar))

        #expect(accepted == candidate)
    }

    @Test
    func `partial rejects an aggregate decrease beyond the expired credit`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 7,
                calendar: calendar,
                cost: 10,
                tokens: 100),
            endDate: priorEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)
        let candidateRows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: candidateEnd,
            days: 7,
            calendar: calendar,
            cost: 10,
            tokens: 100)
        let withinCredit = CodexRollingCostWindowFixture.snapshot(
            rows: candidateRows,
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false,
            last30DaysCostUSDOverride: 60,
            last30DaysTokensOverride: 600)
        let beyondCredit = CodexRollingCostWindowFixture.snapshot(
            rows: candidateRows,
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false,
            last30DaysCostUSDOverride: 50,
            last30DaysTokensOverride: 500)

        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            withinCredit,
            over: current,
            calendar: calendar) == withinCredit)
        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            beyondCredit,
            over: current,
            calendar: calendar) == nil)
    }

    @Test
    func `partial keeps the strict bound when the expired contribution is unknown`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        var priorRows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: priorEnd,
            days: 7,
            calendar: calendar,
            cost: 10,
            tokens: 100)
        priorRows = CodexRollingCostWindowFixture.replacing(priorRows, dayKey: "2026-09-09", cost: nil, tokens: 100)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: priorRows,
            endDate: priorEnd,
            historyDays: 7,
            calendar: calendar,
            established: false,
            last30DaysCostUSDOverride: 60)
        let candidateRows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: candidateEnd,
            days: 7,
            calendar: calendar,
            cost: 10,
            tokens: 100)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: candidateRows,
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)
        let regressed = CodexRollingCostWindowFixture.snapshot(
            rows: candidateRows,
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false,
            last30DaysCostUSDOverride: 59)

        // The expired day's cost is unknown, so it cannot justify any aggregate decrease.
        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar) == candidate)
        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            regressed,
            over: current,
            calendar: calendar) == nil)
    }

    @Test
    func `partial accepts a multi-day offline rollover`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 19, hour: 9, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 7,
                calendar: calendar,
                cost: 2,
                tokens: 20),
            endDate: priorEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: candidateEnd,
                days: 7,
                calendar: calendar,
                cost: 2,
                tokens: 20),
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)

        let accepted = try #require(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar))

        #expect(accepted.historySinceDayKey == "2026-09-13")
        #expect(accepted.historyUntilDayKey == "2026-09-19")
    }

    @Test
    func `partial rollover follows the Los Angeles midnight boundary`() throws {
        let calendar = try CodexRollingCostWindowFixture.losAngelesCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, hour: 23, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 1, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: candidateEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)

        let accepted = try #require(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar))

        #expect(accepted.historySinceDayKey == "2026-09-10")
        #expect(accepted.historyUntilDayKey == "2026-09-16")
    }

    @Test
    func `partial rollover accepts the expired day across the DST spring-forward transition`() throws {
        let calendar = try CodexRollingCostWindowFixture.losAngelesCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 3, 7, hour: 23, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 3, 8, hour: 12, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: candidateEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)

        let accepted = try #require(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar))

        #expect(accepted.historySinceDayKey == "2026-03-02")
        #expect(accepted.historyUntilDayKey == "2026-03-08")
    }

    @Test
    func `partial rollover accepts the expired day across the DST fall-back transition`() throws {
        let calendar = try CodexRollingCostWindowFixture.losAngelesCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 10, 31, hour: 23, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 11, 1, hour: 12, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: candidateEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)

        let accepted = try #require(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar))

        #expect(accepted.historySinceDayKey == "2026-10-26")
        #expect(accepted.historyUntilDayKey == "2026-11-01")
    }

    @Test
    func `partial rejects a window that moved backwards`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)
        let candidate = try CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 700,
            last30DaysCostUSD: 7,
            historyDays: 7,
            historyCoverageIsEstablished: false,
            historySinceDayKey: "2026-09-02",
            historyUntilDayKey: "2026-09-08",
            daily: CodexRollingCostWindowFixture.uniformRows(
                endingAt: CodexRollingCostWindowFixture.date(2026, 9, 8, calendar: calendar),
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            updatedAt: candidateEnd)

        #expect(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar) == nil)
    }

    @Test
    func `partial accepts an expanded history window`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: priorEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: priorEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: candidateEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: candidateEnd,
            calendar: calendar,
            established: false)

        let accepted = try #require(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar))

        #expect(accepted.historySinceDayKey == "2026-08-18")
        #expect(accepted.historyUntilDayKey == "2026-09-16")
    }

    @Test
    func `partial compares timestamp entry dates by bucket day`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let priorEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let current = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 200,
            last30DaysCostUSD: 2,
            historyDays: 7,
            historyCoverageIsEstablished: false,
            historySinceDayKey: "2026-09-09",
            historyUntilDayKey: "2026-09-15",
            daily: [
                CodexRollingCostWindowFixture.row("2026-09-14T12:00:00Z", cost: 1, tokens: 100),
                CodexRollingCostWindowFixture.row("2026-09-15T12:00:00Z", cost: 1, tokens: 100),
            ],
            updatedAt: priorEnd)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [
                CodexRollingCostWindowFixture.row("2026-09-14", cost: 1, tokens: 100),
                CodexRollingCostWindowFixture.row("2026-09-15", cost: 1, tokens: 100),
                CodexRollingCostWindowFixture.row("2026-09-16", cost: 1, tokens: 100),
            ],
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)

        let accepted = try #require(UsageStore.codexCostSnapshotAdvancingPartialLowerBound(
            candidate,
            over: current,
            calendar: calendar))

        #expect(accepted == candidate)
    }

    // MARK: - Publication loop

    @Test
    func `pending catch-up republishes when only the coverage bounds advance`() async throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let store = try CodexRollingCostWindowFixture.makeStore(suite: "bounds-only-advance")
        var loadCount = 0
        var bounds: [(since: String, until: String)] = []
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            loadCount += 1
            let end = calendar.date(byAdding: .day, value: loadCount - 1, to: now) ?? now
            let window = CodexRollingCostWindowFixture.window(endingAt: end, days: 30, calendar: calendar)
            bounds.append((window.sinceKey, window.untilKey))
            return CodexRollingCostWindowFixture.snapshot(
                rows: [CodexRollingCostWindowFixture.row(window.untilKey, cost: 1, tokens: 10)],
                endDate: end,
                calendar: calendar,
                established: true)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "stalled")
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, _ in
            CostUsageFetcher.CodexScanCatchUpStatus(pending: true, progressKey: "stalled")
        }
        store._test_codexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        await store.refreshTokenUsage(.codex, force: true)
        await CodexRollingCostWindowFixture.waitUntil { store.codexCostCatchUpTask == nil }

        #expect(loadCount == 4)
        #expect(bounds.count == 4)
        #expect(store.tokenSnapshot(for: .codex)?.historySinceDayKey == bounds.last?.since)
        #expect(store.tokenSnapshot(for: .codex)?.historyUntilDayKey == bounds.last?.until)
        #expect(store.tokenSnapshotPublicationRevision(for: .codex) == 4)
    }
}
