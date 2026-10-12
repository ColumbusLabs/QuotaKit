import Foundation
import LiteCore
import Testing

struct ActivitySignalGateTests {
    private static let roots = ActivityRoots(homeDirectory: "/Users/me")
    private static let codexHome = Self.roots.roots.first { $0.path == "/Users/me/.codex" }!
    private static let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test
    func `Codex activity comes from thread history and auth json only`() {
        let signals = Self.codexHome.signalFiles

        #expect(signals.contains { $0.matches("auth.json") })
        #expect(signals.contains { $0.matches("thread_history_1.sqlite-wal") })
        #expect(signals.contains { $0.matches("thread_history_2.sqlite-wal") })
        #expect(!signals.contains { $0.matches("logs_2.sqlite-wal") })
        #expect(!signals.contains { $0.matches("state_5.sqlite-wal") })
        #expect(!signals.contains { $0.matches("thread_history_1.sqlite") })
        #expect(!signals.contains { $0.matches(".codex-global-state.json") })
    }

    @Test
    func `background churn without a signal change is not activity`() {
        var gate = ActivitySignalGate()
        let listing = ["auth.json": Self.t0, "thread_history_1.sqlite-wal": Self.t0, "logs_2.sqlite-wal": Self.t0]
        gate.seed(Self.codexHome, listing: listing)

        var churned = listing
        churned["logs_2.sqlite-wal"] = Self.t0.addingTimeInterval(30)

        let result1 = gate.hasNewSignal(Self.codexHome, listing: churned)

        #expect(result1 == false)
    }

    @Test
    func `a newer thread history write is activity once`() {
        var gate = ActivitySignalGate()
        gate.seed(Self.codexHome, listing: ["thread_history_1.sqlite-wal": Self.t0])
        let newer = ["thread_history_1.sqlite-wal": Self.t0.addingTimeInterval(5)]

        let result2 = gate.hasNewSignal(Self.codexHome, listing: newer)

        #expect(result2)
        let result3 = gate.hasNewSignal(Self.codexHome, listing: newer)
        #expect(result3 == false)
    }

    @Test
    func `a signal file that appears is activity`() {
        var gate = ActivitySignalGate()
        gate.seed(Self.codexHome, listing: [:])

        let result4 = gate.hasNewSignal(Self.codexHome, listing: ["auth.json": Self.t0])

        #expect(result4)
    }

    @Test
    func `an unseeded root with signal files counts as activity`() {
        var gate = ActivitySignalGate()

        let result5 = gate.hasNewSignal(Self.codexHome, listing: ["auth.json": Self.t0])

        #expect(result5)
        let result6 = gate.hasNewSignal(Self.codexHome, listing: [:])
        #expect(result6 == false)
    }
}
