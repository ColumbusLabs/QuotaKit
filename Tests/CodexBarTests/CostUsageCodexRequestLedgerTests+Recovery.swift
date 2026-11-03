import Foundation
@testable import CodexBarCore

extension CostUsageCodexRequestLedgerTests {
    static func appendPostRecoveryRequests(to survivor: URL, env: CostUsageTestEnvironment) throws {
        let handle = try FileHandle(forWritingTo: survivor)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(env.jsonl([
            Self.record(id: "priced-response-0", usage: [100, 20, 10, 4], total: [100, 20, 10, 4]),
            Self.record(
                id: "new-after-recovery",
                timestamp: Self.timestampC,
                usage: [60, 20, 6, 3],
                total: [560, 120, 56, 23]),
            Self.legacy(timestamp: Self.timestampC, usage: [60, 20, 6, 3], total: [560, 120, 56, 23]),
        ]).utf8))
        try handle.close()
    }
}
