import Foundation
import Testing
@testable import CodexBarCore

/// End-to-end coverage of the fallback resolver chain through the
/// production cost-scanner path. This is the test that proves the
/// Mac 0.20.3 `$0` Daily Spend bug (Research/018) cannot recur:
/// when a JSONL log contains a model name the local pricing table
/// doesn't have, the row's `costNanos` must be non-zero (i.e. the
/// resolver substituted a nearby family entry) instead of dropping
/// the row to zero.
///
/// Sibling unit tests in `ClaudeFamilyResolverTests` and
/// `CostUsageScannerClaudeRegressionTests` cover the resolver and
/// scanner in isolation; this single E2E test crosses the seam
/// where the bug originally lived.
struct CostUsageScannerFallbackE2ETests {
    @Test
    func `parseClaudeFile costs unknown model via fallback resolver`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 27)
        let iso = env.isoString(for: day)

        // `claude-opus-4-99` doesn't exist in the live Claude pricing
        // table. Pre-fallback, this row would land with costNanos=0.
        // Post-fallback, the resolver substitutes claude-opus-4-7's
        // pricing → costNanos > 0.
        let fileURL = try env.writeClaudeProjectFile(
            relativePath: "project-fallback/unknown-model.jsonl",
            contents: env.jsonl([
                [
                    "type": "assistant",
                    "timestamp": iso,
                    "sessionId": "fallback-session",
                    "requestId": "req_fallback_e2e",
                    "isSidechain": false,
                    "message": [
                        "id": "msg_fallback_e2e",
                        "model": "claude-opus-4-99",
                        "usage": [
                            "input_tokens": 1000,
                            "cache_creation_input_tokens": 0,
                            "cache_read_input_tokens": 0,
                            "output_tokens": 100,
                        ],
                    ],
                ],
            ]))

        let parsed = CostUsageScanner.parseClaudeFile(
            fileURL: fileURL,
            range: CostUsageScanner.CostUsageDayRange(since: day, until: day),
            providerFilter: .all)

        #expect(parsed.rows.count == 1)
        let row = try #require(parsed.rows.first)
        // Expected cost via fallback to claude-opus-4-7:
        //   1000 * 5e-6 + 100 * 2.5e-5 = 0.005 + 0.0025 = 0.0075 USD
        // costNanos = 0.0075 * 1e9 = 7,500,000.
        // Pin > 0 (the regression guard) and within 1% of expected.
        #expect(row.costNanos > 0, "Unknown model should NOT zero out (Research/018 fix).")
        let expectedNanos = 7_500_000
        let drift = abs(row.costNanos - expectedNanos)
        #expect(
            drift < 100,
            "Fallback cost \(row.costNanos) should match opus-4-7 pricing within rounding.")
    }
}
