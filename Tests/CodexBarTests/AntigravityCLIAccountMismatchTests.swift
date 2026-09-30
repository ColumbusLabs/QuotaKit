import Foundation
import Testing
@testable import CodexBarCore

struct AntigravityCLIAccountMismatchTests {
    @Test
    func `cli HTTPS stops waiting after an identified account mismatch`() async {
        let fetchAttempts = AntigravityAccountMismatchCounter()

        await #expect(throws: AntigravityStatusProbeError.accountMismatch(
            expected: "selected@example.com",
            found: "ambient@example.com"))
        {
            try await AntigravityCLIHTTPSFetchStrategy.waitForSnapshot(
                pid: 123,
                deadline: Date().addingTimeInterval(30),
                expectedAccountEmail: "selected@example.com",
                dependencies: AntigravityCLIHTTPSFetchStrategy.SnapshotWaitDependencies(
                    pollIntervalNanoseconds: 0,
                    listeningPorts: { _, _ in [50080] },
                    drainOutput: { Data() },
                    fetchSnapshot: { _ in
                        fetchAttempts.increment()
                        return AntigravityStatusSnapshot(
                            modelQuotas: [
                                AntigravityModelQuota(
                                    label: "Claude Sonnet",
                                    modelId: "claude-sonnet",
                                    remainingFraction: 0.5,
                                    resetTime: nil,
                                    resetDescription: nil),
                            ],
                            accountEmail: "ambient@example.com",
                            accountPlan: "Pro",
                            source: .local)
                    },
                    now: Date.init))
        }

        #expect(fetchAttempts.value == 1)
    }
}

private final class AntigravityAccountMismatchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        self.lock.lock()
        self.count += 1
        self.lock.unlock()
    }

    var value: Int {
        self.lock.lock()
        let value = self.count
        self.lock.unlock()
        return value
    }
}
