import Foundation
import Testing
@testable import LiteCore

struct CardPresentationTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func state(
        windows: [QuotaWindow],
        status: ProviderStatus = .ok,
        plan: String? = "Claude Max 20x",
        fetchedAgo: TimeInterval? = 120) -> ProviderState
    {
        ProviderState(
            provider: .claude,
            windows: windows,
            plan: plan,
            accountEmail: "person@example.com",
            lastFetched: fetchedAgo.map { Self.now.addingTimeInterval(-$0) },
            status: status)
    }

    @Test
    func `rows show the remaining share with a countdown like the full app defaults`() throws {
        // 3h into a 5h session with 80% used: 20% left, expected 60% used, so a red stripe at 40% left.
        let session = QuotaWindow(
            label: "Session",
            lane: .session,
            usedPercent: 80,
            windowMinutes: 300,
            resetsAt: Self.now.addingTimeInterval(2 * 3600))
        let card = CardPresentation(state: Self.state(windows: [session]), now: Self.now)
        let row = try #require(card.metrics.first)

        #expect(row.title == "Session 20% left")
        #expect(row.fillPercent == 20)
        #expect(row.resetText == "Resets in 2h")
        #expect(row.metaText == "20% in deficit · Projected empty in 45m")
        #expect(abs((row.pacePercent ?? 0) - 40) < 0.01)
        #expect(row.paceOnTop == false)
    }

    @Test
    func `on track pace hides the stripe and reserve is green`() throws {
        let onTrack = QuotaWindow(
            label: "Weekly",
            lane: .weekly,
            usedPercent: 50,
            windowMinutes: 10080,
            resetsAt: Self.now.addingTimeInterval(3.5 * 24 * 3600))
        let reserve = QuotaWindow(
            label: "Weekly",
            lane: .weekly,
            usedPercent: 10,
            windowMinutes: 10080,
            resetsAt: Self.now.addingTimeInterval(3.5 * 24 * 3600))

        let onTrackRow = try #require(CardPresentation(state: Self.state(windows: [onTrack]), now: Self.now)
            .metrics.first)
        let reserveRow = try #require(CardPresentation(state: Self.state(windows: [reserve]), now: Self.now)
            .metrics.first)

        #expect(onTrackRow.pacePercent == nil)
        #expect(onTrackRow.metaText == "On pace · Lasts until reset")
        #expect(reserveRow.paceOnTop)
        #expect(abs((reserveRow.pacePercent ?? 0) - 50) < 0.01)
    }

    @Test
    func `a window past its reset shows full and says so`() throws {
        let stale = QuotaWindow(
            label: "Session",
            lane: .session,
            usedPercent: 90,
            windowMinutes: 300,
            resetsAt: Self.now.addingTimeInterval(-60))
        let row = try #require(CardPresentation(state: Self.state(windows: [stale]), now: Self.now).metrics.first)

        #expect(row.title == "Session 100% left")
        #expect(row.metaText == "Reset since last refresh")
        #expect(row.pacePercent == nil)
    }

    @Test
    func `header shows freshness, plan without the provider prefix, and status`() {
        let card = CardPresentation(state: Self.state(windows: []), now: Self.now)

        #expect(card.providerName == "Claude")
        #expect(card.email == "person@example.com")
        #expect(card.plan == "Max 20x")
        #expect(card.subtitle == "Updated 2m ago")
        #expect(card.subtitleIsError == false)
        #expect(card.placeholder == "No usage yet")

        let expired = CardPresentation(state: Self.state(windows: [], status: .tokenExpired), now: Self.now)
        #expect(expired.subtitle == "Token expired — run claude once")
        #expect(expired.subtitleIsError == false)

        let failed = CardPresentation(state: Self.state(windows: [], status: .error("Server error 503")), now: Self.now)
        #expect(failed.subtitle == "Server error 503")
        #expect(failed.subtitleIsError)
    }

    @Test
    func `Codex plans use the full app display names`() {
        var state = Self.state(windows: [], plan: "pro")
        state.provider = .codex

        #expect(CardPresentation(state: state, now: Self.now).plan == "Pro 20x")
    }

    @Test
    func `percent and reset text match the full app formatter`() {
        #expect(CardPresentation.percentText(0) == "0%")
        #expect(CardPresentation.percentText(0.4) == "<1%")
        #expect(CardPresentation.percentText(12.5) == "13%")
        #expect(CardPresentation.resetText(to: Self.now, now: Self.now) == "Resets now")
        #expect(CardPresentation.resetText(to: Self.now.addingTimeInterval(28 * 3600), now: Self.now)
            == "Resets in 1d 4h")
        #expect(CardPresentation.updatedText(since: Self.now.addingTimeInterval(-30), now: Self.now)
            == "Updated just now")
        #expect(CardPresentation.updatedText(since: Self.now.addingTimeInterval(-3 * 3600), now: Self.now)
            == "Updated 3h ago")
    }
}
