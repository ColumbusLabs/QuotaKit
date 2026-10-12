import Foundation
import LiteCore
import Testing

struct ResetProjectionTests {
    private static let resetsAt = Date(timeIntervalSince1970: 1_000_000)
    private static let session = QuotaWindow(
        label: "Session",
        lane: .session,
        usedPercent: 82,
        windowMinutes: 300,
        resetsAt: Self.resetsAt)

    @Test
    func `window before its reset is unchanged`() {
        let projected = Self.session.projected(at: Self.resetsAt.addingTimeInterval(-1))

        #expect(projected == Self.session)
    }

    @Test
    func `reaching the reset shows zero and moves the reset one window forward`() {
        let projected = Self.session.projected(at: Self.resetsAt)

        #expect(projected.usedPercent == 0)
        #expect(projected.resetsAt == Self.resetsAt.addingTimeInterval(300 * 60))
        #expect(projected.isProjected)
    }

    @Test
    func `several missed resets skip whole windows`() {
        // 2.5 windows after the stored reset: the next reset is 3 windows after it.
        let projected = Self.session.projected(at: Self.resetsAt.addingTimeInterval(2.5 * 300 * 60))

        #expect(projected.resetsAt == Self.resetsAt.addingTimeInterval(3 * 300 * 60))
        #expect(projected.usedPercent == 0)
    }

    @Test
    func `window without a reset time is never projected`() {
        var window = Self.session
        window.resetsAt = nil

        #expect(window.projected(at: Self.resetsAt.addingTimeInterval(86400)) == window)
    }

    @Test
    func `provider projection keeps last fetch time and status`() {
        let fetched = Self.resetsAt.addingTimeInterval(-3600)
        let state = ProviderState(
            provider: .claude,
            windows: [Self.session],
            plan: "Max 20x",
            lastFetched: fetched,
            status: .tokenExpired)

        let projected = state.projected(at: Self.resetsAt.addingTimeInterval(60))

        #expect(projected.windows.first?.usedPercent == 0)
        #expect(projected.lastFetched == fetched)
        #expect(projected.status == .tokenExpired)
        #expect(projected.plan == "Max 20x")
    }
}
