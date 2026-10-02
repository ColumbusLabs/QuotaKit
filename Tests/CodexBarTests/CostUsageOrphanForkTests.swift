import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageOrphanForkTests {
    @Test(arguments: [false, true], [0, 512])
    func `archived missing parent forks settle without hiding current gaps and recover their parent`(
        currentTokens: Bool,
        byteBudget: Int64) throws
    {
        try self.runScenario(currentTokens: currentTokens, byteBudget: byteBudget, parentDay: "2026-08-15")
    }

    @Test(arguments: [0, 512])
    func `a parent restored outside the scan window stays pending until snapshots arrive`(byteBudget: Int64) throws {
        try self.runScenario(currentTokens: false, byteBudget: byteBudget, parentDay: "2026-08-10")
    }

    @Test(arguments: [0, 512])
    func `working set scans retain orphan coverage and recover restored parents`(byteBudget: Int64) throws {
        try self.runScenario(
            currentTokens: true,
            byteBudget: byteBudget,
            parentDay: "2026-08-10",
            useWorkingSet: true)
    }

    @Test(arguments: [false, true])
    func `pending previous reports lose coverage only when a new orphan overlaps`(overlaps: Bool) async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12)))
        let currentURL = try env.writeCodexSessionFile(
            day: now,
            filename: "current.jsonl",
            contents: """
            {"type":"session_meta","payload":{"id":"current","timestamp":"2026-09-30T04:00:00Z"}}
            {"type":"turn_context","payload":{"model":"gpt-5.4"}}
            {"type":"event_msg","timestamp":"2026-09-30T04:00:01Z","payload":{"type":"token_count",\
            "info":{"total_token_usage":{"input_tokens":20,"output_tokens":2}}}}

            """)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.calendar = calendar
        options.refreshMinIntervalSeconds = 0
        let report = CostUsageScanner.loadDailyReport(
            provider: .codex, since: now, until: now, now: now, options: options)
        #expect(report.data.first?.inputTokens == 20)
        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: calendar)
        let range = CostUsageScanner.CostUsageDayRange(since: now, until: now, calendar: calendar)
        cache.codexPreviousReport = try #require(CostUsageCodexPreviousReport(
            report: report, cache: cache, reportSinceKey: range.sinceKey, reportUntilKey: range.untilKey))

        // Model a persisted bounded refresh: the active file remains partial after a
        // newly discovered, fully parsed missing-parent fork joins the inventory.
        var orphan = try #require(cache.files[currentURL.path])
        orphan.sessionId = "orphan"
        orphan.forkedFromId = "missing-parent"
        orphan.forkBaselineDependencyKey = "missing|missing-parent|discovery|fixture"
        orphan.days = [:]
        orphan.codexRows = []
        orphan.codexCostNanos = nil
        orphan.codexPrioritySurchargeNanos = nil
        orphan.codexStandardCostNanos = nil
        orphan.codexPriorityCostNanos = nil
        orphan.codexStandardTokens = nil
        orphan.codexPriorityTokens = nil
        let orphanDate = overlaps ? now : now.addingTimeInterval(-45 * 86400)
        let orphanMs = Int64(orphanDate.timeIntervalSince1970 * 1000)
        orphan.codexSession?.sessionId = "orphan"
        orphan.codexSession?.forkedFromId = "missing-parent"
        orphan.codexSession?.startedAtUnixMs = orphanMs
        orphan.codexSession?.latestActivityUnixMs = orphanMs
        orphan.codexSession?.latestAcceptedUsageUnixMs = nil
        let orphanURL = env.codexArchivedSessionsRoot.appendingPathComponent("orphan.jsonl")
        try Data(contentsOf: currentURL).write(to: orphanURL)
        let orphanFile = CostUsageScanner.codexFileMetadata(fileURL: orphanURL)
        orphan.mtimeUnixMs = orphanFile.mtimeUnixMs
        orphan.size = orphanFile.size
        orphan.parsedBytes = orphanFile.size
        orphan.codexScanFileId = orphanFile.fileId
        orphan.codexTokenSnapshots = nil
        orphan.codexTokenIndexAnchor = nil
        orphan.codexBufferedUnresolvedForkLines = [.init(
            lineIndex: 1,
            ordinal: nil,
            line: .tokenCount(.init(
                timestamp: orphanDate.ISO8601Format(),
                model: "gpt-5.4",
                turnID: nil,
                last: nil,
                total: .init(input: 100, cached: 0, output: 10))))]
        cache.files[orphanURL.path] = orphan
        cache.files[currentURL.path]?.codexScanComplete = false
        cache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache, calendar: calendar)

        let persisted = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: calendar)
        let previous = CostUsageScanner.codexPreviousReport(
            cache: persisted,
            range: range,
            rootsFingerprint: CostUsageScanner.codexRootsFingerprint(options: options))
        #expect((previous != nil) == !overlaps)
        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 1,
            includePiSessions: false,
            scannerOptions: options)
        #expect(cached?.snapshot.historyCoverageIsEstablished == !overlaps)
        let complete = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 1,
            includePiSessions: false,
            requireCompleteHistory: true,
            scannerOptions: options)
        #expect((complete != nil) == !overlaps)
    }

    private func runScenario(
        currentTokens: Bool,
        byteBudget: Int64,
        parentDay: String,
        useWorkingSet: Bool = false) throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12)))
        let old = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12)))
        for (session, parent) in [("fork-b", "missing-a"), ("fork-c", "missing-a"), ("fork-d", "fork-b")] {
            let forkTime = session == "fork-d" ? "2026-08-15T04:00:02Z" : "2026-08-15T04:00:00Z"
            let tokenTime = currentTokens ? "2026-09-30T04:00:00Z" : "2026-08-15T04:00:03Z"
            let contents = """
            {"type":"session_meta","payload":{"id":"\(session)","forked_from_id":"\(parent)","timestamp":"\(forkTime)"}}
            {"type":"turn_context","payload":{"model":"gpt-5.4"}}
            {"type":"event_msg","timestamp":"\(tokenTime)","payload":{"type":"token_count",\
            "info":{"total_token_usage":{"input_tokens":100,"output_tokens":10}}}}
            {"type":"event_msg","timestamp":"2026-09-30T04:00:00Z","payload":{"type":"task_complete"}}

            """
            try contents.write(
                to: env.codexArchivedSessionsRoot.appendingPathComponent("rollout-2026-08-15-\(session).jsonl"),
                atomically: true,
                encoding: .utf8)
        }
        let currentFile = try env.writeCodexSessionFile(
            day: now,
            filename: "rollout-2026-09-30-current.jsonl",
            contents: """
            {"type":"session_meta","payload":{"id":"current","timestamp":"2026-09-30T04:00:00Z"}}
            {"type":"turn_context","payload":{"model":"gpt-5.4"}}
            {"type":"event_msg","timestamp":"2026-09-30T04:00:01Z","payload":{"type":"token_count",\
            "info":{"total_token_usage":{"input_tokens":20,"output_tokens":2}}}}

            """)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: [],
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.useCodexCatchUpWorkingSet = useWorkingSet
        options.refreshMinIntervalSeconds = 0
        options.calendar = calendar
        options.maxCodexScanBytesPerRefresh = byteBudget
        var clock = now
        func scanUntilSettled() {
            for _ in 0..<32 {
                clock.addTimeInterval(1)
                _ = CostUsageScanner.loadDailyReport(
                    provider: .codex, since: old, until: now, now: clock, options: options)
                if CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: calendar)
                    .codexScanCatchUpPending == false { return }
            }
        }
        scanUntilSettled()
        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: calendar)
        #expect(cache.files.count == 4)
        #expect(cache.files.values.allSatisfy { $0.codexScanComplete == true && $0.parsedBytes == $0.size })
        let orphanFiles = cache.files.values.filter(\.hasBufferedCodexForkRetryLines)
        #expect(orphanFiles.count == 3)
        #expect(orphanFiles.allSatisfy {
            $0.forkBaselineDependencyKey.map(CostUsageScanner.codexDependencyIsMissing) == true
                && !$0.hasPendingCodexScanWork
        })
        #expect(cache.codexScanCatchUpPending == false)
        #expect(cache.codexScanCompletedFiles == 4)
        #expect(cache.codexScanTotalFiles == 4)
        let view = CostUsageStoreAccess.readView(cacheRoot: env.cacheRoot, calendar: calendar, purpose: .report)
        let range = CostUsageScanner.CostUsageDayRange(since: now, until: now, calendar: calendar)
        #expect(view.historyCoverageIsEstablished(
            range: range, rootsFingerprint: CostUsageScanner.codexRootsFingerprint(options: options)) == !currentTokens)
        #expect(view.days["2026-09-30"]?.values.first?.first == 20)
        #expect(!view.hasPendingScan)
        // Production freshness checks use the compact status view, which must retain
        // the same missing-parent lineage even though it omits event history.
        let statusView = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexReadView(
            calendar: calendar, purpose: .status)
        #expect(statusView.historyCoverageIsEstablished(
            range: range, rootsFingerprint: CostUsageScanner.codexRootsFingerprint(options: options)) == !currentTokens)
        if currentTokens {
            #expect(!CostUsageScanner.codexCurrentDayProjectionCanPublish(
                cache: cache,
                roots: CostUsageScanner.codexSessionsRoots(options: options),
                dayKey: "2026-09-30",
                calendar: calendar))
            #expect(!CostUsageScanner.codexRequestedWindowProjectionCanPublish(
                cache: cache,
                roots: CostUsageScanner.codexSessionsRoots(options: options),
                sinceKey: "2026-09-30",
                untilKey: "2026-09-30",
                calendar: calendar))
        }
        let fullRange = CostUsageScanner.CostUsageDayRange(since: old, until: now, calendar: calendar)
        #expect(!view.historyCoverageIsEstablished(
            range: fullRange, rootsFingerprint: CostUsageScanner.codexRootsFingerprint(options: options)))
        #expect(!statusView.historyCoverageIsEstablished(
            range: fullRange, rootsFingerprint: CostUsageScanner.codexRootsFingerprint(options: options)))
        let projection = CostUsageStore(cacheRoot: env.cacheRoot).syncReadCodexReportProjection(calendar: calendar)
        #expect(projection.verifiedScanSinceKey.map { $0 > fullRange.sinceKey } ?? true)
        #expect(view.dailyReport(range: fullRange, cacheRoot: env.cacheRoot).data
            .reduce(0) { $0 + ($1.unmeteredRequestCount ?? 0) } == 3)

        let handle = try FileHandle(forWritingTo: currentFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("""
        {"type":"event_msg","timestamp":"2026-09-30T04:00:02Z","payload":{"type":"token_count",\
        "info":{"total_token_usage":{"input_tokens":30,"output_tokens":3}}}}

        """.utf8))
        try handle.close()
        options.maxCodexScanBytesPerRefresh = 64
        clock.addTimeInterval(1)
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex, since: now, until: now, now: clock, options: options)
        let pending = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: calendar)
        #expect(pending.codexScanCatchUpPending == true)
        #expect((pending.codexPreviousReport != nil) == !currentTokens)
        if !currentTokens {
            #expect(pending.codexPreviousReport?.report.data.first?.inputTokens == 20)
        }
        options.maxCodexScanBytesPerRefresh = byteBudget
        scanUntilSettled()

        try """
        {"type":"session_meta","payload":{"id":"missing-a","timestamp":"\(parentDay)T03:59:58Z"}}
        {"type":"turn_context","payload":{"model":"gpt-5.4"}}
        {"type":"event_msg","timestamp":"\(parentDay)T03:59:59Z","payload":{"type":"token_count",\
        "info":{"total_token_usage":{"input_tokens":60,"output_tokens":6}}}}

        """.write(
            to: env.codexArchivedSessionsRoot.appendingPathComponent("rollout-\(parentDay)-missing-a.jsonl"),
            atomically: true,
            encoding: .utf8)
        scanUntilSettled()
        let recovered = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, calendar: calendar)
        #expect(recovered.codexScanCatchUpPending == false)
        #expect(recovered.files.count == 5)
        #expect(recovered.files.values.allSatisfy { !$0.hasBufferedCodexForkRetryLines })
        for id in ["fork-b", "fork-c", "fork-d"] {
            let usage = try #require(recovered.files.values.first { $0.sessionId == id })
            #expect(usage.codexRows?.reduce(0) { $0 + $1.input } == 40)
        }
    }
}
