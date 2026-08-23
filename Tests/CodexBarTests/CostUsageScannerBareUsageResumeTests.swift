import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageScannerBareUsageResumeTests {
    @Test
    func `codex incremental bare usage resumes persisted session timestamp`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 21)
        let iso = env.isoString(for: day)
        let model = "openai/gpt-5.5"
        let initialContents = try env.jsonl([
            ["type": "turn_context", "timestamp": iso, "payload": ["model": model]],
            [
                "type": "event_msg",
                "timestamp": iso,
                "payload": [
                    "type": "token_count",
                    "info": [
                        "total_token_usage": ["input_tokens": 7, "output_tokens": 3],
                    ],
                ],
            ],
        ])
        let fileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "incremental-bare-timestamp.jsonl",
            contents: initialContents)
        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day)
        let first = CostUsageScanner.parseCodexFile(fileURL: fileURL, range: range)
        let persistedActivity = try #require(first.codexSession.latestActivityUnixMs)

        let appendedContents = try env.jsonl([
            ["result": ["usage": ["input_tokens": 5, "output_tokens": 1]]],
        ])
        try (initialContents + appendedContents).write(to: fileURL, atomically: true, encoding: .utf8)

        let delta = CostUsageScanner.parseCodexFile(
            fileURL: fileURL,
            range: range,
            startOffset: first.parsedBytes,
            initialModel: first.lastModel,
            initialTotals: first.lastCountedTotals,
            initialRawTotalsBaseline: first.lastRawTotalsBaseline,
            initialHasDivergentTotals: first.hasDivergentTotals,
            initialCodexTurnID: first.lastCodexTurnID,
            initialCodexUsageRowIndex: first.rows.count,
            initialLastAcceptedTokenTimestampUnixMs: persistedActivity)
        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)

        #expect(delta.days[dayKey]?["gpt-5.5"] == [5, 0, 1])
        #expect(delta.rows.first?.timestampUnixMs == persistedActivity)
    }
}
