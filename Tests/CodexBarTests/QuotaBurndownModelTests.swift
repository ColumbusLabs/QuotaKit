import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct QuotaBurndownModelTests {
    @Test
    func `builds current window samples and ideal line`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)
        let history = Self.history(entries: [
            Self.entry(hoursBeforeNow: 2, usedPercent: 20, reset: reset),
            Self.entry(hoursBeforeNow: 1, usedPercent: 45, reset: reset),
        ])

        let model = try #require(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 60, reset: reset),
            now: Self.now))

        #expect(model.start == reset.addingTimeInterval(-5 * 3600))
        #expect(model.reset == reset)
        #expect(model.samples == [
            .init(date: Self.now.addingTimeInterval(-2 * 3600), remainingPercent: 80),
            .init(date: Self.now.addingTimeInterval(-3600), remainingPercent: 55),
            .init(date: Self.now, remainingPercent: 40),
        ])
        #expect(model.ideal == [
            .init(date: reset.addingTimeInterval(-5 * 3600), remainingPercent: 100),
            .init(date: reset, remainingPercent: 0),
        ])
    }

    @Test
    func `filters samples to this window and restarts the line after usage drops`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)
        let priorReset = reset.addingTimeInterval(-5 * 3600)
        let history = Self.history(entries: [
            Self.entry(hoursBeforeNow: 4, usedPercent: 95, reset: reset), // Before this window's start.
            Self.entry(hoursBeforeNow: 2, usedPercent: 70, reset: reset.addingTimeInterval(90)),
            Self.entry(hoursBeforeNow: 1.5, usedPercent: 85, reset: reset.addingTimeInterval(121)),
            Self.entry(hoursBeforeNow: 1, usedPercent: 10, reset: reset),
            Self.entry(hoursBeforeNow: 0.75, usedPercent: 20, reset: priorReset), // Prior cycle.
            Self.entry(hoursBeforeNow: 0.5, usedPercent: 25, reset: reset),
            Self.entry(hoursBeforeNow: -1, usedPercent: 95, reset: reset), // After now.
        ])

        let model = try #require(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 30, reset: reset),
            now: Self.now))

        #expect(model.samples == [
            .init(date: Self.now.addingTimeInterval(-3600), remainingPercent: 90),
            .init(date: Self.now.addingTimeInterval(-1800), remainingPercent: 75),
            .init(date: Self.now, remainingPercent: 70),
        ])
    }

    @Test
    func `accepts captures exactly at the window start`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)
        let start = reset.addingTimeInterval(-5 * 3600)
        let history = Self.history(entries: [
            .init(capturedAt: start, usedPercent: 15, resetsAt: reset),
        ])

        let model = try #require(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 25, reset: reset),
            now: Self.now))

        #expect(model.samples.first == .init(date: start, remainingPercent: 85))
    }

    @Test
    func `uses the last value at duplicate capture times and skips nonfinite history`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)
        let duplicateDate = Self.now.addingTimeInterval(-3600)
        let history = Self.history(entries: [
            .init(capturedAt: Self.now.addingTimeInterval(-2 * 3600), usedPercent: .nan, resetsAt: reset),
            .init(capturedAt: duplicateDate, usedPercent: 20, resetsAt: reset),
            .init(capturedAt: duplicateDate, usedPercent: 30, resetsAt: reset),
            .init(capturedAt: Self.now, usedPercent: 40, resetsAt: reset),
        ])

        let model = try #require(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 150, reset: reset),
            now: Self.now))

        #expect(model.samples == [
            .init(date: duplicateDate, remainingPercent: 70),
            .init(date: Self.now, remainingPercent: 0),
        ])
        #expect(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: .infinity, reset: reset),
            now: Self.now) == nil)
    }

    @Test
    func `clamps remaining quota to the displayed range`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)

        let negativeUsage = try #require(QuotaBurndownModel(
            history: Self.history(entries: []),
            window: Self.window(usedPercent: -20, reset: reset),
            now: Self.now))
        let overQuota = try #require(QuotaBurndownModel(
            history: Self.history(entries: []),
            window: Self.window(usedPercent: 120, reset: reset),
            now: Self.now))

        #expect(negativeUsage.samples.last?.remainingPercent == 100)
        #expect(overQuota.samples.last?.remainingPercent == 0)
    }

    @Test
    func `requires a finite active window with a real reset`() {
        let history = Self.history(entries: [])
        let validReset = Self.now.addingTimeInterval(3600)

        #expect(QuotaBurndownModel(
            history: history,
            window: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            now: Self.now) == nil)
        #expect(QuotaBurndownModel(
            history: history,
            window: RateWindow(usedPercent: 10, windowMinutes: 0, resetsAt: validReset, resetDescription: nil),
            now: Self.now) == nil)
        #expect(QuotaBurndownModel(
            history: history,
            window: RateWindow(usedPercent: 10, windowMinutes: -5, resetsAt: validReset, resetDescription: nil),
            now: Self.now) == nil)
        #expect(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 10, reset: Date(timeIntervalSinceReferenceDate: .infinity)),
            now: Self.now) == nil)
        #expect(QuotaBurndownModel(
            history: history,
            window: RateWindow(
                usedPercent: 10,
                windowMinutes: 300,
                resetsAt: validReset,
                resetDescription: nil,
                isSyntheticPlaceholder: true),
            now: Self.now) == nil)

        let resetBeforeNow = Self.now.addingTimeInterval(-1)
        #expect(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 10, reset: resetBeforeNow),
            now: Self.now) == nil)
        let resetTooFarAhead = Self.now.addingTimeInterval(8 * 3600)
        #expect(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 10, reset: resetTooFarAhead),
            now: Self.now) == nil)
        #expect(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 10, reset: validReset),
            now: Date(timeIntervalSinceReferenceDate: .infinity)) == nil)
    }

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static func history(entries: [PlanUtilizationHistoryEntry]) -> PlanUtilizationSeriesHistory {
        PlanUtilizationSeriesHistory(name: .session, windowMinutes: 300, entries: entries)
    }

    private static func entry(
        hoursBeforeNow: Double,
        usedPercent: Double,
        reset: Date?) -> PlanUtilizationHistoryEntry
    {
        PlanUtilizationHistoryEntry(
            capturedAt: self.now.addingTimeInterval(-hoursBeforeNow * 3600),
            usedPercent: usedPercent,
            resetsAt: reset)
    }

    private static func window(usedPercent: Double, reset: Date) -> RateWindow {
        RateWindow(
            usedPercent: usedPercent,
            windowMinutes: 300,
            resetsAt: reset,
            resetDescription: nil)
    }
}
