import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageUltrafastPricingTests {
    @Test
    func `published Ultrafast rates use request time including long context`() throws {
        let before = Date(timeIntervalSince1970: 1_803_887_999)
        let after = before.addingTimeInterval(1)
        for model in ["gpt-6.2-astra", "gpt-6.2-sol"] {
            let standard = try #require(Self.cost(model: model, mode: "standard", date: before))
            #expect(try abs(#require(Self.cost(model: model, mode: "ultrafast", date: before)) - standard * 3) < 1e-9)
            #expect(try abs(#require(Self.cost(model: model, mode: "ultrafast", date: after)) - standard * 6) < 1e-9)
            #expect(try abs(#require(Self.cost(model: model, mode: "priority", date: before)) - standard * 2) < 1e-9)
            #expect(Self.cost(model: model, mode: "ultrafast", date: nil) == nil)
        }
        for model in ["gpt-6-astra", "gpt-6.1-sol"] {
            let standard = try #require(Self.cost(model: model, mode: "standard", date: before))
            #expect(try abs(#require(Self.cost(model: model, mode: "ultrafast", date: before)) - standard * 6) < 1e-9)
        }
        #expect(Self.cost(model: "gpt-5.4", mode: "ultrafast", date: before) == nil)
        // 300K input exceeds the 272K threshold: uncached and cached rates double, output is 1.5x.
        #expect(try abs(#require(Self.cost(model: "gpt-6.2-sol", mode: "ultrafast", date: before)) - 3.48) < 1e-9)
    }

    @Test
    func `native Ultrafast pricing wins over older turn level Priority evidence`() throws {
        let row = CostUsageScanner.CodexUsageRow(
            day: "2026-11-20",
            model: "gpt-6.1-sol",
            turnID: "turn",
            eventIndex: 0,
            input: 1000,
            cached: 800,
            output: 100,
            pricingMode: "ultrafast")
        let trace: [String: CostUsageScanner.CodexPriorityTurnMetadata] = [
            "turn": .init(threadID: nil, turnID: "turn", model: "gpt-6-astra", timestamp: nil),
        ]
        let normalized = try #require(CostUsageScanner.codexRowsWithPricingMetadata([row], priorityTurns: trace).first)
        #expect(normalized.pricingMode == "ultrafast")
        #expect(normalized.pricingModel == "gpt-6.1-sol")
        let cost = CostUsageScanner.codexResolvedCostUSD(
            for: normalized, priorityTurns: trace, modelsDevCatalog: nil, modelsDevCacheRoot: nil)
        #expect(try abs(#require(cost) - 0.00888) < 1e-12)
    }

    @Test
    func `native Ultrafast checkpoint keeps legacy booleans readable`() throws {
        let decoder = JSONDecoder()
        typealias Tier = CostUsageScanner.CodexNativePricingTier
        #expect(try decoder.decode(Tier.self, from: Data("true".utf8)) == .priority)
        #expect(try decoder.decode(Tier.self, from: Data("false".utf8)) == .standard)
        let bytes = try JSONEncoder().encode(Tier.ultrafast)
        #expect(try decoder.decode(Tier.self, from: bytes) == .ultrafast)
    }

    @Test
    func `Ultrafast requests keep their tier and price after SQLite reopening`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let before = Date(timeIntervalSince1970: 1_803_887_999)
        let after = before.addingTimeInterval(1)
        let prefix = [
            Self.record("session_meta", at: before, payload: ["id": "synthetic-ultrafast"]),
            Self.record("event_msg", at: before, payload: ["type": "thread_settings_applied", "thread_settings": [
                "model": "gpt-6.2-sol", "service_tier": "ultrafast",
            ]]),
        ]
        let directory = env.codexSessionsRoot.appendingPathComponent("2027/03/01", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("ultrafast.jsonl")
        try env.jsonl(prefix).write(to: file, atomically: true, encoding: .utf8)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"),
            calendar: calendar)
        options.refreshMinIntervalSeconds = 0
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: before,
            until: after,
            now: after,
            options: options)
        let store = CostUsageStore(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        await store.closeConnectionForTesting()
        let checkpoint = store.syncLoadCodexCache(calendar: calendar)
        #expect(checkpoint.files[file.path]?.codexRequestLedgerState?.threadUltrafast == true)
        let suffix = [
            Self.record("event_msg", at: before, payload: ["type": "task_started", "turn_id": "ultrafast-turn"]),
            Self.record("turn_context", at: before, payload: ["model": "gpt-6.2-sol", "turn_id": "ultrafast-turn"]),
            Self.request(at: before, response: "promotion"),
            Self.request(at: after, response: "regular"),
            Self.record("event_msg", at: after, payload: ["type": "thread_settings_applied", "thread_settings": [
                "service_tier": "default",
            ]]),
            Self.record("turn_context", at: after, payload: ["model": "gpt-6.2-sol", "turn_id": "ultrafast-turn"]),
            Self.request(at: after, response: "standard"),
        ]
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(env.jsonl(suffix).utf8))
        try handle.close()
        let report = CostUsageScanner.loadDailyReport(
            provider: .codex, since: before, until: after, now: after.addingTimeInterval(1), options: options)
        #expect(report.summary?.totalTokens == 930_000)
        #expect(try abs(#require(report.summary?.totalCostUSD) - 11.6) < 1e-9)
        await store.closeConnectionForTesting()
        let reopened = store.syncLoadCodexCache(calendar: calendar)
        let rows = try #require(reopened.files[file.path]?.codexRows)
        #expect(rows.map(\.pricingMode) == ["ultrafast", "ultrafast", "standard"])
        #expect(rows.map(\.timestampUnixMs) == [1_803_887_999_000, 1_803_888_000_000, 1_803_888_000_000])
        let saved = await store.readSnapshot()
        #expect(saved.fileDayAggregates.first?.aggregate.ultrafastTokens == 620_000)
        #expect(saved.fileDayAggregates.first?.aggregate.standardTokens == 310_000)
        #expect(saved.dayAggregates.first?.ultrafastTokens == 620_000)
        let again = CostUsageScanner.loadDailyReport(
            provider: .codex, since: before, until: after, now: after.addingTimeInterval(2), options: options)
        #expect(again.data == report.data)
        let projection = store.syncReadCodexReportProjection(calendar: calendar)
        let compact = CostUsageCodexReportProjectionBuilder.buildReport(
            projection: projection,
            range: .init(since: before, until: after, calendar: calendar),
            cacheRoot: env.cacheRoot)
        #expect(try abs(#require(compact.summary?.totalCostUSD) - 11.6) < 1e-9)
    }

    #if DEBUG
    @Test(arguments: [false, true])
    func `compact Ultrafast report preserves zero and unknown prices`(hasUnknown: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 11, day: 1)
        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day)
        let key = range.sinceKey
        var rows: [CostUsageScanner.CodexUsageRow] = [
            .init(
                day: key,
                model: "gpt-6.1-sol",
                turnID: nil,
                eventIndex: 0,
                input: 10,
                cached: 0,
                output: 0,
                knownCostNanos: 0,
                pricingMode: "ultrafast"),
        ]
        if hasUnknown {
            rows.append(.init(
                day: key,
                model: "gpt-6.1-sol",
                turnID: nil,
                eventIndex: 1,
                input: 10,
                cached: 0,
                output: 0,
                unpricedTokens: 10,
                pricingMode: "ultrafast"))
        }
        let usage = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 1,
            days: [key: ["gpt-6.1-sol": [hasUnknown ? 20 : 10, 0, 0]]],
            parsedBytes: 1,
            codexRows: rows,
            codexScanComplete: true)
        let aggregate = try #require(CostUsageStore.fileAggregatesForTesting(usage).first)
        let path = env.codexSessionsRoot.appendingPathComponent("ultrafast.jsonl").path
        var cache = CostUsageCache()
        cache.files[path] = usage
        cache.days = usage.days
        let projection = CostUsageStoreCodexReportProjection(
            cache: cache,
            fileDayAggregates: [.init(path: path, aggregate: aggregate)])
        let report = CostUsageCodexReportProjectionBuilder.build(
            projection: projection,
            roots: [env.codexSessionsRoot],
            range: range,
            cacheRoot: env.cacheRoot,
            includeBreakdowns: false).report
        #expect(report.data.first?.costUSD == 0)
        #expect(report.data.first?.unpricedRequestCount == (hasUnknown ? 1 : nil))
    }
    #endif

    private static func cost(model: String, mode: String, date: Date?) -> Double? {
        CostUsageScanner.codexResolvedCostUSD(
            for: .init(
                day: "2027-03-01",
                model: model,
                turnID: "synthetic-turn",
                eventIndex: 0,
                timestampUnixMs: date.map { Int64($0.timeIntervalSince1970 * 1000) },
                input: 300_000,
                cached: 50000,
                output: 10000,
                pricingMode: mode),
            modelsDevCatalog: nil,
            modelsDevCacheRoot: nil)
    }

    private static func record(_ type: String, at date: Date, payload: [String: Any]) -> [String: Any] {
        ["type": type, "timestamp": ISO8601DateFormatter().string(from: date), "payload": payload]
    }

    private static func request(at date: Date, response: String) -> [String: Any] {
        let count = response == "promotion" ? 1 : response == "regular" ? 2 : 3
        return self.record("token_usage_record", at: date, payload: [
            "thread_id": "synthetic-ultrafast", "response_id": response, "turn_id": "ultrafast-turn",
            "thread_token_usage": [
                "input_tokens": 300_000 * count,
                "cached_input_tokens": 50000 * count,
                "output_tokens": 10000 * count,
            ],
            "model": "gpt-6.2-sol", "usage": [
                "input_tokens": 300_000,
                "cached_input_tokens": 50000,
                "output_tokens": 10000,
            ],
        ])
    }
}
