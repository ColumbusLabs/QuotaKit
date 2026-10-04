import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageCodexRequestLedgerTests {
    private static let timestampA = "2026-08-29T15:59:00Z"
    private static let timestampB = "2026-08-29T16:01:00Z"
    private static let timestampC = "2026-08-29T16:01:05Z"

    @Test
    func `pricing reconstruction retains request identity and mirror aliases`() {
        let row = CostUsageScanner.CodexUsageRow(
            day: "2026-08-29",
            model: "gpt-5",
            turnID: "synthetic-turn",
            eventIndex: 2,
            input: 100,
            cached: 20,
            output: 10,
            knownCostNanos: 123_000_000,
            pricingMode: "priority",
            responseID: "owned-response",
            requestMirrorKeys: ["synthetic-mirror"])
        let priced = CostUsageScanner.codexRowsWithPricingMetadata([row], priorityTurns: [:])
        #expect(priced.first?.responseID == row.responseID)
        #expect(priced.first?.requestMirrorKeys == row.requestMirrorKeys)
        #expect(priced.first?.knownCostNanos == row.knownCostNanos)
        #expect(priced.first?.pricingMode == "priority")
    }

    @Test
    func `staged replacement removes a legacy row after its typed mirror crosses a scan boundary`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let file = env.root.appendingPathComponent("staged-mirror.jsonl")
        let legacy = Self.legacy(timestamp: Self.timestampA, usage: [100, 20, 10, 4], total: [100, 20, 10, 4])
        let prefix = try env.jsonl(Self.header() + [legacy])
        try prefix.write(to: file, atomically: false, encoding: .utf8)
        let start = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let range = CostUsageScanner.CostUsageDayRange(since: start, until: start, calendar: calendar)
        let partial = try CostUsageScanner.parseCodexFileCancellable(fileURL: file, range: range)
        var retained = try #require(partial.rows.first)
        retained.pricingMode = "priority"
        let ledger = Self.record(id: "cross-boundary", usage: [100, 20, 10, 4], total: [100, 20, 10, 4])
        try (prefix + env.jsonl([ledger])).write(to: file, atomically: false, encoding: .utf8)
        let resumed = try CostUsageScanner.parseCodexFileCancellable(
            fileURL: file,
            range: range,
            startOffset: partial.parsedBytes,
            initialModel: partial.lastModel,
            initialSessionID: partial.sessionId,
            initialTotals: partial.lastCountedTotals,
            initialRawTotalsBaseline: partial.lastRawTotalsBaseline,
            initialRawTotalsWatermark: partial.lastRawTotalsWatermark,
            initialSeenRawTotals: partial.seenRawTotals,
            initialCodexUsageRowIndex: partial.nextUsageRowIndex,
            initialRequestLedgerState: partial.requestLedgerState,
            initialRequestLedgerRows: [retained])
        #expect(try resumed.replacedLegacyRowIndices == [#require(retained.eventIndex)])
        #expect(resumed.rows.map(\.responseID) == ["cross-boundary"])
        #expect(resumed.rows.first?.pricingMode == "priority")
        #expect(resumed.requestLedgerState?.responseIDs == ["cross-boundary"])
    }

    @Test(arguments: [false, true], [false, true])
    func `request ledger recovers reset counters without counting both formats`(
        legacyFirst: Bool, spacedJSON: Bool) throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var lines = Self.header()
        let requests: [(String, [Int], [Int], [Int])] = [
            (Self.timestampA, [1000, 200, 100, 40], [1000, 200, 100, 40], [1000, 200, 100, 40]),
            (Self.timestampB, [60, 20, 6, 3], [60, 20, 6, 3], [1060, 220, 106, 43]),
            (Self.timestampC, [60, 20, 6, 3], [120, 40, 12, 6], [1120, 240, 112, 46]),
        ]
        for (index, request) in requests.enumerated() {
            let (timestamp, usage, legacyTotal, threadTotal) = request
            let legacy = Self.legacy(timestamp: timestamp, usage: usage, total: legacyTotal)
            let ledger = Self.record(
                id: "response-\(index)",
                timestamp: timestamp,
                usage: usage,
                total: threadTotal,
                turnTotal: legacyTotal)
            lines += legacyFirst ? [legacy, ledger] : [ledger, legacy]
        }
        let result = try Self.parse(lines, env: env, spacedJSON: spacedJSON)
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 1232)
        #expect(result.rows.filter { $0.day == "2026-08-30" }.reduce(0) { $0 + $1.input + $1.output } == 132)
        #expect(result.rows.reduce(0) { $0 + ($1.reasoning ?? 0) } == 46)
    }

    @Test
    func `ledger and legacy timestamps may differ`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let result = try Self.parse(Self.header() + [
            Self.legacy(timestamp: Self.timestampA, usage: [100, 20, 10, 4], total: [100, 20, 10, 4]),
            Self.record(
                id: "one",
                timestamp: "2026-08-29T15:59:01Z",
                usage: [100, 20, 10, 4],
                total: [100, 20, 10, 4]),
        ], env: env)
        #expect(result.rows.count == 1)
        #expect(result.rows.first?.responseID == "one")
        #expect(result.rows.first?.input == 100)
    }

    @Test(arguments: [false, true], [false, true])
    func `request accounting survives append and SQLite reopen`(legacyFirst: Bool, sameWindow: Bool) async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let start = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        let end = try #require(ISO8601DateFormatter().date(from: Self.timestampC))
        let first = Self.record(id: "one", usage: [1000, 200, 100, 40], total: [1000, 200, 100, 40])
        let mirror = Self.legacy(
            timestamp: Self.timestampA,
            usage: [1000, 200, 100, 40],
            total: [1000, 200, 100, 40])
        let file = try env.writeCodexSessionFile(
            day: start,
            filename: "synthetic-ledger.jsonl",
            contents: env.jsonl(Self.header() + [legacyFirst ? mirror : first]))
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"),
            calendar: calendar)
        func fetch(_ now: Date) async throws -> CostUsageTokenSnapshot {
            try await CostUsageFetcher.loadTokenSnapshot(
                provider: .codex,
                environment: [:],
                now: now,
                forceRefresh: true,
                historyDays: 30,
                allowPricingRefresh: false,
                includePiSessions: false,
                scannerOptions: options)
        }
        let initial = try await fetch(sameWindow ? end : start)
        #expect(initial.sessionTokens == (sameWindow ? 0 : 1100))
        _ = await CostUsageStore(cacheRoot: env.cacheRoot).readSnapshot()
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(env.jsonl([
            legacyFirst ? first : mirror,
            Self.record(
                id: "two",
                timestamp: Self.timestampB,
                usage: [60, 20, 6, 3],
                total: [1060, 220, 106, 43],
                turnTotal: [60, 20, 6, 3]),
            Self.legacy(timestamp: Self.timestampB, usage: [60, 20, 6, 3], total: [60, 20, 6, 3]),
            Self.record(
                id: "three",
                timestamp: Self.timestampC,
                usage: [60, 20, 6, 3],
                total: [1120, 240, 112, 46],
                turnTotal: [120, 40, 12, 6]),
            Self.legacy(timestamp: Self.timestampC, usage: [60, 20, 6, 3], total: [120, 40, 12, 6]),
        ]).utf8))
        try handle.close()
        let resumed = try await fetch(end)
        #expect(resumed.sessionTokens == 132)
        let saved = await CostUsageStore(cacheRoot: env.cacheRoot).readSnapshot()
        #expect(saved.files.allSatisfy { $0.scanState.isComplete == true })
        let stable = try await fetch(end.addingTimeInterval(120))
        #expect(stable.daily == resumed.daily)
        let reopened = await CostUsageStore(cacheRoot: env.cacheRoot).readSnapshot()
        #expect(reopened.usageRows == saved.usageRows)
    }

    @Test
    func `request identity suppresses replay even when replayed counters change`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let result = try Self.parse(Self.header() + [
            Self.record(id: "one", usage: [100, 20, 10, 4], total: [100, 20, 10, 4]),
            Self.record(id: "one", usage: [100, 20, 10, 4], total: [200, 40, 20, 8]),
            Self.record(id: "two", usage: [100, 20, 10, 4], total: [300, 60, 30, 12]),
        ], env: env)
        #expect(result.rows.count == 2)
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 220)
    }

    @Test(arguments: [false, true])
    func `replayed identities also suppress legacy mirrors with changed counters`(legacyFirst: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let replay = Self.record(id: "one", usage: [100, 20, 10, 4], total: [200, 40, 20, 8])
        let mirror = Self.legacy(timestamp: Self.timestampB, usage: [100, 20, 10, 4], total: [200, 40, 20, 8])
        let result = try Self.parse(Self.header() + [
            Self.record(id: "one", usage: [100, 20, 10, 4], total: [100, 20, 10, 4]),
            Self.legacy(timestamp: Self.timestampA, usage: [100, 20, 10, 4], total: [100, 20, 10, 4]),
        ] + (legacyFirst ? [mirror, replay] : [replay, mirror]), env: env)
        #expect(result.rows.count == 1)
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 110)
    }

    @Test
    func `copied parent request records are not billed to a child`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let result = try Self.parse(Self.header() + [
            Self.record(id: "copied", owner: "parent", usage: [1000, 200, 100, 40], total: [1000, 200, 100, 40]),
            Self.record(id: "owned", usage: [60, 20, 6, 3], total: [1060, 220, 106, 43]),
        ], env: env)
        #expect(result.rows.count == 1)
        #expect(result.rows.first?.input == 60)
        #expect(result.rows.first?.output == 6)
    }

    @Test
    func `legacy prefix remains when request records start later`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let result = try Self.parse(Self.header() + [
            Self.legacy(timestamp: Self.timestampA, usage: [1000, 200, 100, 40], total: [1000, 200, 100, 40]),
            Self.record(id: "new", timestamp: Self.timestampB, usage: [60, 20, 6, 3], total: [1060, 220, 106, 43]),
            Self.legacy(timestamp: Self.timestampB, usage: [60, 20, 6, 3], total: [60, 20, 6, 3]),
        ], env: env)
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 1166)
        #expect(result.rows.map(\.day) == ["2026-08-29", "2026-08-30"])
    }

    @Test
    func `legacy-only requests between ledger requests remain counted`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let result = try Self.parse(Self.header() + [
            Self.record(id: "one", usage: [100, 20, 10, 4], total: [100, 20, 10, 4]),
            Self.legacy(timestamp: Self.timestampA, usage: [100, 20, 10, 4], total: [100, 20, 10, 4]),
            Self.legacy(timestamp: Self.timestampB, usage: [50, 10, 5, 2], total: [150, 30, 15, 6]),
            Self.record(
                id: "three",
                timestamp: Self.timestampC,
                usage: [60, 20, 6, 3],
                total: [210, 50, 21, 9]),
        ], env: env)
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 231)
    }

    @Test
    func `archived copies deduplicate by response identity rather than page index`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let result = try Self.parse(Self.header() + [
            Self.record(id: "one", usage: [100, 20, 10, 4], total: [100, 20, 10, 4]),
        ], env: env)
        var state = CostUsageScanner.CodexScanState()
        CostUsageScanner.rememberCodexRows(
            result.rows,
            sessionId: "synthetic-thread",
            fileIdentity: "page-one",
            state: &state)
        let duplicate = CostUsageScanner.CodexUsageRow(
            day: "2026-08-30",
            model: "gpt-5",
            turnID: "synthetic-turn",
            eventIndex: 42,
            input: 100,
            cached: 20,
            output: 10,
            responseID: "one")
        let unique = CostUsageScanner.uniqueCodexRows(
            rows: [duplicate],
            sessionId: "synthetic-thread",
            fileIdentity: "archive-copy",
            state: &state)
        #expect(unique.isEmpty)
        let anotherThread = CostUsageScanner.uniqueCodexRows(
            rows: [duplicate],
            sessionId: "another-thread",
            fileIdentity: "other",
            state: &state)
        #expect(anotherThread.count == 1)
    }

    @Test
    func `totals-only legacy requests retain their baseline after a ledger mirror`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let result = try Self.parse(Self.header() + [
            Self.record(id: "one", usage: [100, 20, 10, 4], total: [100, 20, 10, 4]),
            Self.legacy(timestamp: Self.timestampA, usage: [100, 20, 10, 4], total: [100, 20, 10, 4]),
            ["type": "event_msg", "timestamp": Self.timestampB, "payload": [
                "type": "token_count", "info": ["total_token_usage": Self.tokens([150, 30, 15, 6])],
            ]],
        ], env: env)
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 165)
    }

    @Test
    func `invalid ledger does not disable legacy accounting`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var invalid = Self.record(id: "invalid", usage: [100, 20, 10, 4], total: [100, 20, 10, 4])
        var payload = try #require(invalid["payload"] as? [String: Any])
        payload["usage"] = ["input_tokens": true, "cached_input_tokens": 20, "output_tokens": 10]
        invalid["payload"] = payload
        let result = try Self.parse(Self.header() + [
            invalid,
            Self.legacy(
                timestamp: Self.timestampA,
                usage: [100, 20, 10, 4],
                total: [100, 20, 10, 4]),
        ], env: env)
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 110)
    }

    @Test(arguments: [false, true])
    func `ordinary cached tails retain ownership inside the same reporting window`(legacyFirst: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let date = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let first = Self.record(id: "first", usage: [100, 20, 10, 4], total: [100, 20, 10, 4])
        let file = try env.writeCodexSessionFile(
            day: date, filename: "same-window.jsonl", contents: env.jsonl(Self.header() + [first, Self.legacy(
                timestamp: Self.timestampA, usage: [100, 20, 10, 4], total: [100, 20, 10, 4])]))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"),
            calendar: calendar)
        options.refreshMinIntervalSeconds = 0
        func fetch(_ cacheRoot: URL = env.cacheRoot) -> CostUsageDailyReport {
            var selected = options
            selected.cacheRoot = cacheRoot
            return CostUsageScanner.loadDailyReport(
                provider: .codex, since: date, until: date, now: date, options: selected)
        }
        #expect(fetch().summary?.totalTokens == 110)
        let prefix = try #require(CostUsageStore(cacheRoot: env.cacheRoot)
            .syncLoadCodexCache(calendar: calendar).files[file.path])
        let record = Self.record(
            id: "second",
            timestamp: Self.timestampC,
            usage: [60, 20, 6, 3],
            total: [160, 40, 16, 7])
        let mirror = Self.legacy(timestamp: Self.timestampC, usage: [60, 20, 6, 3], total: [160, 40, 16, 7])
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(env.jsonl(legacyFirst ? [mirror, record] : [record, mirror]).utf8))
        try handle.close()
        let delta = try CostUsageScanner.parseCodexFileCancellable(
            fileURL: file,
            range: .init(since: date, until: date, calendar: calendar),
            startOffset: #require(prefix.parsedBytes),
            initialModel: prefix.lastModel,
            initialSessionID: prefix.sessionId,
            initialTotals: prefix.lastCountedTotals,
            initialRawTotalsBaseline: prefix.lastRawTotalsBaseline,
            initialRawTotalsWatermark: prefix.lastRawTotalsWatermark,
            initialSeenRawTotals: prefix.seenRawTotals ?? [],
            initialCodexTurnID: prefix.lastCodexTurnID,
            initialCodexUsageRowIndex: #require(prefix.codexNextUsageRowIndex),
            initialRequestLedgerState: prefix.codexRequestLedgerState,
            initialRequestLedgerRows: prefix.codexRows ?? [])
        #expect(delta.rows.compactMap(\.responseID) == ["second"])
        #expect(delta.rows.reduce(0) { $0 + $1.input + $1.output } == 66)
        let resumed = fetch()
        #expect(resumed.summary?.totalTokens == 176)
        let cache = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        #expect(cache.files[file.path]?.codexRows?.compactMap(\.responseID) == ["first", "second"])
        #expect(cache.files[file.path]?.codexRows?.count == 2)
        #expect(fetch().data == resumed.data)
        #expect(fetch(env.root.appendingPathComponent("cold-cache")).data == resumed.data)
    }

    @Test(arguments: ["standard", "priority", "known", "unpriced"], [false, true])
    func `cached legacy mirrors retain saved pricing after a separate append`(
        pricing: String, differentTotals: Bool) throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let date = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        var header = Self.header()
        header[1]["payload"] = ["turn_id": "synthetic-turn", "model": "gpt-5.4"]
        let usage = [100_000, 20000, 10000, 4000]
        let file = try env.writeCodexSessionFile(
            day: date, filename: "saved-pricing.jsonl", contents: env.jsonl(header + [Self.legacy(
                timestamp: Self.timestampA, usage: usage, total: usage)]))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"),
            calendar: calendar)
        options.refreshMinIntervalSeconds = 0
        options.useCodexCatchUpWorkingSet = true
        func fetch() -> CostUsageDailyReport {
            var report = CostUsageScanner.loadDailyReport(
                provider: .codex, since: date, until: date, now: date, options: options)
            for _ in 0..<60 {
                let manifest = CostUsageStore(cacheRoot: env.cacheRoot)
                    .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
                if manifest.codexScanCatchUpPending != true { break }
                report = CostUsageScanner.loadDailyReport(
                    provider: .codex, since: date, until: date, now: date, options: options)
            }
            return report
        }
        _ = fetch()
        var saved = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        var cached = try #require(saved.files[file.path])
        var rows = try #require(cached.codexRows)
        #expect(rows.count == 1)
        rows[0].pricingModel = "gpt-5.4"
        rows[0].pricingMode = pricing == "priority" ? "priority" : "standard"
        if pricing == "known" { rows[0].knownCostNanos = 123_000_000 }
        if pricing == "unpriced" { rows[0].unpricedTokens = 110_000 }
        cached.codexRows = rows
        saved.files[file.path] = cached
        #expect(!CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: saved, calendar: calendar)
            .catchUpRequired)
        let expectedCost = CostUsageScanner.codexResolvedCostUSD(
            for: rows[0], modelsDevCatalog: nil, modelsDevCacheRoot: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(env.jsonl([Self.record(
            id: "priced-response",
            usage: usage,
            total: differentTotals ? [200_000, 40000, 20000, 8000] : usage)]).utf8))
        try handle.close()
        let resumed = fetch()
        let reopened = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        let replaced = try #require(reopened.files[file.path]?.codexRows)
        #expect(replaced.count == 1)
        let row = try #require(replaced.first)
        #expect(row.responseID == "priced-response")
        #expect(row.pricingModel == rows[0].pricingModel)
        #expect(row.pricingMode == rows[0].pricingMode)
        #expect(row.knownCostNanos == rows[0].knownCostNanos)
        #expect(row.unpricedTokens == rows[0].unpricedTokens)
        #expect(CostUsageScanner.codexResolvedCostUSD(
            for: row, modelsDevCatalog: nil, modelsDevCacheRoot: nil) == expectedCost)
        #expect(resumed.summary?.totalTokens == 110_000)
        #expect(fetch().data == resumed.data)
    }

    @Test(arguments: [false, true])
    func `ledger ownership distinguishes thread identity from execution session identity`(subagent: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var header = Self.header()
        var metadata: [String: Any] = ["id": "synthetic-thread", "session_id": "execution-session"]
        if subagent {
            metadata["forked_from_id"] = "execution-session"
            metadata["source"] = ["subagent": ["thread_spawn": ["parent_thread_id": "parent"]]]
            metadata["subagent_history_start_ordinal"] = 10
        }
        header[0]["payload"] = metadata
        header[1]["ordinal"] = 10
        var owned = Self.record(id: "owned", usage: [60, 20, 6, 3], total: [60, 20, 6, 3])
        var payload = try #require(owned["payload"] as? [String: Any])
        payload["session_id"] = "execution-session"
        owned["payload"] = payload
        owned["ordinal"] = 11
        var wrongSession = owned
        payload["response_id"] = "wrong-session"
        payload["session_id"] = "another-execution"
        wrongSession["payload"] = payload
        wrongSession["ordinal"] = 12
        let result = try Self.parse(header + [owned, wrongSession], env: env)
        #expect(result.rows.compactMap(\.responseID) == ["owned"])
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 66)
    }

    @Test(arguments: [false, true])
    func `explicit subagent boundary excludes matching thread ledger rows in copied history`(
        hasOwnedSuffix: Bool) throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var header = Self.header()
        header[0]["payload"] = [
            "id": "synthetic-thread",
            "subagent_history_start_ordinal": 10,
            "source": ["subagent": ["thread_spawn": ["parent_thread_id": "parent"]]],
        ]
        header[1]["ordinal"] = 1
        var copied = Self.record(id: "copied", usage: [1000, 200, 100, 40], total: [1000, 200, 100, 40])
        copied["ordinal"] = 2
        var owned = Self.record(id: "owned", usage: [60, 20, 6, 3], total: [1060, 220, 106, 43])
        owned["ordinal"] = 11
        let result = try Self.parse(header + [copied] + (hasOwnedSuffix ? [owned] : []), env: env)
        #expect(result.rows.compactMap(\.responseID) == (hasOwnedSuffix ? ["owned"] : []))
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == (hasOwnedSuffix ? 66 : 0))
    }

    @Test
    func `bounded subagent ledger routing survives serialized replay buffers`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var header = Self.header()
        header[0]["payload"] = [
            "id": "synthetic-thread", "session_id": "execution-session", "subagent_history_start_ordinal": 10,
            "source": ["subagent": ["thread_spawn": ["parent_thread_id": "parent"]]],
        ]
        header[1]["ordinal"] = 10
        func ownedRecord(_ id: String, ordinal: Int, input: Int) throws -> [String: Any] {
            var record = Self.record(id: id, usage: [input, 0, 0, 0], total: [input, 0, 0, 0])
            var payload = try #require(record["payload"] as? [String: Any])
            payload["session_id"] = "execution-session"
            record["payload"] = payload
            record["ordinal"] = ordinal
            return record
        }
        let prefix = try env.jsonl([header[0], ownedRecord("copied", ordinal: 2, input: 1000)])
        let suffix = try env.jsonl([header[1], ownedRecord("owned", ordinal: 11, input: 60)])
        let file = env.root.appendingPathComponent("buffered-ledger.jsonl")
        try (prefix + suffix).write(to: file, atomically: false, encoding: .utf8)
        let day = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day, calendar: .current)
        let partial = try CostUsageScanner.parseCodexFileCancellable(
            fileURL: file, range: range, maxBytesToRead: Int64(prefix.utf8.count))
        #expect(partial.rows.isEmpty)
        let buffer = try #require(partial.bufferedSubagentLines)
        #expect(buffer.contains {
            if case .tokenUsageRecord = $0.line {
                true
            } else {
                false
            }
        })
        let restored = try JSONDecoder().decode(
            [CostUsageScanner.CodexBufferedFastLine].self, from: JSONEncoder().encode(buffer))
        let resumed = try CostUsageScanner.parseCodexFileCancellable(
            fileURL: file,
            range: range,
            startOffset: partial.parsedBytes,
            initialSessionID: partial.sessionId,
            initialBufferedSubagentLines: restored,
            initialJSONLResumeState: partial.jsonlResumeState,
            initialRequestLedgerState: partial.requestLedgerState)
        #expect(resumed.rows.compactMap(\.responseID) == ["owned"])
        #expect(resumed.rows.reduce(0) { $0 + $1.input + $1.output } == 60)
        #expect(resumed.bufferedSubagentLines == nil)
        let cold = try CostUsageScanner.parseCodexFileCancellable(fileURL: file, range: range)
        #expect(resumed.rows == cold.rows)
    }

    @Test(arguments: [false, true])
    func `adjacent mirrors reconcile distinct cumulative domains once`(legacyFirst: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let ledger = Self.record(id: "one", usage: [100, 20, 10, 4], total: [1100, 220, 110, 44])
        let legacy = Self.legacy(timestamp: Self.timestampA, usage: [100, 20, 10, 4], total: [100, 20, 10, 4])
        let result = try Self.parse(Self.header() + (legacyFirst ? [legacy, ledger] : [ledger, legacy]) + [
            Self.legacy(timestamp: Self.timestampB, usage: [100, 20, 10, 4], total: [200, 40, 20, 8]),
            Self.record(id: "two", timestamp: Self.timestampC, usage: [60, 20, 6, 3], total: [1260, 260, 126, 51]),
        ], env: env)
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 286)
        #expect(result.rows.compactMap(\.responseID) == ["one", "two"])
        #expect(result.rows.count == 3)
    }

    @Test
    func `typed records survive the JSON timestamp fallback`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let result = try Self.parse(
            Self.header() + [
                Self.record(id: "escaped-timestamp", usage: [100, 20, 10, 4], total: [100, 20, 10, 4]),
            ],
            env: env,
            transform: { $0.replacingOccurrences(of: #""timestamp""#, with: #""time\u0073tamp""#) })
        #expect(result.rows.compactMap(\.responseID) == ["escaped-timestamp"])
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 110)
    }

    @Test
    func `repeated counter tuples do not replace an earlier legacy request`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let usage = [100, 20, 10, 4]
        let result = try Self.parse(Self.header() + [
            Self.legacy(timestamp: Self.timestampA, usage: usage, total: usage),
            Self.header()[1],
            Self.record(
                id: "after-reset",
                timestamp: Self.timestampB,
                usage: usage,
                total: [200, 40, 20, 8],
                turnTotal: usage),
            Self.legacy(timestamp: Self.timestampB, usage: usage, total: usage),
        ], env: env)
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 220)
        #expect(result.rows.map(\.day) == ["2026-08-29", "2026-08-30"])
    }

    @Test(arguments: [false, true], ["standard", "priority", "known", "unpriced"])
    func `owned response date and saved prices survive cross-file mirrors`(
        ledgerFirst: Bool, pricing: String) throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let start = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        let end = try #require(ISO8601DateFormatter().date(from: Self.timestampC))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let usage = [100, 20, 10, 4]
        let legacy = Self.legacy(timestamp: Self.timestampA, usage: usage, total: usage)
        let ledger = Self.record(id: "owned", timestamp: Self.timestampB, usage: usage, total: usage)
        let legacyFile = try env.writeCodexSessionFile(
            day: start,
            filename: ledgerFirst ? "z-page.jsonl" : "a-page.jsonl",
            contents: env.jsonl(Self.header() + [legacy]))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"),
            calendar: calendar)
        options.refreshMinIntervalSeconds = 0
        options.useCodexCatchUpWorkingSet = true
        func fetch() -> CostUsageDailyReport {
            var report = CostUsageScanner.loadDailyReport(
                provider: .codex, since: start, until: end, now: end, options: options)
            for _ in 0..<60 {
                let manifest = CostUsageStore(cacheRoot: env.cacheRoot)
                    .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
                if manifest.codexScanCatchUpPending != true { break }
                report = CostUsageScanner.loadDailyReport(
                    provider: .codex, since: start, until: end, now: end, options: options)
            }
            return report
        }
        _ = fetch()
        let legacyManifest = CostUsageStore(cacheRoot: env.cacheRoot)
            .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
        #expect(legacyManifest.files[legacyFile.path]?.codexTypedResponseIdentity == false)
        var cache = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        var file = try #require(cache.files[legacyFile.path])
        var savedPrice = try #require(file.codexRows?.first)
        savedPrice.pricingModel = "gpt-5.4"
        savedPrice.pricingMode = pricing == "priority" ? "priority" : "standard"
        if pricing == "known" { savedPrice.knownCostNanos = 123_000_000 }
        if pricing == "unpriced" { savedPrice.unpricedTokens = 110 }
        file.codexRows = [savedPrice]
        cache.files[legacyFile.path] = file
        #expect(!CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache, calendar: calendar)
            .catchUpRequired)
        // The paired page proves which legacy observation mirrors this response across midnight.
        _ = try env.writeCodexSessionFile(
            day: start,
            filename: ledgerFirst ? "a-page.jsonl" : "z-page.jsonl",
            contents: env.jsonl(Self.header() + (ledgerFirst ? [ledger, legacy] : [legacy, ledger])))
        let report = fetch()
        #expect(report.summary?.totalTokens == 110)
        #expect(report.data.filter { ($0.totalTokens ?? 0) > 0 }.map(\.date) == ["2026-08-30"])
        let reopened = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        let rows = reopened.files.values.flatMap { $0.codexRows ?? [] }
        #expect(rows.compactMap(\.responseID) == ["owned"])
        let row = try #require(rows.first)
        #expect(row.knownCostNanos == savedPrice.knownCostNanos)
        #expect(row.unpricedTokens == savedPrice.unpricedTokens)
        #expect(row.pricingModel == savedPrice.pricingModel)
        #expect(row.pricingMode == savedPrice.pricingMode)
        #expect(fetch().data == report.data)
    }

    @Test(arguments: [false, true])
    func `adjacent equal usage without shared timestamp or totals remains distinct`(ledgerFirst: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let usage = [100, 20, 10, 4]
        let total = [200, 40, 20, 8]
        let first = ledgerFirst
            ? Self.record(id: "first", usage: usage, total: usage)
            : Self.legacy(timestamp: Self.timestampA, usage: usage, total: usage)
        let second = ledgerFirst
            ? Self.legacy(timestamp: Self.timestampB, usage: usage, total: total)
            : Self.record(id: "second", timestamp: Self.timestampB, usage: usage, total: total)
        let result = try Self.parse(Self.header() + [first, second], env: env)
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 220)
        #expect(result.rows.map(\.day) == ["2026-08-29", "2026-08-30"])
    }

    @Test(arguments: [false, true], [false, true])
    func `partial legacy observations mirror a typed response once`(legacyFirst: Bool, lastOnly: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let legacy = try Self.partialLegacy(lastOnly: lastOnly)
        let ledger = Self.record(id: "partial", usage: [100, 20, 10, 4], total: [100, 20, 10, 4])
        let result = try Self.parse(Self.header() + (legacyFirst ? [legacy, ledger] : [ledger, legacy]), env: env)
        #expect(result.rows.reduce(0) { $0 + $1.input + $1.output } == 110)
        #expect(result.rows.compactMap(\.responseID) == ["partial"])
    }

    @Test(arguments: [false, true])
    func `partial legacy observations reconcile across separate pages`(lastOnly: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        let pages = try [
            [Self.partialLegacy(lastOnly: lastOnly)],
            [Self.record(id: "partial", usage: [100, 20, 10, 4], total: [100, 20, 10, 4])],
        ]
        for (index, page) in pages.enumerated() {
            _ = try env.writeCodexSessionFile(
                day: day, filename: "partial-\(index).jsonl", contents: env.jsonl(Self.header() + page))
        }
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"))
        let report = CostUsageScanner.loadDailyReport(
            provider: .codex, since: day, until: day, now: day, options: options)
        #expect(report.summary?.totalTokens == 110)
        let cache = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: .current)
        #expect(cache.files.values.flatMap { $0.codexRows ?? [] }.compactMap(\.responseID) == ["partial"])
    }
}

extension CostUsageCodexRequestLedgerTests {
    @Test
    func `compact request progress saves preserve committed details and explicit empty generations still clear`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let parsed = try Self.parse(
            Self.header() + [Self.record(id: "saved-response", usage: [100, 20, 10, 4], total: [100, 20, 10, 4])],
            env: env)
        var row = try #require(parsed.rows.first)
        row.knownCostNanos = 123_000_000
        row.pricingMode = "priority"
        let path = env.root.appendingPathComponent("synthetic.jsonl").path
        let usage = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: parsed.parsedBytes,
            days: parsed.days,
            parsedBytes: parsed.parsedBytes,
            lastCountedTotals: parsed.lastCountedTotals,
            sessionId: parsed.sessionId,
            codexRows: [row],
            codexTokenSnapshots: parsed.tokenSnapshots,
            codexScanComplete: true,
            codexRequestLedgerState: parsed.requestLedgerState)
        var seed = CostUsageCache()
        seed.scanSinceKey = "2026-08-29"
        seed.scanUntilKey = "2026-08-30"
        seed.days = usage.days
        seed.files[path] = usage
        #expect(!CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: seed, calendar: calendar)
            .catchUpRequired)
        let store = CostUsageStore(cacheRoot: env.cacheRoot)
        let baseline = try #require(store.syncLoadCodexCache(calendar: calendar).files[path])
        var compact = store.syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
        #expect(compact.files[path]?.codexRows == nil)
        #expect(compact.files[path]?.codexTokenSnapshots == nil)
        #expect(compact.files[path]?.codexRequestLedgerState == nil)
        #expect(compact.files[path]?.codexTypedResponseIdentity == true)
        let progress = CostUsageCodexRequestReconciliation(
            size: usage.size,
            mtimeUnixMs: usage.mtimeUnixMs,
            parserRevision: CostUsageFileUsage.currentCodexParserRevision,
            sessionID: parsed.sessionId,
            pendingPaths: ["/synthetic/sibling.jsonl"])
        compact.files[path]?.codexRequestReconciliation = progress
        compact.files[path]?.codexInventoryValidationGeneration = "synthetic-validation"
        let window = (sinceKey: "2026-08-29", untilKey: "2026-08-30")
        #expect(!store.syncSaveCodexCatchUpCache(
            compact,
            calendar: calendar,
            requestedScanWindow: window,
            hydratedPaths: [path]).catchUpRequired)
        let reopenedStore = CostUsageStore(cacheRoot: env.cacheRoot)
        var reopened = reopenedStore.syncLoadCodexCache(calendar: calendar)
        let preserved = try #require(reopened.files[path])
        #expect(preserved.codexRows == baseline.codexRows)
        #expect(preserved.codexTokenSnapshots == baseline.codexTokenSnapshots)
        #expect(preserved.codexRequestLedgerState == baseline.codexRequestLedgerState)
        #expect(preserved.lastCountedTotals == baseline.lastCountedTotals)
        #expect(preserved.days == baseline.days)
        #expect(preserved.codexRequestReconciliation == progress)
        #expect(preserved.codexInventoryValidationGeneration == "synthetic-validation")
        #expect(preserved.codexTypedResponseIdentity == true)
        let empty = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: usage.mtimeUnixMs,
            size: usage.size,
            days: [:],
            parsedBytes: usage.parsedBytes,
            sessionId: parsed.sessionId,
            codexRows: [],
            codexTokenSnapshots: [],
            codexScanComplete: true,
            codexReplacementScanPending: false)
        reopened.files[path] = empty
        reopened.days = [:]
        #expect(!reopenedStore.syncSaveCodexCatchUpCache(
            reopened,
            calendar: calendar,
            requestedScanWindow: window,
            hydratedPaths: [path]).catchUpRequired)
        let cleared = try #require(CostUsageStore(cacheRoot: env.cacheRoot)
            .syncLoadCodexCache(calendar: calendar).files[path])
        #expect(cleared.codexRows?.isEmpty == true)
        #expect(cleared.codexTokenSnapshots?.isEmpty == true)
        #expect(cleared.codexRequestLedgerState == nil)
        #expect(cleared.codexTypedResponseIdentity == false)
        #expect(cleared.days.isEmpty)
    }

    @Test(arguments: [false, true], [false, true])
    func `session alias cleanup preserves typed pages and still removes proven legacy duplicates`(
        currentTyped: Bool,
        aliasTyped: Bool)
    {
        let session = CostUsageCodexSessionMetadata(
            sessionId: "synthetic-session",
            concreteSessionId: "synthetic-session",
            forkedFromId: nil,
            cwd: nil,
            title: nil,
            startedAtUnixMs: nil,
            latestActivityUnixMs: nil)
        var alias = CostUsageFileUsage(mtimeUnixMs: 1, size: 1, days: [:], codexSession: session)
        alias.codexHasTypedResponseIdentity = aliasTyped
        var contradictory = alias
        contradictory.codexHasTypedResponseIdentity = false
        contradictory.codexRequestLedgerState = .init()
        #expect(contradictory.codexTypedResponseIdentity == false)
        contradictory.codexRows = [CostUsageScanner.CodexUsageRow(
            day: "2026-08-29",
            model: "gpt-5",
            input: 1,
            cached: 0,
            output: 1,
            responseID: "synthetic-response")]
        #expect(contradictory.codexTypedResponseIdentity == true)
        contradictory.codexRequestLedgerState = nil
        #expect(contradictory.codexTypedResponseIdentity == true)
        contradictory.codexHasTypedResponseIdentity = nil
        contradictory.codexRequestLedgerState = .init()
        #expect(contradictory.codexTypedResponseIdentity == true)
        contradictory.codexRows = nil
        contradictory.codexRequestLedgerState = nil
        contradictory.codexHasTypedResponseIdentity = nil
        #expect(contradictory.codexTypedResponseIdentity == nil)
        contradictory.codexHasTypedResponseIdentity = false
        #expect(contradictory.codexTypedResponseIdentity == false)
        var cache = CostUsageCache()
        cache.files["/synthetic/older-page.jsonl"] = alias
        #expect(!CostUsageScanner.dropStaleCodexSessionAliases(
            currentSession: session,
            currentHasTypedResponseIdentity: currentTyped,
            currentPath: "/synthetic/current-page.jsonl",
            currentMtimeUnixMs: 2,
            currentSize: 2,
            cache: &cache))
        #expect((cache.files["/synthetic/older-page.jsonl"] != nil) == (currentTyped || aliasTyped))

        // Missing identity metadata is not proof that an older page contains only legacy rows.
        alias.codexHasTypedResponseIdentity = nil
        cache.files["/synthetic/unknown-page.jsonl"] = alias
        #expect(!CostUsageScanner.dropStaleCodexSessionAliases(
            currentSession: session,
            currentHasTypedResponseIdentity: false,
            currentPath: "/synthetic/current-page.jsonl",
            currentMtimeUnixMs: 2,
            currentSize: 2,
            cache: &cache))
        #expect(cache.files["/synthetic/unknown-page.jsonl"] != nil)
        for peerIdentity in [nil, true] as [Bool?] {
            for currentMtime in [Int64(0), Int64(2)] {
                var legacy = alias
                legacy.codexHasTypedResponseIdentity = false
                var peer = alias
                peer.codexHasTypedResponseIdentity = peerIdentity
                cache.files = [
                    "/synthetic/current-page.jsonl": legacy,
                    "/synthetic/legacy-peer.jsonl": legacy,
                    "/synthetic/mixed-peer.jsonl": peer,
                ]
                #expect(!CostUsageScanner.dropStaleCodexSessionAliases(
                    currentSession: session,
                    currentHasTypedResponseIdentity: false,
                    currentPath: "/synthetic/current-page.jsonl",
                    currentMtimeUnixMs: currentMtime,
                    currentSize: 2,
                    cache: &cache))
                #expect(cache.files.count == 3)
            }
        }
    }

    @Test(arguments: [false, true], [false, true])
    func `working set deduplicates settled typed siblings in bounded cohorts across reopen`(
        newestFirst: Bool, earlierReplay: Bool) throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let start = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        let end = try #require(ISO8601DateFormatter().date(from: Self.timestampC))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"),
            calendar: calendar)
        options.refreshMinIntervalSeconds = 0
        options.useCodexCatchUpWorkingSet = true
        options.preferNewestCodexSessionsFirst = newestFirst
        func fetch() -> CostUsageDailyReport {
            CostUsageScanner.loadDailyReport(provider: .codex, since: start, until: end, now: end, options: options)
        }
        func settle() -> CostUsageDailyReport {
            var report = fetch()
            for _ in 0..<100 {
                let manifest = CostUsageStore(cacheRoot: env.cacheRoot)
                    .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
                if manifest.codexScanCatchUpPending != true { break }
                report = fetch()
            }
            return report
        }
        for index in 0..<7 {
            _ = try env.writeCodexSessionFile(
                day: start,
                filename: "settled-\(index).jsonl",
                contents: env.jsonl(Self.header() + [Self.record(
                    id: "response-\(index)",
                    timestamp: earlierReplay ? Self.timestampB : Self.timestampA,
                    usage: [100, 20, 10, 4],
                    total: [100, 20, 10, 4])]))
        }
        let settledCopy = (0..<7).map { Self.record(
            id: "response-\($0)",
            timestamp: earlierReplay ? Self.timestampB : Self.timestampA,
            usage: [100, 20, 10, 4],
            total: [100, 20, 10, 4]) }
        let settledCopyURL = try env.writeCodexSessionFile(
            day: start, filename: "settled-7-copy.jsonl", contents: env.jsonl(Self.header() + settledCopy))
        #expect(settle().summary?.totalTokens == 770)
        let replay = (0..<7).map { Self.record(
            id: "response-\($0)",
            timestamp: earlierReplay ? Self.timestampA : Self.timestampB,
            usage: [100, 20, 10, 4],
            total: [100, 20, 10, 4]) }
        let page = try env.writeCodexSessionFile(
            day: start, filename: "z-replayed-page.jsonl", contents: env.jsonl(Self.header() + replay))
        let recorder = CostUsageScanner.CodexScanWorkRecorder()
        options.codexScanWorkRecorderForTesting = recorder
        _ = fetch()
        #expect(recorder.snapshot().codexHydratedFiles <= CostUsageScanner.codexCatchUpHydrationPathLimit)
        let partial = CostUsageStore(cacheRoot: env.cacheRoot)
            .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
        #expect(partial.codexScanCatchUpPending == true)
        #expect(partial.files[page.path]?.codexRequestReconciliation?.pendingPaths.isEmpty == false)
        options.codexScanWorkRecorderForTesting = nil
        let reconciled = settle()
        #expect(reconciled.summary?.totalTokens == 770)
        #expect(reconciled.data.filter { ($0.totalTokens ?? 0) > 0 }.map(\.date) == ["2026-08-29"])
        let reopened = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        #expect(reopened.codexScanCatchUpPending != true)
        #expect(reopened.files.values.flatMap { $0.codexRows ?? [] }.compactMap(\.responseID).count == 7)
        #expect(reopened.files.values.contains {
            $0.codexRows?.isEmpty == true && $0.codexRequestLedgerState?.responseIDs.isEmpty == false
        })
        let handle = try FileHandle(forWritingTo: page)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(env.jsonl([Self.record(
            id: "new-response",
            timestamp: Self.timestampC,
            usage: [60, 20, 6, 3],
            total: [760, 160, 76, 31])]).utf8))
        try handle.close()
        #expect(settle().summary?.totalTokens == 836)
        // The old owner pages are now rowless. Visit them before the active owner in later
        // hydration cohorts and prove its carried aliases still eliminate this legacy copy.
        _ = try env.writeCodexSessionFile(
            day: start, filename: "a-legacy-copy.jsonl", contents: env.jsonl(Self.header() + [Self.legacy(
                timestamp: Self.timestampA, usage: [100, 20, 10, 4], total: [100, 20, 10, 4])]))
        #expect(settle().summary?.totalTokens == 836)
        #expect(fetch().summary?.totalTokens == 836)

        var pricedCache = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        var owner = try #require(pricedCache.files[page.path])
        owner.codexRows = owner.codexRows?.map { row in
            var row = row
            if row.responseID == "response-0" {
                row.knownCostNanos = 123_000_000
                row.pricingMode = "priority"
            }
            return row
        }
        pricedCache.files[page.path] = owner
        #expect(!CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: pricedCache).catchUpRequired)
        _ = settle()
        try FileManager.default.removeItem(at: page)
        try FileManager.default.removeItem(at: settledCopyURL)
        _ = fetch()
        let queuedRecovery = CostUsageStore(cacheRoot: env.cacheRoot)
            .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
        #expect(queuedRecovery.codexScanCatchUpPending == true)
        #expect(queuedRecovery.files[page.path] != nil)
        let recovered = settle()
        #expect(recovered.summary?.totalTokens == 770)
        #expect(recovered.data.filter { ($0.totalTokens ?? 0) > 0 }.map(\.date) == ["2026-08-29"])
        let recoveredCache = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        #expect(recoveredCache.files[page.path] == nil)
        #expect(recoveredCache.codexScanCatchUpPending != true)
        #expect(recoveredCache.codexHistoryHydrationRetries?.isEmpty != false)
        let recoveredPrice = try #require(recoveredCache.files.values.flatMap { $0.codexRows ?? [] }
            .first { $0.responseID == "response-0" })
        #expect(recoveredPrice.knownCostNanos == 123_000_000)
        #expect(recoveredPrice.pricingMode == "priority")
        #expect(fetch().summary == recovered.summary)
    }

    @Test(arguments: [false, true], [1, 5])
    func `deleting every typed owner drains recovery without retaining ghost quota`(
        targetsDisappearAfterQueue: Bool,
        ownerCount: Int) throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"),
            calendar: calendar)
        options.refreshMinIntervalSeconds = 0
        options.useCodexCatchUpWorkingSet = true
        options.preferNewestCodexSessionsFirst = false
        func fetch() -> CostUsageDailyReport {
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            options.codexScanWorkRecorderForTesting = recorder
            let report = CostUsageScanner.loadDailyReport(
                provider: .codex, since: day, until: day, now: day, options: options)
            #expect(recorder.snapshot().codexHydratedFiles <= CostUsageScanner.codexCatchUpHydrationPathLimit)
            options.codexScanWorkRecorderForTesting = nil
            return report
        }
        func settle() -> CostUsageDailyReport {
            var report = fetch()
            for _ in 0..<150 {
                let manifest = CostUsageStore(cacheRoot: env.cacheRoot)
                    .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
                if manifest.codexScanCatchUpPending != true { break }
                report = fetch()
            }
            return report
        }
        var files: [URL] = []
        var mirrors: [[String: Any]] = []
        for index in 0..<ownerCount {
            let total = [(index + 1) * 100, (index + 1) * 20, (index + 1) * 10, (index + 1) * 4]
            let record = Self.record(
                id: "removed-response-\(index)", usage: [100, 20, 10, 4], total: total)
            let mirror = Self.legacy(timestamp: Self.timestampB, usage: [100, 20, 10, 4], total: total)
            mirrors.append(mirror)
            try files.append(env.writeCodexSessionFile(
                day: day,
                filename: "removed-owner-\(index).jsonl",
                contents: env.jsonl(Self.header() + [record, mirror])))
        }
        #expect(settle().summary?.totalTokens == ownerCount * 110)
        let compact = CostUsageStore(cacheRoot: env.cacheRoot)
            .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
        for file in files {
            let owner = try #require(compact.files[file.path])
            #expect(owner.codexTypedResponseIdentity == true)
            #expect(owner.codexRequestLedgerState == nil)
            #expect(owner.codexRows == nil)
        }
        var queuedSource: URL?
        if targetsDisappearAfterQueue {
            queuedSource = try env.writeCodexSessionFile(
                day: day,
                filename: "z-disappearing-source.jsonl",
                contents: env.jsonl(Self.header() + mirrors))
            #expect(settle().summary?.totalTokens == ownerCount * 110)
        }
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
        if let queuedSource {
            _ = fetch()
            let queued = CostUsageStore(cacheRoot: env.cacheRoot)
                .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
            #expect(queued.codexScanCatchUpPending == true)
            #expect(queued.codexHistoryHydrationRetries?[queuedSource.path]?.requestOwnerPaths?.isEmpty == false)
            try FileManager.default.removeItem(at: queuedSource)
        }
        #expect((settle().summary?.totalTokens ?? 0) == 0)
        let cache = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        #expect(cache.files.isEmpty)
        #expect(cache.codexScanCatchUpPending != true)
        #expect(cache.codexHistoryHydrationRetries?.isEmpty != false)
    }

    @Test(arguments: [false, true], [false, true])
    func `missing typed owners transfer canonical accounting to a sole legacy survivor`(
        forkParent: Bool,
        appendBeforeReplay: Bool) throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let start = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        let end = try #require(ISO8601DateFormatter().date(from: Self.timestampC))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"),
            calendar: calendar)
        options.refreshMinIntervalSeconds = 0
        options.useCodexCatchUpWorkingSet = true
        options.preferNewestCodexSessionsFirst = false
        func fetch() -> CostUsageDailyReport {
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            options.codexScanWorkRecorderForTesting = recorder
            let report = CostUsageScanner.loadDailyReport(
                provider: .codex, since: start, until: end, now: end, options: options)
            #expect(recorder.snapshot().codexHydratedFiles <= CostUsageScanner.codexCatchUpHydrationPathLimit)
            options.codexScanWorkRecorderForTesting = nil
            return report
        }
        func settle() -> CostUsageDailyReport {
            var report = fetch()
            for _ in 0..<150 {
                let manifest = CostUsageStore(cacheRoot: env.cacheRoot)
                    .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
                if manifest.codexScanCatchUpPending != true { break }
                report = fetch()
            }
            return report
        }
        var owners: [URL] = []
        var mirrors: [[String: Any]] = []
        for index in 0..<5 {
            let total = [(index + 1) * 100, (index + 1) * 20, (index + 1) * 10, (index + 1) * 4]
            let mirror = Self.legacy(timestamp: Self.timestampB, usage: [100, 20, 10, 4], total: total)
            mirrors.append(mirror)
            try owners.append(env.writeCodexSessionFile(
                day: start,
                filename: "a-priced-owner-\(index).jsonl",
                contents: env.jsonl(Self.header() + [Self.record(
                    id: "priced-response-\(index)", usage: [100, 20, 10, 4], total: total), mirror])))
        }
        var survivorHeader = Self.header()
        if forkParent {
            var metadata = try #require(survivorHeader[0]["payload"] as? [String: Any])
            metadata["forked_from_id"] = "dependency-thread"
            metadata["timestamp"] = Self.timestampA
            survivorHeader[0]["payload"] = metadata
            var parentHeader = Self.header()
            parentHeader[0]["payload"] = ["id": "dependency-thread"]
            _ = try env.writeCodexSessionFile(
                day: start,
                filename: "dependency-parent.jsonl",
                contents: env.jsonl(parentHeader + [Self.legacy(
                    timestamp: Self.timestampA, usage: [0, 0, 0, 0], total: [0, 0, 0, 0])]))
        }
        let survivor = try env.writeCodexSessionFile(
            day: start, filename: "z-legacy-survivor.jsonl", contents: env.jsonl(survivorHeader + mirrors))
        #expect(settle().summary?.totalTokens == 550)
        var cache = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        for (index, path) in owners.enumerated() {
            var owner = try #require(cache.files[path.path])
            owner.codexRows = owner.codexRows?.map { row in
                var row = row
                row.knownCostNanos = Int64(100_000_000 + index * 1_000_000)
                row.pricingMode = "priority"
                return row
            }
            cache.files[path.path] = owner
        }
        #expect(!CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache).catchUpRequired)
        _ = settle()
        for owner in owners {
            try FileManager.default.removeItem(at: owner)
        }
        if appendBeforeReplay {
            let handle = try FileHandle(forWritingTo: survivor)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(env.jsonl([Self.record(
                id: "unrelated-appended-request",
                timestamp: Self.timestampC,
                usage: [60, 20, 6, 3],
                total: [560, 120, 56, 23])]).utf8))
            try handle.close()
        }
        _ = fetch()
        let pending = CostUsageStore(cacheRoot: env.cacheRoot)
            .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
        #expect(pending.codexScanCatchUpPending == true)
        let recovered = settle()
        #expect(recovered.summary?.totalTokens == 550 + (appendBeforeReplay ? 66 : 0))
        let canonicalDay = try #require(recovered.data.first { $0.date == "2026-08-29" })
        #expect(canonicalDay.totalTokens == 550)
        #expect(abs((canonicalDay.costUSD ?? -1) - 0.51) < 0.000001)
        let reopened = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        #expect(owners.allSatisfy { reopened.files[$0.path] == nil })
        #expect(reopened.codexHistoryHydrationRetries?.isEmpty != false)
        #expect(reopened.codexScanCatchUpPending != true)
        let survivorRows = try #require(reopened.files[survivor.path]?.codexRows)
        #expect(survivorRows.contains { $0.responseID == "unrelated-appended-request" } == appendBeforeReplay)
        let rows = survivorRows.filter { $0.responseID?.hasPrefix("priced-response-") == true }.sorted {
            ($0.responseID ?? "") < ($1.responseID ?? "")
        }
        #expect(rows.compactMap(\.responseID) == (0..<5).map { "priced-response-\($0)" })
        let expectedKnownCosts: [Int64] = [100_000_000, 101_000_000, 102_000_000, 103_000_000, 104_000_000]
        #expect(rows.compactMap(\.knownCostNanos) == expectedKnownCosts)
        #expect(rows.allSatisfy { $0.pricingMode == "priority" })
        if !appendBeforeReplay {
            #expect(abs((recovered.summary?.totalCostUSD ?? -1) - 0.51) < 0.000001)
        }
        #expect(fetch().summary == recovered.summary)
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
        #expect(settle().summary?.totalTokens == 616 + (appendBeforeReplay ? 66 : 0))
    }

    @Test
    func `disappearing recovery target preserves its own canonical request for a surviving sibling`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let start = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        let end = try #require(ISO8601DateFormatter().date(from: Self.timestampC))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"),
            calendar: calendar)
        options.refreshMinIntervalSeconds = 0
        options.useCodexCatchUpWorkingSet = true
        options.preferNewestCodexSessionsFirst = false
        func fetch() -> CostUsageDailyReport {
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            options.codexScanWorkRecorderForTesting = recorder
            let report = CostUsageScanner.loadDailyReport(
                provider: .codex, since: start, until: end, now: end, options: options)
            #expect(recorder.snapshot().codexHydratedFiles <= CostUsageScanner.codexCatchUpHydrationPathLimit)
            options.codexScanWorkRecorderForTesting = nil
            return report
        }
        func settle() -> CostUsageDailyReport {
            var report = fetch()
            for _ in 0..<100 {
                let manifest = CostUsageStore(cacheRoot: env.cacheRoot)
                    .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
                if manifest.codexScanCatchUpPending != true { break }
                report = fetch()
            }
            return report
        }
        let firstMirror = Self.legacy(timestamp: Self.timestampB, usage: [100, 20, 10, 4], total: [100, 20, 10, 4])
        let secondMirror = Self.legacy(timestamp: Self.timestampB, usage: [100, 20, 10, 4], total: [200, 40, 20, 8])
        let first = try env.writeCodexSessionFile(
            day: start,
            filename: "a-missing-owner.jsonl",
            contents: env.jsonl(Self.header() + [Self.record(
                id: "first-request", usage: [100, 20, 10, 4], total: [100, 20, 10, 4]), firstMirror]))
        let second = try env.writeCodexSessionFile(
            day: start,
            filename: "b-disappearing-target.jsonl",
            contents: env.jsonl(Self.header() + [Self.record(
                id: "second-request", usage: [100, 20, 10, 4], total: [200, 40, 20, 8]), secondMirror, firstMirror]))
        let survivor = try env.writeCodexSessionFile(
            day: start,
            filename: "c-surviving-mirror.jsonl",
            contents: env.jsonl(Self.header() + [secondMirror]))
        #expect(settle().summary?.totalTokens == 220)
        var cache = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        var secondUsage = try #require(cache.files[second.path])
        #expect(secondUsage.codexRows?.contains { $0.responseID == "second-request" } == true)
        secondUsage.codexRows = secondUsage.codexRows?.map { row in
            var row = row
            row.knownCostNanos = 123_000_000
            row.pricingMode = "priority"
            return row
        }
        cache.files[second.path] = secondUsage
        #expect(!CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache).catchUpRequired)
        _ = settle()
        try FileManager.default.removeItem(at: first)
        _ = fetch()
        let queued = CostUsageStore(cacheRoot: env.cacheRoot)
            .syncLoadCodexCache(calendar: calendar, hydratingPaths: [])
        #expect(queued.codexHistoryHydrationRetries?[second.path]?.requestOwnerPaths?.isEmpty == false)
        #expect(queued.codexScanCatchUpPending == true)
        try FileManager.default.removeItem(at: second)
        let recovered = settle()
        #expect(recovered.summary?.totalTokens == 110)
        #expect(abs((recovered.summary?.totalCostUSD ?? 0) - 0.123) < 0.000_001)
        #expect(recovered.data.filter { ($0.totalTokens ?? 0) > 0 }.map(\.date) == ["2026-08-29"])
        let reopened = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: calendar)
        let row = try #require(reopened.files[survivor.path]?.codexRows?.first)
        #expect(row.responseID == "second-request")
        #expect(row.knownCostNanos == 123_000_000)
        #expect(row.pricingMode == "priority")
        #expect(reopened.files[first.path] == nil)
        #expect(reopened.files[second.path] == nil)
        #expect(reopened.codexScanCatchUpPending != true)
        #expect(reopened.codexHistoryHydrationRetries?.isEmpty != false)
        #expect(fetch().summary == recovered.summary)
    }

    @Test
    func `request owner retirement preserves a baseline protected by another history retry`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let ownerPath = env.root.appendingPathComponent("missing-owner.jsonl").path
        let candidatePath = env.root.appendingPathComponent("missing-candidate.jsonl").path
        let forkPath = env.root.appendingPathComponent("unresolved-fork.jsonl").path
        let owner = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1, size: 1, days: ["2026-08-29": ["gpt-5": [100, 20, 10]]], parsedBytes: 1)
        var cache = CostUsageCache()
        cache.files[ownerPath] = owner
        cache.files[candidatePath] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1, size: 1, days: [:], parsedBytes: 1)
        let forkRetry = CodexHistoryHydrationRetry(retainedPaths: [ownerPath, forkPath], forceFullRescan: true)
        var retries = [
            candidatePath: CodexHistoryHydrationRetry(
                retainedPaths: [ownerPath, candidatePath], forceFullRescan: false, requestOwnerPaths: [ownerPath]),
            forkPath: forkRetry,
        ]
        let retired = CostUsageScanner.completeCodexRequestOwnerRetries(
            processedPaths: [candidatePath], retries: &retries, cache: &cache)
        #expect(retired == [candidatePath])
        #expect(cache.files[candidatePath] == nil)
        #expect(cache.files[ownerPath] == owner)
        #expect(retries[candidatePath] == nil)
        #expect(retries[forkPath] == forkRetry)
    }

    private static func partialLegacy(lastOnly: Bool) throws -> [String: Any] {
        var row = Self.legacy(timestamp: Self.timestampA, usage: [100, 20, 10, 4], total: [100, 20, 10, 4])
        var payload = try #require(row["payload"] as? [String: Any])
        var info = try #require(payload["info"] as? [String: Any])
        info.removeValue(forKey: lastOnly ? "total_token_usage" : "last_token_usage")
        payload["info"] = info
        row["payload"] = payload
        return row
    }

    private static func parse(
        _ lines: [[String: Any]],
        env: CostUsageTestEnvironment,
        spacedJSON: Bool = false,
        transform: (String) -> String = { $0 }) throws -> CostUsageScanner.CodexParseResult
    {
        let file = env.root.appendingPathComponent("synthetic.jsonl")
        let content = try transform(env.jsonl(lines))
        try (spacedJSON ? content.replacingOccurrences(of: "\":", with: "\": ") : content)
            .write(to: file, atomically: false, encoding: .utf8)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let start = try #require(ISO8601DateFormatter().date(from: Self.timestampA))
        let end = try #require(ISO8601DateFormatter().date(from: Self.timestampC))
        return CostUsageScanner.parseCodexFile(
            fileURL: file, range: .init(since: start, until: end, calendar: calendar))
    }

    private static func header() -> [[String: Any]] {
        [
            ["type": "session_meta", "timestamp": self.timestampA, "payload": ["id": "synthetic-thread"]],
            [
                "type": "turn_context",
                "timestamp": self.timestampA,
                "payload": ["turn_id": "synthetic-turn", "model": "gpt-5"],
            ],
        ]
    }

    private static func tokens(_ values: [Int]) -> [String: Int] {
        [
            "input_tokens": values[0],
            "cached_input_tokens": values[1],
            "output_tokens": values[2],
            "reasoning_output_tokens": values[3],
        ]
    }

    private static func record(
        id: String,
        owner: String = "synthetic-thread",
        timestamp: String = timestampA,
        usage: [Int],
        total: [Int],
        turnTotal: [Int]? = nil) -> [String: Any]
    {
        ["type": "token_usage_record", "timestamp": timestamp, "payload": [
            "thread_id": owner, "session_id": owner, "turn_id": "synthetic-turn", "response_id": id,
            "usage": self.tokens(usage), "thread_token_usage": self.tokens(total),
            "turn_token_usage": self.tokens(turnTotal ?? total),
        ]]
    }

    private static func legacy(timestamp: String, usage: [Int], total: [Int]) -> [String: Any] {
        ["type": "event_msg", "timestamp": timestamp, "payload": [
            "type": "token_count", "turn_id": "synthetic-turn", "info": [
                "last_token_usage": self.tokens(usage), "total_token_usage": self.tokens(total),
            ],
        ]]
    }
}
