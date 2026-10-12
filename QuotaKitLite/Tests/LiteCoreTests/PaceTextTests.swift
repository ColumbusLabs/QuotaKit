import Foundation
import LiteCore
import Testing

/// Expected strings copied from Tests/CodexBarTests/UsagePaceTextTests.swift.
struct PaceTextTests {
    private static let now = Date(timeIntervalSince1970: 0)

    private static func window(
        _ lane: QuotaWindow.Lane,
        used: Double,
        resetIn seconds: TimeInterval?,
        projected: Bool = false) -> QuotaWindow
    {
        QuotaWindow(
            label: lane == .session ? "Session" : "Weekly",
            lane: lane,
            usedPercent: used,
            windowMinutes: lane == .session ? 300 : 10080,
            resetsAt: seconds.map { Self.now.addingTimeInterval($0) },
            isProjected: projected)
    }

    @Test
    func `weekly deficit shows run out time`() throws {
        let detail = try #require(PaceText.detail(
            for: Self.window(.weekly, used: 50, resetIn: 4 * 24 * 3600),
            provider: .codex,
            now: Self.now))

        #expect(detail.leftLabel == "7% in deficit")
        #expect(detail.rightLabel == "Runs out in 3d")
    }

    @Test
    func `weekly reserve shows headroom for Codex only`() throws {
        let window = Self.window(.weekly, used: 10, resetIn: 4 * 24 * 3600)
        let codex = try #require(PaceText.detail(for: window, provider: .codex, now: Self.now))
        let claude = try #require(PaceText.detail(for: window, provider: .claude, now: Self.now))

        #expect(codex.leftLabel == "33% in reserve")
        #expect(codex.rightLabel == "Lasts until reset · 1.5× headroom")
        #expect(claude.rightLabel == "Lasts until reset")
    }

    @Test
    func `left label rounds the visible delta`() {
        func pace(_ delta: Double) -> UsagePace {
            UsagePace(
                stage: .onTrack,
                deltaPercent: delta,
                expectedUsedPercent: 40,
                actualUsedPercent: 40 + delta,
                etaSeconds: nil,
                willLastToReset: true)
        }

        #expect(PaceText.leftLabel(for: pace(0.6)) == "1% in deficit")
        #expect(PaceText.leftLabel(for: pace(-0.6)) == "1% in reserve")
        #expect(PaceText.leftLabel(for: pace(0.4)) == "On pace")
        #expect(PaceText.leftLabel(for: pace(-0.4)) == "On pace")
    }

    @Test
    func `session deficit shows projected empty time`() throws {
        let detail = try #require(PaceText.detail(
            for: Self.window(.session, used: 80, resetIn: 2 * 3600),
            provider: .claude,
            now: Self.now))

        #expect(detail.leftLabel == "20% in deficit")
        #expect(detail.rightLabel == "Projected empty in 45m")
        #expect(detail.pace.stage == .farAhead)
    }

    @Test
    func `session reserve lasts until reset without Claude headroom`() throws {
        let detail = try #require(PaceText.detail(
            for: Self.window(.session, used: 10, resetIn: 2 * 3600),
            provider: .claude,
            now: Self.now))

        #expect(detail.leftLabel == "50% in reserve")
        #expect(detail.rightLabel == "Lasts until reset")
    }

    @Test
    func `session pace is hidden when missing reset, depleted, or too early`() {
        let missingReset = Self.window(.session, used: 50, resetIn: nil)
        let depleted = Self.window(.session, used: 100, resetIn: 2 * 3600)
        // 5 minutes into a 5-hour window: expected is under 3%.
        let tooEarly = Self.window(.session, used: 1, resetIn: 295 * 60)

        #expect(PaceText.detail(for: missingReset, provider: .claude, now: Self.now) == nil)
        #expect(PaceText.detail(for: depleted, provider: .claude, now: Self.now) == nil)
        #expect(PaceText.detail(for: tooEarly, provider: .claude, now: Self.now) == nil)
    }

    @Test
    func `projected windows get no pace`() {
        let projected = Self.window(.weekly, used: 0, resetIn: 7 * 24 * 3600 - 60, projected: true)

        #expect(PaceText.detail(for: projected, provider: .claude, now: Self.now) == nil)
    }

    @Test
    func `exhausted weekly window runs out now`() throws {
        let detail = try #require(PaceText.detail(
            for: Self.window(.weekly, used: 100, resetIn: 2 * 24 * 3600),
            provider: .claude,
            now: Self.now))

        #expect(detail.rightLabel == "Runs out now")
    }

    @Test
    func `countdown matches the full app format`() {
        func countdown(_ seconds: TimeInterval) -> String {
            ResetText.countdown(to: Self.now.addingTimeInterval(seconds), now: Self.now)
        }

        #expect(countdown(0.5) == "now")
        #expect(countdown(30) == "in 1m")
        #expect(countdown(45 * 60) == "in 45m")
        #expect(countdown(2 * 3600 + 14 * 60) == "in 2h 14m")
        #expect(countdown(3 * 3600) == "in 3h")
        #expect(countdown(28 * 3600) == "in 1d 4h")
        #expect(countdown(24 * 3600 + 5 * 60) == "in 1d 5m")
        #expect(countdown(3 * 24 * 3600) == "in 3d")
    }
}
