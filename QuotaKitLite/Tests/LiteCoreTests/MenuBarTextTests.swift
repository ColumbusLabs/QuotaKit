import Foundation
import LiteCore
import Testing

struct MenuBarTextTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func window(_ lane: QuotaWindow.Lane, used: Double, resetIn: TimeInterval = 3600) -> QuotaWindow {
        QuotaWindow(
            label: lane == .session ? "Session" : "Weekly",
            lane: lane,
            usedPercent: used,
            windowMinutes: lane == .session ? 300 : 10080,
            resetsAt: self.now.addingTimeInterval(resetIn))
    }

    @Test
    func `shows what is left of the session window`() {
        let state = ProviderState(provider: .claude, windows: [Self.window(.session, used: 89), Self.window(
            .weekly,
            used: 76)])

        #expect(MenuBarText.percent(for: state, now: Self.now) == "11%")
    }

    @Test
    func `falls back to the weekly window when there is no session`() {
        let state = ProviderState(provider: .codex, windows: [Self.window(.weekly, used: 7)])

        #expect(MenuBarText.percent(for: state, now: Self.now) == "93%")
    }

    @Test
    func `an exhausted window wins over the session`() {
        let state = ProviderState(provider: .claude, windows: [Self.window(.session, used: 40), Self.window(
            .weekly,
            used: 100)])

        #expect(MenuBarText.percent(for: state, now: Self.now) == "0%")
    }

    @Test
    func `a window past its reset shows as full`() {
        let state = ProviderState(provider: .claude, windows: [Self.window(.session, used: 100, resetIn: -60)])

        #expect(MenuBarText.percent(for: state, now: Self.now) == "100%")
    }

    @Test
    func `no data shows no percent`() {
        #expect(MenuBarText.percent(for: ProviderState(provider: .claude), now: Self.now) == nil)
    }
}
