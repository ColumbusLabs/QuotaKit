import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageCodexAutoReviewTests {
    @Test
    func `custom rates win while uncovered free requests stay unknown`() throws {
        let model = "codex-auto-review"
        let day = "2026-10-06"
        let instant = Date(timeIntervalSince1970: 1_791_270_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var usage = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 1,
            days: [day: [model: [1000, 0, 10]]],
            parsedBytes: 1,
            codexRows: [.init(
                day: day,
                model: model,
                turnID: nil,
                eventIndex: 0,
                timestampUnixMs: 1_791_270_000_000,
                input: 1000,
                cached: 0,
                output: 10)],
            codexScanComplete: true)
        usage.codexSession = .init(
            sessionId: nil, forkedFromId: nil, cwd: nil, title: nil,
            startedAtUnixMs: nil, latestActivityUnixMs: nil, hasCreatorAccount: true)
        var cache = CostUsageCache()
        cache.files = ["/review-fixture.jsonl": usage]
        cache.days = usage.days
        let catalog = ModelsDevCatalog(providers: ["openai": .init(
            id: "openai", name: "OpenAI", models: [model: .init(
                id: model, name: nil, cost: .init(input: 1, output: 2), limit: nil)])])
        func report(_ custom: CostUsageCustomPricing = .empty) -> CostUsageDailyReport {
            CostUsageScanner.buildCodexReportFromCache(
                cache: cache,
                range: .init(since: instant, until: instant, calendar: calendar),
                modelsDevCatalog: catalog,
                customPricing: custom)
        }
        let custom = CostUsageCustomPricing.parse(Data(#"{"openai/codex-auto-review":{"input":5,"output":10}}"#.utf8))
        #expect(report().data.first?.costUSD == 0)
        #expect(abs((report(custom).data.first?.costUSD ?? -1) - 0.0051) < 1e-12)

        // A missing request makes the day's token totals larger than the retained rows.
        cache.days[day]?[model]?[0] = 1500
        let uncovered = report()
        #expect(uncovered.data.first?.costUSD == nil)
        #expect(uncovered.data.first?.coverageCounts.unpriced == 1)
        #expect(uncovered.quotaSlices.count == 1)
        #expect(uncovered.quotaSlices.first?.costUSD == nil)
        #expect(uncovered.quotaSlices.first?.costIsComplete == false)
        #expect(abs((report(custom).data.first?.costUSD ?? -1) - 0.0076) < 1e-12)
    }

    @Test(arguments: [false, true])
    func `only ChatGPT auto review from the cutoff is free across cache refreshes`(workingSet: Bool) throws {
        let cutoff = Date(timeIntervalSince1970: 1_791_270_000)
        for creator in [nil, " \n", "account-fixture"] as [String?] {
            for instant in [cutoff.addingTimeInterval(-1), cutoff] {
                let env = try CostUsageTestEnvironment()
                defer { env.cleanup() }
                let timestamp = env.isoString(for: instant)
                var metadata: [String: Any] = ["id": "review-fixture"]
                if let creator { metadata["creator_account_id"] = creator }
                let contents = try env.jsonl([
                    ["type": "session_meta", "timestamp": timestamp, "payload": metadata],
                    ["type": "turn_context", "timestamp": timestamp, "payload": ["model": "codex-auto-review"]],
                    ["type": "event_msg", "timestamp": timestamp, "payload": [
                        "type": "token_count",
                        "info": ["last_token_usage": [
                            "input_tokens": 1000, "cached_input_tokens": 200, "output_tokens": 100,
                        ]],
                    ]],
                ])
                _ = try env.writeCodexSessionFile(day: instant, filename: "review.jsonl", contents: contents)
                var options = CostUsageScanner.Options(
                    codexSessionsRoot: env.codexSessionsRoot,
                    claudeProjectsRoots: nil,
                    cacheRoot: env.cacheRoot,
                    codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"))
                options.refreshMinIntervalSeconds = 0
                options.useCodexCatchUpWorkingSet = workingSet
                let isFree = creator == "account-fixture" && instant >= cutoff
                for refresh in 0..<3 {
                    if refresh == 2 {
                        var legacy = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
                        for path in legacy.files.keys {
                            legacy.files[path]?.codexSession = nil
                            legacy.files[path]?.codexParserRevision = CostUsageFileUsage.currentCodexParserRevision - 1
                        }
                        #expect(!CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: legacy).catchUpRequired)
                    }
                    let scannedReport = CostUsageScanner.loadDailyReport(
                        provider: .codex, since: instant, until: instant, now: cutoff, options: options)
                    let report = CostUsageScanner.buildCodexReportFromCache(
                        cache: CostUsageStoreAccess.read(cacheRoot: env.cacheRoot),
                        range: .init(since: instant, until: instant),
                        modelsDevCatalog: ModelsDevCatalog(providers: [:]))
                    let entry = try #require(report.data.first)
                    #expect(scannedReport.data.first?.totalTokens == 1100)
                    #expect(scannedReport.data.first?.costUSD == (isFree ? 0 : nil))
                    #expect(scannedReport.hourly.first?.costIsComplete == isFree)
                    #expect(scannedReport.quotaSlices.first?.costUSD == (isFree ? 0 : nil))
                    #expect(entry.totalTokens == 1100)
                    #expect(entry.cacheReadTokens == 200)
                    #expect(entry.coverageCounts.unmetered == 0)
                    #expect(entry.coverageCounts.unpriced == (isFree ? 0 : 1))
                    #expect(entry.costUSD == (isFree ? 0 : nil))
                    #expect(entry.modelBreakdowns?.first?.costUSD == (isFree ? 0 : nil))
                    #expect(report.quotaSlices.first?.costIsComplete == isFree)
                    #expect(report.quotaSlices.first?.costUSD == (isFree ? 0 : nil))
                    #expect(report.hourly.first?.costIsComplete == isFree)
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func `only the leaf creator flag survives embedded and resumed session metadata`(chatGPTLeaf: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let instant = Date(timeIntervalSince1970: 1_791_270_000)
        let timestamp = env.isoString(for: instant)
        var leaf: [String: Any] = ["id": "leaf-fixture"]
        if chatGPTLeaf { leaf["creator_account_id"] = "leaf-account-fixture" }
        let contents = try env.jsonl([
            ["type": "session_meta", "timestamp": timestamp, "payload": leaf],
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": ["id": "ancestor-fixture", "creator_account_id": "ancestor-account-fixture"],
            ],
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": ["id": "leaf-fixture", "creator_account_id": chatGPTLeaf ? "" : "resume-account-fixture"],
            ],
        ])
        let file = env.root.appendingPathComponent("creator-fixture.jsonl")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        let result = try CostUsageScanner.parseCodexFileCancellable(
            fileURL: file, range: .init(since: instant, until: instant))
        #expect(result.codexSession.hasCreatorAccount == chatGPTLeaf)
        #expect(result.codexSession.sessionId == "leaf-fixture")
        let appended = CostUsageCodexSessionMetadata(
            sessionId: nil, forkedFromId: nil, cwd: nil, title: nil,
            startedAtUnixMs: nil, latestActivityUnixMs: nil)
        #expect(result.codexSession.merging(appended).hasCreatorAccount == chatGPTLeaf)
    }

    @Test(arguments: ["saved", "missing timestamp", "missing request", "unpriced tokens", "eligible"])
    func `saved prices and unreliable evidence never become the Auto review waiver`(evidence: String) throws {
        let instant = Date(timeIntervalSince1970: 1_791_270_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = "2026-10-06"
        let row = CostUsageScanner.CodexUsageRow(
            day: day, model: "openai/codex-auto-review", turnID: nil,
            eventIndex: evidence == "missing request" ? nil : 0,
            timestampUnixMs: evidence == "missing timestamp" ? nil : 1_791_270_000_000,
            input: 100, cached: 0, output: 10,
            knownCostNanos: evidence == "saved" ? 123_000_000 : nil,
            unpricedTokens: evidence == "unpriced tokens" ? 1 : nil)
        var usage = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1, size: 1, days: [day: [row.model: [100, 0, 10]]],
            parsedBytes: 1, codexRows: [row], codexScanComplete: true)
        usage.codexSession = .init(
            sessionId: nil, forkedFromId: nil, cwd: nil, title: nil,
            startedAtUnixMs: nil, latestActivityUnixMs: nil, hasCreatorAccount: true)
        var cache = CostUsageCache()
        cache.files["/review-fixture.jsonl"] = usage
        cache.days = usage.days
        let report = CostUsageScanner.buildCodexReportFromCache(
            cache: cache, range: .init(since: instant, until: instant, calendar: calendar),
            modelsDevCatalog: ModelsDevCatalog(providers: [:]), customPricing: .empty)
        let expected: Double? = evidence == "saved" ? 0.123 : (evidence == "eligible" ? 0 : nil)
        #expect(report.data.first?.costUSD == expected)
        #expect(report.summary?.totalTokens == 110)
        #expect(cache.files["/review-fixture.jsonl"]?.codexRows?.first == row)
        #expect(cache.files["/review-fixture.jsonl"]?.codexRows?.first?.isIncludedInPlan == nil)
    }

    @Test
    func `routine Mac token fetch publishes free Auto review daily and temporal costs`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let now = Date(timeIntervalSince1970: 1_791_270_000)
        let timestamp = env.isoString(for: now)
        let contents = try env.jsonl([
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": ["id": "routine-review", "creator_account_id": "account-fixture"],
            ],
            ["type": "turn_context", "timestamp": timestamp, "payload": ["model": "codex-auto-review"]],
            ["type": "event_msg", "timestamp": timestamp, "payload": [
                "type": "token_count", "info": ["last_token_usage": ["input_tokens": 100, "output_tokens": 10]],
            ]],
        ])
        _ = try env.writeCodexSessionFile(day: now, filename: "routine-review.jsonl", contents: contents)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot, cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"))
        options.refreshMinIntervalSeconds = 0
        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex, now: now, historyDays: 1, allowPricingRefresh: false,
            refreshPricingInBackground: false, includePiSessions: false, scannerOptions: options)
        let daily = snapshot.daily.first { $0.modelsUsed?.contains("codex-auto-review") == true }
        #expect(daily?.costUSD == 0)
        #expect(daily?.totalTokens == 110)
        #expect(snapshot.last30DaysCostUSD == 0)
        #expect(snapshot.sessions.first?.costUSD == 0)
    }

    #if DEBUG
    @Test(arguments: [
        "free",
        "saved",
        "custom",
        "uncovered",
        "uncovered custom",
        "no rows",
        "no rows custom",
        "no rows catalog",
        "no rows priority custom",
    ])
    func `compact stored projections match detailed Auto review pricing without changing source evidence`(
        policy: String) throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let instant = Date(timeIntervalSince1970: 1_791_270_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let range = CostUsageScanner.CostUsageDayRange(since: instant, until: instant, calendar: calendar)
        let file = try env.writeCodexSessionFile(day: instant, filename: "projection-review.jsonl", contents: "{}\n")
        let metadata = CostUsageScanner.codexFileMetadata(fileURL: file)
        let row = CostUsageScanner.CodexUsageRow(
            day: range.sinceKey, model: "codex-auto-review", turnID: nil, eventIndex: 0,
            timestampUnixMs: 1_791_270_000_000, input: 100, cached: 0, output: 10,
            knownCostNanos: policy == "saved" ? 123_000_000 : nil)
        let days = [range.sinceKey: [row.model: [policy.hasPrefix("uncovered") ? 150 : 100, 0, 10]]]
        var cache = CostUsageCache()
        cache.scanSinceKey = range.scanSinceKey
        cache.scanUntilKey = range.scanUntilKey
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.roots = [env.codexSessionsRoot.path: 0]
        cache.days = days
        var usage = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: metadata.mtimeUnixMs, size: metadata.size, days: days,
            parsedBytes: metadata.size, sessionId: "projection-review",
            codexRows: policy.hasPrefix("no rows") ? [] : [row],
            codexScanFileId: metadata.fileId, codexScanComplete: true)
        usage.codexSession = .init(
            sessionId: "projection-review", forkedFromId: nil, cwd: nil, title: nil,
            startedAtUnixMs: nil, latestActivityUnixMs: nil, hasCreatorAccount: true)
        if policy == "no rows priority custom" {
            usage.codexPriorityTokens = [range.sinceKey: [row.model: 110]]
        }
        cache.files[file.path] = usage
        let overlay = policy.hasSuffix("custom")
            ? CostUsageCustomPricing.parse(Data(#"{"codex-auto-review":{"input":5,"output":10}}"#.utf8))
            : .empty
        if policy == "no rows catalog" {
            let catalog = ModelsDevCatalog(providers: ["openai": .init(
                id: "openai", name: "OpenAI", models: [row.model: .init(
                    id: row.model, name: nil, cost: .init(input: 1, output: 2), limit: nil)])])
            #expect(ModelsDevCache.save(catalog: catalog, cacheRoot: env.cacheRoot))
        }
        var hooks = CostUsageStoreTestHooks()
        hooks.customPricingOverlay = overlay
        try CostUsageStoreTestHooks.$current.withValue(hooks) {
            let full = CostUsageScanner.buildCodexReportFromCache(
                cache: cache, range: range, modelsDevCacheRoot: env.cacheRoot)
            #expect(!CostUsageStoreAccess.replace(
                cacheRoot: env.cacheRoot, cache: cache, calendar: calendar).catchUpRequired)
            let store = CostUsageStore(cacheRoot: env.cacheRoot)
            let projection = store.syncReadCodexReportProjection(calendar: calendar)
            let compact = CostUsageCodexReportProjectionBuilder.build(
                projection: projection, roots: [env.codexSessionsRoot], range: range,
                cacheRoot: env.cacheRoot, includeBreakdowns: true).report
            let expected: Double? = switch policy {
            case "saved": 0.123
            case "custom", "no rows custom": 0.0006
            case "no rows catalog": 0.00012
            case "free": 0
            default: nil
            }
            if let expected {
                #expect(abs((full.data.first?.costUSD ?? -1) - expected) < 1e-12)
            } else {
                #expect(full.data.first?.costUSD == nil)
            }
            #expect(abs((compact.data.first?.costUSD ?? -1) - (full.data.first?.costUSD ?? -1)) < 1e-12)
            #expect(compact.data.first?.totalTokens == full.data.first?.totalTokens)
            #expect(compact.data.first?.coverageCounts.unpriced == full.data.first?.coverageCounts.unpriced)
            #expect(compact.hourly == full.hourly)
            #expect(compact.quotaSlices == full.quotaSlices)
            let stored = store.syncLoadCodexCache(calendar: calendar)
            // An empty eager row ledger restores an aggregate fallback row by design.
            if !policy.hasPrefix("no rows") {
                #expect(stored.files[file.path]?.codexRows == usage.codexRows)
                #expect(stored.files[file.path]?.codexRows?.first?.isIncludedInPlan == nil)
                #expect(stored.files[file.path]?.codexRows?.first?.knownCostNanos
                    == usage.codexRows?.first?.knownCostNanos)
            }
        }
    }

    @Test
    func `settled working set reprices historical Auto review when a custom overlay is added and removed`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let instant = Date(timeIntervalSince1970: 1_791_270_000)
        let now = instant.addingTimeInterval(2 * 86400)
        let timestamp = env.isoString(for: instant)
        let contents = try env.jsonl([
            [
                "type": "session_meta",
                "timestamp": timestamp,
                "payload": ["id": "historical-review", "creator_account_id": "account-fixture"],
            ],
            ["type": "turn_context", "timestamp": timestamp, "payload": ["model": "codex-auto-review"]],
            ["type": "event_msg", "timestamp": timestamp, "payload": [
                "type": "token_count", "info": ["last_token_usage": ["input_tokens": 100, "output_tokens": 10]],
            ]],
        ])
        let file = try env.writeCodexSessionFile(day: instant, filename: "historical-review.jsonl", contents: contents)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot, cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"),
            useCodexCatchUpWorkingSet: true)
        options.refreshMinIntervalSeconds = 0
        let overlay = CostUsageCustomPricing.parse(Data(#"{"codex-auto-review":{"input":5,"output":10}}"#.utf8))
        for pricing in [CostUsageCustomPricing.empty, overlay, .empty] {
            var hooks = CostUsageStoreTestHooks()
            hooks.customPricingOverlay = pricing
            try CostUsageStoreTestHooks.$current.withValue(hooks) {
                var settled: CostUsageDailyReport?
                for _ in 0..<12 {
                    settled = CostUsageScanner.loadDailyReport(
                        provider: .codex, since: instant, until: now, now: now, options: options)
                    if CostUsageStoreAccess.read(cacheRoot: env.cacheRoot).codexScanCatchUpPending != true { break }
                }
                let expected = pricing == .empty ? 0.0 : 0.0006
                #expect(abs((settled?.data.first?.costUSD ?? -1) - expected) < 1e-12)
                let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
                #expect(cache.codexScanCatchUpPending != true)
                #expect(cache.files[file.path]?.codexRows?.first?.knownCostNanos == nil)
                #expect(cache.files[file.path]?.codexRows?.first?.isIncludedInPlan == nil)
                let full = CostUsageScanner.buildCodexReportFromCache(
                    cache: cache, range: .init(since: instant, until: now, calendar: options.calendar))
                #expect(abs((settled?.data.first?.costUSD ?? -1) - (full.data.first?.costUSD ?? -1)) < 1e-12)
                #expect(settled?.hourly == full.hourly)
            }
        }
    }
    #endif
}
