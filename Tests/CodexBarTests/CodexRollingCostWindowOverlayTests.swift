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
struct CodexRollingCostWindowOverlayTests {
    // MARK: - Reproduction 1: established history must trim the expired day

    @Test
    func `established history trims the expired day when the verified current day advances`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: establishedEnd,
            calendar: calendar,
            established: true,
            sessionCostUSD: 1,
            sessionTokens: 100)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-16", cost: 1, tokens: 100)],
            endDate: candidateEnd,
            calendar: calendar,
            established: false,
            sessionCostUSD: 1,
            sessionTokens: 100)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
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

    // MARK: - Established overlay matrix

    @Test(arguments: [1, 7, 30, 365])
    func `overlay trims established history to the candidate window length`(days: Int) throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: days,
                calendar: calendar,
                cost: 1,
                tokens: 100,
                requests: 2),
            endDate: establishedEnd,
            historyDays: days,
            calendar: calendar,
            established: true,
            sessionCostUSD: 1,
            sessionTokens: 100,
            sessionRequests: 2)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-16", cost: 5, tokens: 500, requests: 3)],
            endDate: candidateEnd,
            historyDays: days,
            calendar: calendar,
            established: false,
            sessionCostUSD: 5,
            sessionTokens: 500,
            sessionRequests: 3)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.count == days)
        #expect(overlaid.historyDays == days)
        #expect(overlaid.historyCoverageIsEstablished)
        #expect(overlaid.last30DaysCostUSD == Double(days - 1) + 5)
        #expect(overlaid.last30DaysTokens == (days - 1) * 100 + 500)
        #expect(overlaid.last30DaysRequests == (days - 1) * 2 + 3)
        #expect(overlaid.sessionRequests == 3)
        let summary = overlaid.summary(forLastDays: days, calendar: calendar)
        #expect(summary.totalCostUSD == overlaid.last30DaysCostUSD)
        #expect(summary.entryCount == days)
    }

    @Test
    func `overlay refuses to claim established coverage across an unverified multi-day gap`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let oneDayLater = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let threeDaysLater = try CodexRollingCostWindowFixture.date(2026, 9, 18, hour: 9, calendar: calendar)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: establishedEnd,
            calendar: calendar,
            established: true)
        let adjacent = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-16", cost: 5, tokens: 500)],
            endDate: oneDayLater,
            calendar: calendar,
            established: false)
        let gapped = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-18", cost: 5, tokens: 500)],
            endDate: threeDaysLater,
            calendar: calendar,
            established: false)

        #expect(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            adjacent,
            onto: established,
            calendar: calendar) != nil)
        #expect(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            gapped,
            onto: established,
            calendar: calendar) == nil)
    }

    @Test
    func `overlay refuses a candidate window that moved backwards`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: establishedEnd,
            calendar: calendar,
            established: true)
        let candidate = CostUsageTokenSnapshot(
            sessionTokens: 100,
            sessionCostUSD: 1,
            last30DaysTokens: 100,
            last30DaysCostUSD: 1,
            historyDays: 30,
            historyCoverageIsEstablished: false,
            historySinceDayKey: "2026-08-16",
            historyUntilDayKey: "2026-09-14",
            daily: [CodexRollingCostWindowFixture.row("2026-09-14", cost: 1, tokens: 100)],
            updatedAt: candidateEnd)

        #expect(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar) == nil)
    }

    @Test
    func `overlay replaces an existing current-day row without duplicating it`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, hour: 8, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, hour: 23, calendar: calendar)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: establishedEnd,
            calendar: calendar,
            established: true,
            sessionCostUSD: 1,
            sessionTokens: 100)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-15", cost: 9, tokens: 900)],
            endDate: candidateEnd,
            calendar: calendar,
            established: false,
            sessionCostUSD: 9,
            sessionTokens: 900)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.count == 30)
        #expect(overlaid.daily.count(where: { $0.date == "2026-09-15" }) == 1)
        #expect(overlaid.daily.first { $0.date == "2026-09-15" }?.costUSD == 9)
        #expect(overlaid.last30DaysCostUSD == 38)
        #expect(overlaid.last30DaysTokens == 3800)
        #expect(overlaid.historySinceDayKey == "2026-08-17")
        #expect(overlaid.historyUntilDayKey == "2026-09-15")
        #expect(overlaid.updatedAt == candidateEnd)
    }

    @Test
    func `overlay narrows to a smaller requested history window`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: establishedEnd,
            calendar: calendar,
            established: true)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-16", cost: 5, tokens: 500)],
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.count == 7)
        #expect(overlaid.daily.first?.date == "2026-09-10")
        #expect(overlaid.historyDays == 7)
        #expect(overlaid.historySinceDayKey == "2026-09-10")
        #expect(overlaid.historyUntilDayKey == "2026-09-16")
        #expect(overlaid.last30DaysCostUSD == 11)
    }

    @Test
    func `overlay refuses an expanded history window the established snapshot never covered`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: establishedEnd,
            historyDays: 7,
            calendar: calendar,
            established: true)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-16", cost: 5, tokens: 500)],
            endDate: candidateEnd,
            historyDays: 30,
            calendar: calendar,
            established: false)

        #expect(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar) == nil)
    }

    @Test
    func `overlay records candidate bounds and preserves established metadata`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        let project = CostUsageProjectBreakdown(
            name: "fictional-project-a",
            path: nil,
            totalTokens: 1,
            totalCostUSD: 1,
            daily: [],
            modelBreakdowns: nil)
        let session = CostUsageSessionBreakdown(
            sessionID: "fictional-session-a",
            lastActivity: establishedEnd,
            inputTokens: nil,
            cachedInputTokens: nil,
            outputTokens: nil,
            totalTokens: nil,
            requestCount: nil,
            costUSD: nil,
            modelBreakdowns: [])
        let hourly = CostUsageHourlyEntry(hour: establishedEnd, totalTokens: 1, costUSD: 1)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: establishedEnd,
            calendar: calendar,
            established: true,
            currencyCode: "EUR",
            historyLabel: "30 days",
            meteredCostUSD: 12,
            costProvenance: .listPriceEstimate,
            credentialScopeFingerprint: "fingerprint-a",
            ownership: .machineLocalUnowned,
            projects: [project],
            sessions: [session],
            hourly: [hourly])
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-16", cost: 5, tokens: 500)],
            endDate: candidateEnd,
            calendar: calendar,
            established: false,
            currencyCode: "EUR",
            historyLabel: "candidate window",
            costProvenance: .listPriceEstimate,
            credentialScopeFingerprint: "fingerprint-a",
            ownership: .machineLocalUnowned)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.historySinceDayKey == "2026-08-18")
        #expect(overlaid.historyUntilDayKey == "2026-09-16")
        #expect(overlaid.currencyCode == "EUR")
        // A history label describes the window it was produced for, so a rollover uses the
        // candidate's label instead of the established window's stale one.
        #expect(overlaid.historyLabel == "candidate window")
        #expect(overlaid.costProvenance == .listPriceEstimate)
        #expect(overlaid.credentialScopeFingerprint == "fingerprint-a")
        #expect(overlaid.ownership == .machineLocalUnowned)
        #expect(overlaid.projects == [project])
        #expect(overlaid.sessions == [session])
        #expect(overlaid.hourly == [hourly])
        // Provider-metered spend describes the window it was fetched for, so a rollover
        // must not carry it into the new window.
        #expect(overlaid.meteredCostUSD == nil)
    }

    @Test
    func `same-window overlay preserves provider-metered spend`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, hour: 8, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, hour: 23, calendar: calendar)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: establishedEnd,
            calendar: calendar,
            established: true,
            historyLabel: "30 days",
            meteredCostUSD: 12)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-15", cost: 9, tokens: 900)],
            endDate: candidateEnd,
            calendar: calendar,
            established: false)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.meteredCostUSD == 12)
        #expect(overlaid.historyLabel == "30 days")
    }

    @Test
    func `overlay recomputes totals when an established row lacks a cost`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        var rows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: establishedEnd,
            days: 30,
            calendar: calendar,
            cost: 1,
            tokens: 100)
        rows = CodexRollingCostWindowFixture.replacing(rows, dayKey: "2026-09-10", cost: nil, tokens: 100)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: rows,
            endDate: establishedEnd,
            calendar: calendar,
            established: true)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-16", cost: 5, tokens: 500)],
            endDate: candidateEnd,
            calendar: calendar,
            established: false)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.count == 30)
        #expect(overlaid.last30DaysCostUSD == nil)
        #expect(overlaid.last30DaysTokens == 29 * 100 + 500)
    }

    @Test
    func `overlay keeps an unpriced historical row from completing the window cost`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        var rows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: establishedEnd,
            days: 7,
            calendar: calendar,
            cost: 1,
            tokens: 100)
        rows = rows.map { entry in
            entry.date == "2026-09-12"
                ? CodexRollingCostWindowFixture.row(
                    "2026-09-12",
                    cost: 2,
                    tokens: 100,
                    unpricedRequests: 1)
                : entry
        }
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: rows,
            endDate: establishedEnd,
            historyDays: 7,
            calendar: calendar,
            established: true)
        // A known cost subtotal beside an unpriced day is not a complete window cost, exactly
        // as `CostUsageFetcher.tokenSnapshot` and `CostUsageDailyReport.merged` treat it.
        #expect(established.last30DaysCostUSD == nil)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-16", cost: 1, tokens: 100)],
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.count == 7)
        #expect(overlaid.daily.count(where: { $0.date == "2026-09-12" }) == 1)
        #expect(overlaid.daily.first { $0.date == "2026-09-12" }?.unpricedRequestCount == 1)
        #expect(overlaid.last30DaysCostUSD == nil)
        #expect(overlaid.last30DaysTokens == 700)
    }

    @Test
    func `overlay ignores an established row beyond the candidate window`() throws {
        let calendar = try CodexRollingCostWindowFixture.utcCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 9, calendar: calendar)
        var rows = CodexRollingCostWindowFixture.uniformRows(
            endingAt: establishedEnd,
            days: 30,
            calendar: calendar,
            cost: 1,
            tokens: 100)
        rows.append(CodexRollingCostWindowFixture.row("2026-09-20", cost: 7, tokens: 700))
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: rows,
            endDate: establishedEnd,
            calendar: calendar,
            established: true)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-16", cost: 5, tokens: 500)],
            endDate: candidateEnd,
            calendar: calendar,
            established: false)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.count == 30)
        #expect(!overlaid.daily.contains { $0.date == "2026-09-20" })
        #expect(overlaid.last30DaysCostUSD == 34)
    }

    @Test
    func `overlay follows the Los Angeles midnight boundary`() throws {
        let calendar = try CodexRollingCostWindowFixture.losAngelesCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 9, 15, hour: 23, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 9, 16, hour: 1, calendar: calendar)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: 30,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: establishedEnd,
            calendar: calendar,
            established: true)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-09-16", cost: 5, tokens: 500)],
            endDate: candidateEnd,
            calendar: calendar,
            established: false)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.count == 30)
        #expect(overlaid.daily.first?.date == "2026-08-18")
        #expect(overlaid.daily.last?.date == "2026-09-16")
        #expect(overlaid.historySinceDayKey == "2026-08-18")
        #expect(overlaid.historyUntilDayKey == "2026-09-16")
    }

    @Test
    func `overlay trims the expired day across the DST spring-forward transition`() throws {
        let calendar = try CodexRollingCostWindowFixture.losAngelesCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 3, 7, hour: 23, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 3, 8, hour: 12, calendar: calendar)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: establishedEnd,
            historyDays: 7,
            calendar: calendar,
            established: true)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-03-08", cost: 5, tokens: 500)],
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.count == 7)
        #expect(overlaid.daily.first?.date == "2026-03-02")
        #expect(overlaid.daily.last?.date == "2026-03-08")
        #expect(overlaid.historySinceDayKey == "2026-03-02")
        #expect(overlaid.historyUntilDayKey == "2026-03-08")
    }

    @Test
    func `overlay trims the expired day across the DST fall-back transition`() throws {
        let calendar = try CodexRollingCostWindowFixture.losAngelesCalendar()
        let establishedEnd = try CodexRollingCostWindowFixture.date(2026, 10, 31, hour: 23, calendar: calendar)
        let candidateEnd = try CodexRollingCostWindowFixture.date(2026, 11, 1, hour: 12, calendar: calendar)
        let established = CodexRollingCostWindowFixture.snapshot(
            rows: CodexRollingCostWindowFixture.uniformRows(
                endingAt: establishedEnd,
                days: 7,
                calendar: calendar,
                cost: 1,
                tokens: 100),
            endDate: establishedEnd,
            historyDays: 7,
            calendar: calendar,
            established: true)
        let candidate = CodexRollingCostWindowFixture.snapshot(
            rows: [CodexRollingCostWindowFixture.row("2026-11-01", cost: 5, tokens: 500)],
            endDate: candidateEnd,
            historyDays: 7,
            calendar: calendar,
            established: false)

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.count == 7)
        #expect(overlaid.daily.first?.date == "2026-10-26")
        #expect(overlaid.daily.last?.date == "2026-11-01")
        #expect(overlaid.historySinceDayKey == "2026-10-26")
        #expect(overlaid.historyUntilDayKey == "2026-11-01")
    }
}
