import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageScannerBareUsageResumeTests {
    @Test
    func `codex incremental bare usage ignores later cross-midnight non-usage activity`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let formatter = ISO8601DateFormatter()
        let contextDate = try #require(formatter.date(from: "2026-08-21T23:58:00Z"))
        let usageDate = try #require(formatter.date(from: "2026-08-21T23:59:00Z"))
        let laterActivityDate = try #require(formatter.date(from: "2026-08-22T00:01:00Z"))
        let contextTimestamp = env.isoString(for: contextDate)
        let usageTimestamp = env.isoString(for: usageDate)
        let laterActivityTimestamp = env.isoString(for: laterActivityDate)
        let model = "openai/gpt-5.5"
        let initialContents = try env.jsonl([
            ["type": "turn_context", "timestamp": contextTimestamp, "payload": ["model": model]],
            [
                "type": "event_msg",
                "timestamp": usageTimestamp,
                "payload": [
                    "type": "token_count",
                    "info": [
                        "total_token_usage": ["input_tokens": 7, "output_tokens": 3],
                    ],
                ],
            ],
            ["type": "turn_context", "timestamp": laterActivityTimestamp, "payload": ["model": model]],
        ])
        let fileURL = try env.writeCodexSessionFile(
            day: usageDate,
            filename: "incremental-bare-timestamp.jsonl",
            contents: initialContents)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let range = CostUsageScanner.CostUsageDayRange(
            since: usageDate,
            until: laterActivityDate,
            calendar: utc)
        let first = CostUsageScanner.parseCodexFile(fileURL: fileURL, range: range)
        let restoredSession = try JSONDecoder().decode(
            CostUsageCodexSessionMetadata.self,
            from: JSONEncoder().encode(first.codexSession))
        let persistedUsageTimestamp = try #require(restoredSession.latestAcceptedUsageUnixMs)
        let broadActivityTimestamp = try #require(first.codexSession.latestActivityUnixMs)
        #expect(broadActivityTimestamp > persistedUsageTimestamp)
        #expect(CostUsageScanner.CostUsageDayRange.dayKey(
            from: Date(timeIntervalSince1970: Double(broadActivityTimestamp) / 1000),
            calendar: utc) == "2026-08-22")

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
            initialLastAcceptedTokenTimestampUnixMs: persistedUsageTimestamp)

        #expect(delta.days["2026-08-21"]?["gpt-5.5"] == [5, 0, 1])
        #expect(delta.days["2026-08-22"]?["gpt-5.5"] == nil)
        #expect(delta.rows.first?.timestampUnixMs == persistedUsageTimestamp)
    }
}
