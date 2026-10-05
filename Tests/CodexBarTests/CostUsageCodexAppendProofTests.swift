import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageCodexAppendProofTests {
    @Test
    func `repeated session growth skips committed prefix comparisons`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 18)
        func token(_ index: Int) -> [String: Any] {
            [
                "type": "event_msg",
                "timestamp": env.isoString(for: day.addingTimeInterval(Double(index))),
                "payload": ["type": "token_count", "info": [
                    "model": "gpt-5.4",
                    "total_token_usage": ["input_tokens": index * 10, "output_tokens": 0],
                    "last_token_usage": ["input_tokens": 10, "output_tokens": 0],
                ]],
            ]
        }
        let metadata: [String: Any] = [
            "type": "session_meta",
            "payload": [
                "id": "growing-session", "source": "vscode", "thread_source": "user",
                "timestamp": env.isoString(for: day),
            ],
        ]
        let file = try env.writeCodexSessionFile(
            day: day,
            filename: "growing-session.jsonl",
            contents: env.jsonl([metadata] + (1...50).map(token)))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.refreshMinIntervalSeconds = 0
        let initial = CostUsageScanner.loadDailyReport(
            provider: .codex, since: day, until: day, now: day.addingTimeInterval(51), options: options)
        #expect(initial.summary?.totalTokens == 500)
        #expect(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot).files[file.path]?.codexLedgerRevision != nil)

        let comparedPrefixItems = LockIsolated(0)
        var hooks = CostUsageStoreTestHooks()
        hooks.codexPrefixComparisonVisit = { path, count in
            if path == file.path { comparedPrefixItems.setValue(comparedPrefixItems.value + count) }
        }
        try CostUsageStoreTestHooks.$current.withValue(hooks) {
            for index in 51...55 {
                let handle = try FileHandle(forWritingTo: file)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(env.jsonl([token(index)]).utf8))
                try handle.close()
                let report = CostUsageScanner.loadDailyReport(
                    provider: .codex,
                    since: day,
                    until: day,
                    now: day.addingTimeInterval(Double(index + 1)),
                    options: options)
                #expect(report.summary?.totalTokens == index * 10)
            }
            #expect(comparedPrefixItems.value == 0)
            let reopened = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
            #expect(reopened.files[file.path]?.codexRows?.count == 55)
            #expect(reopened.files[file.path]?.codexTokenSnapshots?.count == 55)

            // A same-cursor repricing changes the committed revision. A scan based on the old
            // revision must compare the prefix before it can choose an append action.
            let original = try #require(reopened.files[file.path])
            let oldRevision = try #require(original.codexLedgerRevision)
            var repriced = reopened
            var repricedUsage = original
            var rows = try #require(repricedUsage.codexRows)
            let first = try #require(rows.first)
            rows[0] = CostUsageScanner.CodexUsageRow(
                day: first.day,
                model: first.model,
                rawModel: first.rawModel,
                turnID: first.turnID,
                eventIndex: first.eventIndex,
                timestampUnixMs: first.timestampUnixMs,
                input: first.input,
                cached: first.cached,
                output: first.output,
                reasoning: first.reasoning,
                knownCostNanos: first.knownCostNanos,
                unpricedTokens: first.unpricedTokens,
                pricingModel: first.pricingModel,
                pricingMode: "priority",
                responseID: first.responseID,
                requestMirrorKeys: first.requestMirrorKeys)
            repricedUsage.codexRows = rows
            repriced.files[file.path] = repricedUsage
            #expect(!CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: repriced).catchUpRequired)
            #expect(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
                .files[file.path]?.codexLedgerRevision != oldRevision)

            var staleAppend = original
            let oldSize = try #require(staleAppend.parsedBytes)
            let oldFileIdentity = try #require(staleAppend.codexScanFileId)
            staleAppend.size = oldSize + 100
            staleAppend.parsedBytes = oldSize + 100
            staleAppend.codexRows?.append(CostUsageScanner.CodexUsageRow(
                day: CostUsageScanner.CostUsageDayRange.dayKey(from: day),
                model: "gpt-5.4",
                turnID: nil,
                eventIndex: 55,
                timestampUnixMs: Int64(day.addingTimeInterval(56).timeIntervalSince1970 * 1000),
                input: 10,
                cached: 0,
                output: 0))
            staleAppend.codexTokenSnapshots?.append(CostUsageCodexTokenSnapshot(
                timestamp: env.isoString(for: day.addingTimeInterval(56)),
                last: .init(input: 10, cached: 0, output: 0),
                total: .init(input: 560, cached: 0, output: 0),
                endOffset: oldSize + 100))
            staleAppend.codexAppendOnlyPrefix = CostUsageCodexAppendOnlyPrefix(
                path: file.path,
                fileIdentity: oldFileIdentity,
                parsedBytes: oldSize,
                rowCount: 55,
                snapshotCount: 55,
                ledgerRevision: oldRevision)
            var staleCache = reopened
            staleCache.files[file.path] = staleAppend
            comparedPrefixItems.setValue(0)
            #expect(!CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: staleCache).catchUpRequired)
            #expect(comparedPrefixItems.value >= 55)
        }
    }
}
