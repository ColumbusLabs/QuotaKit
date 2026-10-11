import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(SQLite3)
import SQLite3
import Testing
@testable import CodexBarCore

// This bounded cross-refresh convergence fixture has its own suite. The explicit per-operation
// performance gates remain in CostUsagePerformanceGateTests unchanged.
@Suite(.serialized)
struct CostUsagePriorityDrainPerformanceGateTests {
    @Test
    func `working set durably drains priority paths beyond one candidate prefix`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let iso = env.isoString(for: day)
        let model = "gpt-5.5"
        let fileCount = CostUsageScanner.codexCatchUpScanCandidateLimit + 18
        for index in 0..<fileCount {
            // swiftlint:disable line_length
            let body = [
                #"{"type":"session_meta","timestamp":"\#(iso)","payload":{"session_id":"priority-\#(index)"}}"#,
                #"{"type":"turn_context","timestamp":"\#(iso)","payload":{"model":"\#(model)"}}"#,
                #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"task_started","turn_id":"priority-turn"}}"#,
                #"{"type":"event_msg","timestamp":"\#(iso)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10},"model":"\#(model)"}}}"#,
            ].joined(separator: "\n") + "\n"
            // swiftlint:enable line_length
            _ = try env.writeCodexSessionFile(
                day: day,
                filename: "priority-\(index).jsonl",
                contents: body)
        }
        let dbURL = env.root.appendingPathComponent("logs_2.sqlite")
        try CostUsageSQLiteFixtures.createTestLogsDatabase(at: dbURL)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: dbURL,
            maxCodexSessionFileBytes: 0,
            maxCodexScanBytesPerRefresh: 0)
        options.refreshMinIntervalSeconds = 0

        func readMetadataOnlyCache() throws -> CostUsageCache {
            let cache = CostUsageStoreAccess.loadCodexWorkingSet(
                cacheRoot: env.cacheRoot,
                calendar: options.calendar,
                hydratingPaths: Set<String>()).cache
            try #require(cache.files.count == fileCount)
            return cache
        }

        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)
        let originalCache = try readMetadataOnlyCache()
        let originalTurnKeys = originalCache.codexPriorityTurnKeys
        let originalCursor = originalCache.codexPriorityTurnsCursor

        try CostUsageSQLiteFixtures.insertTestLog(
            dbURL: dbURL,
            timestamp: iso,
            body: "thread_id=thread turn.id=priority-turn websocket request: "
                + #"{"type":"response.create","model":"gpt-5.5","service_tier":"priority"}"#)
        options.useCodexCatchUpWorkingSet = true
        options.maxCodexScanDurationPerRefresh = 60

        var cache = CostUsageCache()
        var sawPendingTail = false
        let maximumPasses = (fileCount + CostUsageScanner.codexCatchUpHydrationPathLimit - 1)
            / CostUsageScanner.codexCatchUpHydrationPathLimit + 2
        for pass in 1...maximumPasses {
            _ = CostUsageScanner.loadDailyReport(
                provider: .codex,
                since: day,
                until: day,
                now: day.addingTimeInterval(TimeInterval(pass)),
                options: options)
            cache = try readMetadataOnlyCache()
            if cache.codexActiveLookbackState?.pendingFilePaths.isEmpty == false {
                sawPendingTail = true
                #expect(cache.codexPriorityTurnKeys == originalTurnKeys)
                #expect(cache.codexPriorityTurnsCursor == originalCursor)
            } else if cache.codexScanCatchUpPending != true {
                break
            }
        }

        #expect(sawPendingTail)
        #expect(cache.codexActiveLookbackState?.pendingFilePaths.isEmpty != false)
        #expect(cache.codexPriorityTurnKeys != originalTurnKeys)
        let completed = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: day,
            historyDays: 1,
            includePiSessions: false,
            scannerOptions: options)
        #expect(completed?.snapshot.daily.first?.modelBreakdowns?.first?.priorityTokens == fileCount * 110)
    }
}
#endif
