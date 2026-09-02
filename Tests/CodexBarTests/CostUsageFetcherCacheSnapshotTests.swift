import Foundation
import Testing
@testable import CodexBarCore

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
struct CostUsageFetcherCacheSnapshotTests {
    @Test
    func `routine codex refresh uses query backed working set without a full snapshot read`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: now,
            filename: "routine-working-set.jsonl",
            tokens: 42)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        options.refreshMinIntervalSeconds = 0

        #if DEBUG
        let databaseURL = CostUsageStore(cacheRoot: env.cacheRoot).databaseURL
        var fullSnapshotReads = 0
        CostUsageStore.snapshotReadForTesting = { readURL in
            if readURL == databaseURL {
                fullSnapshotReads += 1
            }
        }
        defer { CostUsageStore.snapshotReadForTesting = nil }
        #endif

        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: now,
            historyDays: 1,
            allowPricingRefresh: false,
            refreshPricingInBackground: false,
            includePiSessions: false,
            scannerOptions: options)

        #expect(snapshot.sessionTokens == 42)
        #expect(snapshot.sessions.count == 1)
        #if DEBUG
        #expect(fullSnapshotReads == 0)
        #endif
    }

    @Test
    func `cached projection preserves exact report evidence without a full snapshot hydration`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let day = "2026-04-08"
        let fileURL = try env.writeCodexSessionFile(day: now, filename: "projected.jsonl", contents: "{}\n")
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let range = CostUsageScanner.CostUsageDayRange(
            since: now,
            until: now,
            calendar: options.calendar)
        let fileMetadata = CostUsageScanner.codexFileMetadata(fileURL: fileURL)
        // Dense persisted-report fixtures are clearer when their row fields stay grouped.
        // swiftlint:disable multiline_arguments
        let rows = [
            CostUsageScanner.CodexUsageRow(
                day: day, model: "gpt-5.4", turnID: "standard", eventIndex: 0,
                input: 100, cached: 20, output: 10, reasoning: 5,
                knownCostNanos: 1_000_000_000, pricingModel: "gpt-5.4", pricingMode: "standard"),
            CostUsageScanner.CodexUsageRow(
                day: day, model: "gpt-5.4", turnID: "priority", eventIndex: 1,
                input: 200, cached: 40, output: 20, reasoning: 7,
                knownCostNanos: 2_000_000_000, pricingModel: "gpt-5.4", pricingMode: "priority"),
        ]
        // swiftlint:enable multiline_arguments
        var cache = CostUsageCache()
        cache.lastScanUnixMs = Int64(now.timeIntervalSince1970 * 1000)
        cache.scanSinceKey = range.scanSinceKey
        cache.scanUntilKey = range.scanUntilKey
        cache.timeZoneIdentifier = options.calendar.timeZone.identifier
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.codexProjectMetadataVersion = CostUsageScanner.codexProjectMetadataVersion
        cache.days = [day: ["gpt-5.4": [300, 60, 30]]]
        cache.files[fileURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: fileMetadata.mtimeUnixMs,
            size: fileMetadata.size,
            days: cache.days,
            parsedBytes: fileMetadata.size,
            sessionId: "projected-session",
            projectPath: "/tmp/projected-project",
            canonicalProjectPath: "/tmp/projected-project",
            codexRows: rows,
            codexScanFileId: fileMetadata.fileId,
            codexScanTargetSize: fileMetadata.size,
            codexScanComplete: true)
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: options.calendar)

        let projection = await CostUsageStoreAccess.readCodexReportProjection(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar)
        #expect(projection.cache.days == cache.days)
        #expect(projection.cache.roots == cache.roots)
        #expect(projection.fileDayAggregates.count == 1)
        #expect(projection.fileDayAggregates.first?.aggregate.requestCount == 2)
        #expect(projection.fileDayAggregates.first?.aggregate.reasoningTokens == 12)

        #if DEBUG
        let databaseURL = CostUsageStore(cacheRoot: env.cacheRoot).databaseURL
        var fullSnapshotReads = 0
        CostUsageStore.snapshotReadForTesting = { readURL in
            if readURL == databaseURL {
                fullSnapshotReads += 1
            }
        }
        defer { CostUsageStore.snapshotReadForTesting = nil }
        #endif

        let result = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 1,
            includePiSessions: false,
            scannerOptions: options)

        let entry = try #require(result?.snapshot.daily.first)
        let model = try #require(entry.modelBreakdowns?.first)
        #expect(entry.requestCount == 2)
        #expect(entry.reasoningTokens == 12)
        #expect(entry.costUSD == 3)
        #expect(model.standardCostUSD == 1)
        #expect(model.priorityCostUSD == 2)
        #expect(model.standardTokens == 110)
        #expect(model.priorityTokens == 220)
        #expect(result?.snapshot.projects.first?.path == "/tmp/projected-project")
        #expect(result?.snapshot.sessions.first?.sessionID == "projected-session")
        #if DEBUG
        #expect(fullSnapshotReads == 0)
        #endif
    }

    @Test
    func `compact session projection preserves unknown request counts`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let day = "2026-04-08"
        let fileURL = env.codexSessionsRoot.appendingPathComponent("compatibility.jsonl")
        let range = CostUsageScanner.CostUsageDayRange(
            since: now,
            until: now,
            calendar: .current)
        var aggregate = CostUsageStoreDayAggregate.zero(day: day, model: "gpt-5.4")
        aggregate.inputTokens = 42
        aggregate.standardInputTokens = 42
        aggregate.standardTokens = 42
        var cache = CostUsageCache()
        cache.days = [day: ["gpt-5.4": [42, 0, 0]]]
        cache.files[fileURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: Int64(now.timeIntervalSince1970 * 1000),
            size: 1,
            days: cache.days,
            parsedBytes: 1,
            sessionId: "compatibility-session",
            codexScanComplete: true)

        let compact = CostUsageCodexReportProjectionBuilder.build(
            projection: CostUsageStoreCodexReportProjection(
                cache: cache,
                fileDayAggregates: [.init(path: fileURL.path, aggregate: aggregate)]),
            roots: [env.codexSessionsRoot],
            range: range,
            cacheRoot: env.cacheRoot,
            includeBreakdowns: true)
        let compatibility = CostUsageScanner.buildCodexSessionBreakdownsFromCache(
            cache: cache,
            range: range,
            sessionRoots: [env.codexSessionsRoot])

        #expect(compact.report.data.first?.requestCount == nil)
        #expect(compact.sessions.first?.requestCount == compatibility.first?.requestCount)
        #expect(compact.sessions.first?.requestCount == nil)
    }

    @Test
    func `compact projection preserves mixed priced and unpriced request evidence`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let day = "2026-04-08"
        let fileURL = try env.writeCodexSessionFile(day: now, filename: "mixed.jsonl", contents: "{}\n")
        let options = CostUsageScanner.Options(codexSessionsRoot: env.codexSessionsRoot, cacheRoot: env.cacheRoot)
        let range = CostUsageScanner.CostUsageDayRange(since: now, until: now, calendar: options.calendar)
        let metadata = CostUsageScanner.codexFileMetadata(fileURL: fileURL)
        // swiftlint:disable multiline_arguments
        let rows = [
            CostUsageScanner.CodexUsageRow(
                day: day, model: "gpt-5.4", turnID: "priced", eventIndex: 0,
                input: 100, cached: 20, output: 10, knownCostNanos: 1_000_000_000,
                pricingModel: "gpt-5.4", pricingMode: "standard"),
            CostUsageScanner.CodexUsageRow(
                day: day, model: "gpt-5.4", turnID: "unpriced", eventIndex: 1,
                input: 40, cached: 0, output: 10, unpricedTokens: 50,
                pricingModel: "gpt-5.4", pricingMode: "standard"),
        ]
        // swiftlint:enable multiline_arguments
        var cache = CostUsageCache()
        cache.scanSinceKey = range.scanSinceKey
        cache.scanUntilKey = range.scanUntilKey
        cache.timeZoneIdentifier = options.calendar.timeZone.identifier
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.days = [day: ["gpt-5.4": [140, 20, 20]]]
        cache.files[fileURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: metadata.mtimeUnixMs,
            size: metadata.size,
            days: cache.days,
            parsedBytes: metadata.size,
            sessionId: "mixed",
            codexRows: rows,
            codexScanFileId: metadata.fileId,
            codexScanComplete: true)
        let compatibility = CostUsageScanner.buildCodexReportFromCache(cache: cache, range: range)
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache, calendar: options.calendar)

        let projection = await CostUsageStoreAccess.readCodexReportProjection(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar)
        let compact = CostUsageCodexReportProjectionBuilder.build(
            projection: projection,
            roots: [env.codexSessionsRoot],
            range: range,
            cacheRoot: env.cacheRoot,
            includeBreakdowns: false).report

        #expect(projection.fileDayAggregates.first?.aggregate.unpricedRequestCount == 1)
        #expect(compact.summary?.totalTokens == compatibility.summary?.totalTokens)
        #expect(compact.summary?.totalCostUSD == compatibility.summary?.totalCostUSD)
        #expect(compact.data.first?.requestCount == compatibility.data.first?.requestCount)
        #expect(compact.data.first?.unpricedRequestCount == compatibility.data.first?.unpricedRequestCount)
        #expect(compact.data.first?.unpricedRequestCount == 1)
        #expect(compact.data.first?.costUSD == nil)
    }

    @Test
    func `compact projection preserves routed model and historical pricing semantics`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let now = try env.makeLocalNoon(year: 2026, month: 7, day: 29)
        let day = "2026-07-29"
        let fileURL = try env.writeCodexSessionFile(day: now, filename: "pricing-parity.jsonl", contents: "{}\n")
        let options = CostUsageScanner.Options(codexSessionsRoot: env.codexSessionsRoot, cacheRoot: env.cacheRoot)
        let range = CostUsageScanner.CostUsageDayRange(since: now, until: now, calendar: options.calendar)
        let metadata = CostUsageScanner.codexFileMetadata(fileURL: fileURL)
        let historicalTimestamp = try Int64(#require(ISO8601DateFormatter().date(
            from: "2026-07-29T12:00:00Z")).timeIntervalSince1970 * 1000)
        // swiftlint:disable multiline_arguments
        let rows = [
            CostUsageScanner.CodexUsageRow(
                day: day, model: "gpt-fictitious-display", turnID: "routed", eventIndex: 0,
                timestampUnixMs: historicalTimestamp, input: 1_000_000, cached: 0, output: 100_000,
                pricingModel: "gpt-5.4", pricingMode: "standard"),
            CostUsageScanner.CodexUsageRow(
                day: day, model: "gpt-5.6-terra", turnID: "historical", eventIndex: 1,
                timestampUnixMs: historicalTimestamp, input: 1_000_000, cached: 0, output: 100_000,
                pricingModel: "gpt-5.6-terra", pricingMode: "standard"),
        ]
        // swiftlint:enable multiline_arguments
        let days = [day: [
            "gpt-fictitious-display": [1_000_000, 0, 100_000],
            "gpt-5.6-terra": [1_000_000, 0, 100_000],
        ]]
        var cache = CostUsageCache()
        cache.scanSinceKey = range.scanSinceKey
        cache.scanUntilKey = range.scanUntilKey
        cache.timeZoneIdentifier = options.calendar.timeZone.identifier
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.days = days
        cache.files[fileURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: metadata.mtimeUnixMs,
            size: metadata.size,
            days: days,
            parsedBytes: metadata.size,
            sessionId: "pricing-parity",
            codexRows: rows,
            codexScanFileId: metadata.fileId,
            codexScanComplete: true)
        let full = CostUsageScanner.buildCodexReportFromCache(
            cache: cache,
            range: range,
            modelsDevCacheRoot: env.cacheRoot)
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache, calendar: options.calendar)

        let projection = await CostUsageStoreAccess.readCodexReportProjection(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar)
        let compact = CostUsageCodexReportProjectionBuilder.build(
            projection: projection,
            roots: [env.codexSessionsRoot],
            range: range,
            cacheRoot: env.cacheRoot,
            includeBreakdowns: false).report
        let fullModels = try Dictionary(uniqueKeysWithValues: #require(full.data.first?.modelBreakdowns).map {
            ($0.modelName, $0.costUSD)
        })
        let compactModels = try Dictionary(uniqueKeysWithValues: #require(compact.data.first?.modelBreakdowns).map {
            ($0.modelName, $0.costUSD)
        })
        let fullPricedModels = fullModels.compactMapValues { $0 }
        let compactPricedModels = compactModels.compactMapValues { $0 }

        let fullRoutedCost = try #require(fullPricedModels["gpt-fictitious-display"])
        let fullHistoricalCost = try #require(fullPricedModels["gpt-5.6-terra"])
        let compactRoutedCost = try #require(compactPricedModels["gpt-fictitious-display"])
        let compactHistoricalCost = try #require(compactPricedModels["gpt-5.6-terra"])
        #expect(compactRoutedCost == fullRoutedCost)
        #expect(compactHistoricalCost == fullHistoricalCost)
        #expect(compact.summary?.totalCostUSD == full.summary?.totalCostUSD)
    }

    @Test
    func `compact projection preserves cached only standard and priority cost evidence`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let now = try env.makeLocalNoon(year: 2026, month: 8, day: 8)
        let day = "2026-08-08"
        let fileURL = try env.writeCodexSessionFile(day: now, filename: "cached-only.jsonl", contents: "{}\n")
        let options = CostUsageScanner.Options(codexSessionsRoot: env.codexSessionsRoot, cacheRoot: env.cacheRoot)
        let range = CostUsageScanner.CostUsageDayRange(since: now, until: now, calendar: options.calendar)
        let metadata = CostUsageScanner.codexFileMetadata(fileURL: fileURL)
        // swiftlint:disable multiline_arguments
        let rows = [
            CostUsageScanner.CodexUsageRow(
                day: day, model: "gpt-5.4", turnID: "standard-cache", eventIndex: 0,
                input: 0, cached: 1_000_000, output: 0,
                pricingModel: "gpt-5.4", pricingMode: "standard"),
            CostUsageScanner.CodexUsageRow(
                day: day, model: "gpt-5.4", turnID: "priority-cache", eventIndex: 1,
                input: 0, cached: 1_000_000, output: 0,
                pricingModel: "gpt-5.4", pricingMode: "priority"),
        ]
        // swiftlint:enable multiline_arguments
        let days = [day: ["gpt-5.4": [0, 2_000_000, 0]]]
        var cache = CostUsageCache()
        cache.scanSinceKey = range.scanSinceKey
        cache.scanUntilKey = range.scanUntilKey
        cache.timeZoneIdentifier = options.calendar.timeZone.identifier
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.days = days
        cache.files[fileURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: metadata.mtimeUnixMs,
            size: metadata.size,
            days: days,
            parsedBytes: metadata.size,
            sessionId: "cached-only",
            codexRows: rows,
            codexScanFileId: metadata.fileId,
            codexScanComplete: true)
        let full = CostUsageScanner.buildCodexReportFromCache(cache: cache, range: range)
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache, calendar: options.calendar)

        let projection = await CostUsageStoreAccess.readCodexReportProjection(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar)
        let compact = CostUsageCodexReportProjectionBuilder.build(
            projection: projection,
            roots: [env.codexSessionsRoot],
            range: range,
            cacheRoot: env.cacheRoot,
            includeBreakdowns: false).report
        let fullModel = try #require(full.data.first?.modelBreakdowns?.first)
        let compactModel = try #require(compact.data.first?.modelBreakdowns?.first)

        #expect(compactModel.costUSD == fullModel.costUSD)
        #expect(compactModel.standardCostUSD == fullModel.standardCostUSD)
        #expect(compactModel.priorityCostUSD == fullModel.priorityCostUSD)
        #expect(compactModel.standardCostUSD != nil)
        #expect(compactModel.priorityCostUSD != nil)
    }

    @Test
    func `cached token activity derives buckets and partial coverage from the shared scan cache`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-04-06"
        cache.scanUntilKey = "2026-04-08"
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        let fixtureDays = [
            "2026-04-06": ["gpt-5.4": [10, 4, 2]],
            "2026-04-08": [
                "gpt-5.4": [20, 7, 3],
                "gpt-5.3-codex": [5, 1, 1],
            ],
        ]
        cache.files[env.codexSessionsRoot.appendingPathComponent("fixture.jsonl").path] =
            CostUsageScanner.makeFileUsage(
                mtimeUnixMs: Int64(now.timeIntervalSince1970 * 1000),
                size: 1,
                days: fixtureDays,
                parsedBytes: 1,
                codexScanComplete: true)
        cache.days = fixtureDays
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: options.calendar)

        let readCount = LockIsolated(0)
        let databaseURL = CostUsageStore(cacheRoot: env.cacheRoot).databaseURL
        CostUsageStore.snapshotReadForTesting = { readURL in
            guard readURL == databaseURL else { return }
            readCount.setValue(readCount.value + 1)
        }
        defer { CostUsageStore.snapshotReadForTesting = nil }
        let activity = await CostUsageFetcher.loadCachedCodexTokenActivity(
            now: now,
            maximumDays: 365,
            scannerOptions: options)

        #expect(readCount.value == 0)
        #expect(activity?.coverageSinceKey == "2026-04-06")
        #expect(activity?.coverageUntilKey == "2026-04-08")
        #expect(activity?.daily.map(\.date) == ["2026-04-06", "2026-04-08"])
        #expect(activity?.daily.map(\.totalTokens) == [12, 29])
    }

    @Test
    func `empty shared scan cache preserves established coverage`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-04-08"
        cache.scanUntilKey = "2026-04-08"
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: options.calendar)

        let activity = await CostUsageFetcher.loadCachedCodexTokenActivity(
            now: now,
            maximumDays: 365,
            scannerOptions: options)

        #expect(activity?.coverageSinceKey == "2026-04-08")
        #expect(activity?.coverageUntilKey == "2026-04-08")
        #expect(activity?.daily.isEmpty == true)
    }

    @Test
    func `cached codex token snapshot preserves a completed empty history`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let scanTime = now.addingTimeInterval(-60)
        var cache = CostUsageCache()
        cache.lastScanUnixMs = Int64(scanTime.timeIntervalSince1970 * 1000)
        cache.scanSinceKey = "2026-04-07"
        cache.scanUntilKey = "2026-04-09"
        cache.timeZoneIdentifier = options.calendar.timeZone.identifier
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: options.calendar)
        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 1,
            includePiSessions: false,
            scannerOptions: options)

        #expect(cached?.snapshot.sessionTokens == 0)
        #expect(cached?.snapshot.sessionCostUSD == 0)
        #expect(cached?.snapshot.last30DaysTokens == 0)
        #expect(cached?.snapshot.last30DaysCostUSD == 0)
        #expect(cached?.snapshot.historyCoverageIsEstablished == true)
        #expect(cached?.lastRefreshAt == scanTime)
    }

    @Test
    func `cached empty history becomes unavailable after the local day rolls over`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var beforeMidnightComponents = DateComponents()
        beforeMidnightComponents.calendar = calendar
        beforeMidnightComponents.timeZone = calendar.timeZone
        beforeMidnightComponents.year = 2026
        beforeMidnightComponents.month = 4
        beforeMidnightComponents.day = 8
        beforeMidnightComponents.hour = 23
        beforeMidnightComponents.minute = 59
        let beforeMidnight = try #require(beforeMidnightComponents.date)
        let afterMidnight = beforeMidnight.addingTimeInterval(2 * 60)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            calendar: calendar)
        var cache = CostUsageCache()
        cache.lastScanUnixMs = Int64(beforeMidnight.timeIntervalSince1970 * 1000)
        cache.scanSinceKey = "2026-04-07"
        cache.scanUntilKey = "2026-04-09"
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: calendar)

        let established = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: beforeMidnight,
            historyDays: 1,
            includePiSessions: false,
            scannerOptions: options)
        let expanded = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: afterMidnight,
            historyDays: 1,
            includePiSessions: false,
            scannerOptions: options)

        #expect(established?.snapshot.last30DaysCostUSD == 0)
        #expect(established?.snapshot.historyCoverageIsEstablished == true)
        #expect(expanded == nil)
    }

    @Test
    func `cached codex token snapshot refuses an empty history while catch up is pending`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        var cache = CostUsageCache()
        cache.lastScanUnixMs = Int64(now.addingTimeInterval(-60).timeIntervalSince1970 * 1000)
        cache.scanSinceKey = "2026-04-07"
        cache.scanUntilKey = "2026-04-09"
        cache.timeZoneIdentifier = options.calendar.timeZone.identifier
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: options.calendar)

        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 1,
            includePiSessions: false,
            scannerOptions: options)

        #expect(cached == nil)
    }

    @Test
    func `cached codex token snapshot refuses an empty history with buffered fork retries`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let line = CostUsageScanner.CodexBufferedFastLine(
            lineIndex: 1,
            ordinal: nil,
            line: .interAgentCommunication(triggerTurn: false))
        let filePath = env.codexSessionsRoot.appendingPathComponent("fork.jsonl").path
        var cache = CostUsageCache()
        cache.lastScanUnixMs = Int64(now.addingTimeInterval(-60).timeIntervalSince1970 * 1000)
        cache.scanSinceKey = "2026-04-07"
        cache.scanUntilKey = "2026-04-09"
        cache.timeZoneIdentifier = options.calendar.timeZone.identifier
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.files[filePath] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: cache.lastScanUnixMs,
            size: 1,
            days: [:],
            parsedBytes: 1,
            codexScanComplete: true,
            codexBufferedUnresolvedForkLines: [line])
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: options.calendar)

        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 1,
            includePiSessions: false,
            scannerOptions: options)

        #expect(cached == nil)
    }

    @Test
    func `cached codex token snapshot loads from existing cache without rescanning`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "cached.jsonl",
            tokens: 42)

        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            scannerOptions: options)

        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: day,
            historyDays: 1,
            scannerOptions: options)

        #expect(cached?.sessionTokens == 42)
        #expect(cached?.last30DaysTokens == 42)
        #expect(cached?.daily.map(\.date) == ["2026-04-08"])
    }

    @Test
    func `bounded narrow tail refresh retains only its requested cached window`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let olderDay = try env.makeLocalNoon(year: 2026, month: 2, day: 7)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: olderDay,
            filename: "older.jsonl",
            tokens: 11)
        let sessionURL = try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "active-tail.jsonl",
            tokens: 42)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        options.refreshMinIntervalSeconds = 0

        let established = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 365,
            includePiSessions: false,
            scannerOptions: options)
        let establishedCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(established.historyCoverageIsEstablished)
        #expect(established.last30DaysTokens == 53)
        #expect(establishedCache.codexScanCatchUpPending != true)

        let appendedAt = day.addingTimeInterval(10)
        let appendedLine = try env.jsonl([[
            "type": "event_msg",
            "timestamp": env.isoString(for: appendedAt),
            "payload": [
                "type": "token_count",
                "info": [
                    "last_token_usage": [
                        "input_tokens": 84,
                        "cached_input_tokens": 0,
                        "output_tokens": 0,
                    ],
                    "model": "openai/gpt-5.4",
                ],
            ],
        ]])
        let handle = try FileHandle(forWritingTo: sessionURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appendedLine.utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: appendedAt], ofItemAtPath: sessionURL.path)

        options.maxCodexScanDurationPerRefresh = .leastNonzeroMagnitude
        let partial = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: appendedAt,
            historyDays: 30,
            includePiSessions: false,
            scannerOptions: options)
        let pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: appendedAt,
            historyDays: 30,
            includePiSessions: false,
            scannerOptions: options)
        let narrowSince = try #require(options.calendar.date(byAdding: .day, value: -29, to: day))
        let wideSince = try #require(options.calendar.date(byAdding: .day, value: -364, to: day))
        let narrowRange = CostUsageScanner.CostUsageDayRange(
            since: narrowSince,
            until: appendedAt,
            calendar: options.calendar)
        let wideRange = CostUsageScanner.CostUsageDayRange(
            since: wideSince,
            until: appendedAt,
            calendar: options.calendar)
        let rootsFingerprint = CostUsageScanner.codexRootsFingerprint(options: options)
        let previous = try #require(pendingCache.codexPreviousReport)

        #expect(!partial.historyCoverageIsEstablished)
        #expect(partial.last30DaysTokens == 42)
        #expect(pendingCache.codexScanCatchUpPending == true)
        #expect(previous.report.data.map(\.date) == ["2026-04-08"])
        #expect(previous.scanSinceKey == narrowRange.sinceKey)
        #expect(previous.scanUntilKey == narrowRange.untilKey)
        #expect(CostUsageScanner.codexPreviousReport(
            cache: pendingCache,
            range: narrowRange,
            rootsFingerprint: rootsFingerprint) != nil)
        #expect(CostUsageScanner.codexPreviousReport(
            cache: pendingCache,
            range: wideRange,
            rootsFingerprint: rootsFingerprint) == nil)
        #expect(cached?.snapshot.historyCoverageIsEstablished == true)
        #expect(cached?.snapshot.last30DaysTokens == 42)
        #expect(cached?.staleSnapshotUpdatedAt == established.updatedAt)
        #expect(cached?.lastRefreshAt == nil)
    }

    @Test
    func `verified codex history projects alternating pending windows after reload`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let oldDay = try env.makeLocalNoon(year: 2026, month: 2, day: 7)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let wideSince = try #require(options.calendar.date(byAdding: .day, value: -364, to: now))
        let wideRange = CostUsageScanner.CostUsageDayRange(
            since: wideSince,
            until: now,
            calendar: options.calendar)
        let currentKey = wideRange.untilKey
        let oldKey = CostUsageScanner.CostUsageDayRange.dayKey(
            from: oldDay,
            calendar: options.calendar)
        let sessionURL = try env.writeCodexSessionFile(
            day: now,
            filename: "verified-history.jsonl",
            contents: "{}\n")
        let fileMetadata = CostUsageScanner.codexFileMetadata(fileURL: sessionURL)
        let days = [
            oldKey: ["gpt-5.4": [11, 0, 2]],
            currentKey: ["gpt-5.4": [42, 0, 8]],
        ]
        var established = CostUsageCache()
        established.lastScanUnixMs = Int64(now.timeIntervalSince1970 * 1000)
        established.scanSinceKey = wideRange.sinceKey
        established.scanUntilKey = wideRange.untilKey
        established.timeZoneIdentifier = options.calendar.timeZone.identifier
        established.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        established.days = days
        established.files[sessionURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: fileMetadata.mtimeUnixMs,
            size: fileMetadata.size,
            days: days,
            parsedBytes: fileMetadata.size,
            codexScanFileId: fileMetadata.fileId,
            codexScanTargetSize: fileMetadata.size,
            codexScanComplete: true)
        let establishedResult = CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: established,
            calendar: options.calendar)
        #expect(!establishedResult.catchUpRequired)

        // A bounded 365-day pass can replace the visible working set while the complete
        // report remains the publication baseline. This intentionally has no old payload.
        var pending = established
        pending.lastScanUnixMs += 10000
        pending.codexScanCatchUpPending = true
        pending.days = [currentKey: days[currentKey] ?? [:]]
        let pendingResult = CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: pending,
            calendar: options.calendar)
        #expect(!pendingResult.catchUpRequired)

        let reloadedProjection = await CostUsageStoreAccess.readCodexReportProjection(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar)
        #expect(reloadedProjection.verifiedScanSinceKey == wideRange.sinceKey)
        #expect(reloadedProjection.verifiedScanUntilKey == wideRange.untilKey)
        #expect(reloadedProjection.verifiedDayAggregates.count == 2)

        // Requesting the narrow projection first must not collapse the durable wide history.
        let narrow = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 30,
            includePiSessions: false,
            scannerOptions: options)
        #expect(narrow?.snapshot.daily.map(\.date) == [currentKey])
        #expect(narrow?.snapshot.last30DaysTokens == 50)
        #expect(narrow?.snapshot.historyCoverageIsEstablished == true)

        // A fresh store read of the reverse projection still sees its own complete range.
        let wide = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 365,
            includePiSessions: false,
            scannerOptions: options)
        #expect(wide?.snapshot.daily.map(\.date) == [oldKey, currentKey])
        #expect(wide?.snapshot.last30DaysTokens == 63)
        #expect(wide?.snapshot.historyCoverageIsEstablished == true)
    }

    @Test
    func `pending historical catch-up replaces only a fully indexed current day`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let olderDay = try env.makeLocalNoon(year: 2026, month: 2, day: 7)
        let currentDayKey = "2026-04-08"
        let currentURL = try env.writeCodexSessionFile(
            day: now,
            filename: "current-complete.jsonl",
            contents: "{}\n")
        let olderURL = try env.writeCodexSessionFile(
            day: olderDay,
            filename: "historical-pending.jsonl",
            contents: "{}\n")
        try FileManager.default.setAttributes(
            [.modificationDate: olderDay],
            ofItemAtPath: olderURL.path)

        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let since = try #require(options.calendar.date(byAdding: .day, value: -29, to: now))
        let range = CostUsageScanner.CostUsageDayRange(
            since: since,
            until: now,
            calendar: options.calendar)
        let currentMetadata = CostUsageScanner.codexFileMetadata(fileURL: currentURL)
        let olderMetadata = CostUsageScanner.codexFileMetadata(fileURL: olderURL)
        let roots = CostUsageScanner.codexRootsFingerprint(options: options)
        let oldScanAt = now.addingTimeInterval(-60)
        let freshScanAt = now.addingTimeInterval(60)
        let establishedReport = CostUsageDailyReport(data: [
            CostUsageDailyReport.Entry(
                date: "2026-04-07",
                inputTokens: 10,
                outputTokens: 0,
                totalTokens: 10,
                costUSD: 3,
                modelsUsed: nil,
                modelBreakdowns: nil),
            CostUsageDailyReport.Entry(
                date: currentDayKey,
                inputTokens: 5,
                outputTokens: 0,
                totalTokens: 5,
                costUSD: 1,
                modelsUsed: nil,
                modelBreakdowns: nil),
        ], summary: nil)

        var cache = CostUsageCache()
        cache.lastScanUnixMs = Int64(oldScanAt.timeIntervalSince1970 * 1000)
        cache.scanSinceKey = range.scanSinceKey
        cache.scanUntilKey = range.scanUntilKey
        cache.timeZoneIdentifier = options.calendar.timeZone.identifier
        cache.roots = roots
        cache.codexScanCatchUpPending = true
        cache.codexPreviousReport = CostUsageCodexPreviousReport(
            report: establishedReport,
            cache: cache,
            reportSinceKey: range.sinceKey,
            reportUntilKey: range.untilKey)
        cache.lastScanUnixMs = Int64(freshScanAt.timeIntervalSince1970 * 1000)
        cache.days = [currentDayKey: ["gpt-5.4": [20, 0, 0]]]
        cache.files[currentURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: currentMetadata.mtimeUnixMs,
            size: currentMetadata.size,
            days: cache.days,
            parsedBytes: currentMetadata.size,
            codexRows: [CostUsageScanner.CodexUsageRow(
                day: currentDayKey,
                model: "gpt-5.4",
                turnID: "fresh-current-day",
                eventIndex: 0,
                input: 20,
                cached: 0,
                output: 0,
                knownCostNanos: 2_000_000_000,
                pricingModel: "gpt-5.4",
                pricingMode: "standard")],
            codexScanFileId: currentMetadata.fileId,
            codexScanTargetSize: currentMetadata.size,
            codexScanComplete: true)
        cache.files[olderURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: olderMetadata.mtimeUnixMs,
            size: olderMetadata.size,
            days: ["2026-02-07": ["gpt-5.4": [7, 0, 0]]],
            parsedBytes: 0,
            codexScanFileId: olderMetadata.fileId,
            codexScanTargetSize: olderMetadata.size,
            codexScanComplete: false)
        cache.codexSessionDiscovery = Self.completeMetadataDiscovery(
            roots: CostUsageScanner.codexSessionsRoots(options: options),
            filePaths: [currentURL.path, olderURL.path])
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: options.calendar)

        let persisted = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(persisted.codexSessionDiscovery?.isComplete == false)
        #expect(persisted.codexSessionDiscovery?.generation == nil)
        #expect(persisted.codexSessionDiscovery?.nextFileIndex == 0)
        #expect(persisted.codexSessionDiscovery?.nextDirectoryIndex
            == persisted.codexSessionDiscovery?.directoryPaths.count)
        #expect(CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: persisted,
            roots: CostUsageScanner.codexSessionsRoots(options: options),
            dayKey: currentDayKey,
            calendar: options.calendar))

        let published = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 30,
            includePiSessions: false,
            scannerOptions: options)

        #expect(published?.snapshot.daily.map(\.date) == ["2026-04-07", currentDayKey])
        #expect(published?.snapshot.daily.map(\.totalTokens) == [10, 20])
        #expect(published?.snapshot.last30DaysTokens == 30)
        #expect(published?.snapshot.last30DaysCostUSD == 5)
        #expect(published?.snapshot.updatedAt == freshScanAt)
        #expect(published?.staleSnapshotUpdatedAt == oldScanAt)

        let yesterday = try env.makeLocalNoon(year: 2026, month: 4, day: 7)
        _ = try env.writeCodexSessionFile(
            day: yesterday,
            filename: "uncached-resumed-session.jsonl",
            contents: "{}\n")
        cache.lastScanUnixMs += 1000
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: options.calendar)
        let adjacentPartitionBlocked = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 30,
            includePiSessions: false,
            scannerOptions: options)

        #expect(adjacentPartitionBlocked?.snapshot.daily.map(\.totalTokens) == [10, 5])
        #expect(adjacentPartitionBlocked?.snapshot.updatedAt == oldScanAt)

        cache.lastScanUnixMs += 1000
        cache.files[currentURL.path]?.codexScanComplete = false
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: options.calendar)
        let blocked = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 30,
            includePiSessions: false,
            scannerOptions: options)

        #expect(blocked?.snapshot.daily.map(\.totalTokens) == [10, 5])
        #expect(blocked?.snapshot.last30DaysTokens == 15)
        #expect(blocked?.snapshot.last30DaysCostUSD == 4)
        #expect(blocked?.snapshot.updatedAt == oldScanAt)
    }

    @Test
    func `verified current day publishes while historical catch up has no baseline`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let olderDay = try env.makeLocalNoon(year: 2026, month: 4, day: 1)
        let currentDayKey = "2026-04-08"
        let currentURL = try env.writeCodexSessionFile(
            day: now,
            filename: "current.jsonl",
            contents: "{}\n")
        let olderURL = try env.writeCodexSessionFile(
            day: olderDay,
            filename: "older.jsonl",
            contents: "{}\n")
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: currentURL.path)
        try FileManager.default.setAttributes([.modificationDate: olderDay], ofItemAtPath: olderURL.path)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let range = CostUsageScanner.CostUsageDayRange(
            since: options.calendar.date(byAdding: .day, value: -29, to: now) ?? now,
            until: now,
            calendar: options.calendar)
        let currentMetadata = CostUsageScanner.codexFileMetadata(fileURL: currentURL)
        let olderMetadata = CostUsageScanner.codexFileMetadata(fileURL: olderURL)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)

        var cache = CostUsageCache()
        cache.lastScanUnixMs = Int64(now.timeIntervalSince1970 * 1000)
        cache.scanSinceKey = range.scanSinceKey
        cache.scanUntilKey = range.scanUntilKey
        cache.timeZoneIdentifier = options.calendar.timeZone.identifier
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.codexProjectMetadataVersion = CostUsageScanner.codexProjectMetadataVersion
        cache.codexScanCatchUpPending = true
        cache.days = [currentDayKey: ["gpt-5.4": [20, 0, 0]]]
        cache.files[currentURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: currentMetadata.mtimeUnixMs,
            size: currentMetadata.size,
            days: cache.days,
            parsedBytes: currentMetadata.size,
            codexRows: [CostUsageScanner.CodexUsageRow(
                day: currentDayKey,
                model: "gpt-5.4",
                turnID: "verified-current-day",
                eventIndex: 0,
                input: 20,
                cached: 0,
                output: 0,
                knownCostNanos: 2_000_000_000,
                pricingModel: "gpt-5.4",
                pricingMode: "standard")],
            codexScanFileId: currentMetadata.fileId,
            codexScanTargetSize: currentMetadata.size,
            codexScanComplete: true)
        cache.files[olderURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: olderMetadata.mtimeUnixMs,
            size: olderMetadata.size,
            days: ["2026-04-01": ["gpt-5.4": [7, 0, 0]]],
            parsedBytes: 0,
            codexScanFileId: olderMetadata.fileId,
            codexScanTargetSize: olderMetadata.size,
            codexScanComplete: false)
        cache.codexSessionDiscovery = Self.completeMetadataDiscovery(
            roots: roots,
            filePaths: [currentURL.path, olderURL.path])
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: options.calendar)

        // The production-default Pi merge must not add either current or historical rows
        // to a native recovery snapshot whose proof covers only the native current day.
        try Self.writePiCodexSessionFile(env: env, day: now, tokens: 165)
        let piOptions = PiSessionCostScanner.Options(
            piSessionsRoot: env.piSessionsRoot,
            cacheRoot: env.cacheRoot,
            refreshMinIntervalSeconds: 0)
        _ = PiSessionCostScanner.loadDailyReport(
            provider: .codex,
            since: olderDay,
            until: now,
            now: now,
            options: piOptions)

        let projection = await CostUsageStoreAccess.readCodexReportProjection(
            cacheRoot: env.cacheRoot,
            calendar: options.calendar)
        #expect(projection.verifiedDayAggregates.isEmpty)
        #expect(projection.cache.codexPreviousReport == nil)
        #expect(CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: projection.cache,
            roots: roots,
            dayKey: currentDayKey,
            calendar: options.calendar))
        let projected = CostUsageCodexReportProjectionBuilder.build(
            projection: projection,
            roots: roots,
            range: range,
            cacheRoot: options.cacheRoot,
            includeBreakdowns: false)
        #expect(projected.report.data.map(\.date) == ["2026-04-01", currentDayKey])
        #expect(projected.report.data.first(where: { $0.date == currentDayKey })?.costUSD == 2)

        let published = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 30,
            scannerOptions: options)

        #expect(published?.snapshot.daily.map(\.date) == [currentDayKey])
        #expect(published?.snapshot.daily.first?.totalTokens == 20)
        #expect(published?.snapshot.daily.first?.costUSD == 2)
        #expect(published?.snapshot.last30DaysCostUSD == 2)
        #expect(published?.snapshot.historyCoverageIsEstablished == false)
        #expect(published?.currentDayIsFullyVerified == true)

        let handle = try FileHandle(forWritingTo: currentURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"changed\":true}\n".utf8))
        try handle.close()
        let blocked = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: now,
            historyDays: 30,
            scannerOptions: options)
        #expect(blocked == nil)
    }

    @Test
    func `bounded refresh advances metadata inventory without session head discovery`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let oldDay = try env.makeLocalNoon(year: 2026, month: 2, day: 7)
        let currentURL = try env.writeCodexSessionFile(
            day: now,
            filename: "current.jsonl",
            contents: "{}\n")
        let olderURL = try env.writeCodexSessionFile(
            day: oldDay,
            filename: "older.jsonl",
            contents: "{}\n")
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            maxCodexScanBytesPerRefresh: 64 * 1024,
            useCodexCatchUpWorkingSet: true)
        options.refreshMinIntervalSeconds = 0
        let roots = CostUsageScanner.codexSessionsRoots(options: options)

        var cache = CostUsageCache()
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.codexSessionDiscovery = Self.incompleteMetadataDiscovery(
            roots: roots,
            filePaths: [currentURL.path, olderURL.path])
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache, calendar: options.calendar)

        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: now,
            until: now,
            now: now,
            options: options)

        let persisted = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let discovery = try #require(persisted.codexSessionDiscovery)
        #expect(discovery.isComplete == false)
        #expect(discovery.generation == nil)
        #expect(discovery.nextFileIndex == 0)
        #expect(discovery.nextDirectoryIndex == discovery.directoryPaths.count)
        #expect(Set(discovery.directoryPaths) == Set(discovery.directoryStamps.keys))
        #expect(Set([currentURL.path, olderURL.path]).isSubset(of: Set(discovery.filePaths)))

        var backloggedCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        backloggedCache.codexScanCatchUpPending = true
        backloggedCache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: "2026-02-07",
            rootPaths: roots.map(\.path),
            pendingFilePaths: (0...CostUsageScanner.codexCatchUpScanCandidateLimit).map {
                env.codexSessionsRoot.appendingPathComponent("historical-backlog-\($0).jsonl").path
            })
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: backloggedCache,
            calendar: options.calendar)

        let addedURL = try env.writeCodexSessionFile(
            day: oldDay,
            filename: "added-after-inventory.jsonl",
            contents: env.jsonl([
                [
                    "type": "turn_context",
                    "timestamp": env.isoString(for: now),
                    "payload": ["model": "openai/gpt-5.4"],
                ],
                [
                    "type": "event_msg",
                    "timestamp": env.isoString(for: now.addingTimeInterval(1)),
                    "payload": [
                        "type": "token_count",
                        "info": [
                            "last_token_usage": [
                                "input_tokens": 9,
                                "cached_input_tokens": 0,
                                "output_tokens": 0,
                            ],
                            "model": "openai/gpt-5.4",
                        ],
                    ],
                ],
            ]))
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: now,
            until: now,
            now: now.addingTimeInterval(1),
            options: options)

        let rebuilt = try #require(CostUsageStoreAccess.read(cacheRoot: env.cacheRoot).codexSessionDiscovery)
        #expect(rebuilt.nextDirectoryIndex == rebuilt.directoryPaths.count)
        #expect(Set(rebuilt.directoryPaths) == Set(rebuilt.directoryStamps.keys))
        #expect(rebuilt.filePaths.contains(addedURL.path))
        let queuedAfterBacklog = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
            .codexActiveLookbackState?.pendingFilePaths
        #expect(queuedAfterBacklog?.first == addedURL.path)

        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: now,
            until: now,
            now: now.addingTimeInterval(2),
            options: options)

        let recoveredCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(recoveredCache.files[addedURL.path]?.codexScanComplete == true)
        #expect(recoveredCache.files[addedURL.path]?.days["2026-04-08"]?["gpt-5.4"]?.first == 9)
        #expect(recoveredCache.codexActiveLookbackState?.pendingFilePaths.contains(addedURL.path) != true)
        #expect(CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: recoveredCache,
            roots: roots,
            dayKey: "2026-04-08",
            calendar: options.calendar))
    }

    @Test
    func `metadata inventory resumes legacy cursors and begins a second bounded sweep`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let oldDay = try env.makeLocalNoon(year: 2026, month: 4, day: 5)
        func initialSession(turnID: String) throws -> String {
            try env.jsonl([
                [
                    "type": "turn_context",
                    "timestamp": env.isoString(for: oldDay),
                    "payload": ["model": "openai/gpt-5.4"],
                ],
                [
                    "type": "event_msg",
                    "timestamp": env.isoString(for: oldDay.addingTimeInterval(1)),
                    "payload": [
                        "type": "token_count",
                        "turn_id": turnID,
                        "info": [
                            "last_token_usage": [
                                "input_tokens": 1,
                                "cached_input_tokens": 0,
                                "output_tokens": 0,
                            ],
                            "model": "openai/gpt-5.4",
                        ],
                    ],
                ],
            ])
        }
        let firstURL = try env.writeCodexSessionFile(
            day: oldDay,
            filename: "legacy-cursor-first.jsonl",
            contents: initialSession(turnID: "first-old"))
        let secondURL = try env.writeCodexSessionFile(
            day: oldDay,
            filename: "legacy-cursor-second.jsonl",
            contents: initialSession(turnID: "second-old"))
        try FileManager.default.setAttributes([.modificationDate: oldDay], ofItemAtPath: firstURL.path)
        try FileManager.default.setAttributes([.modificationDate: oldDay], ofItemAtPath: secondURL.path)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            useCodexCatchUpWorkingSet: true)
        options.refreshMinIntervalSeconds = 0

        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: oldDay,
            until: now,
            now: now,
            options: options)
        var legacyCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        var legacyDiscovery = try #require(legacyCache.codexSessionDiscovery)
        legacyDiscovery.metadataCandidateIndex = nil
        legacyDiscovery.nextFileIndex = legacyDiscovery.filePaths.count
        legacyCache.codexSessionDiscovery = legacyDiscovery
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: legacyCache,
            calendar: options.calendar)

        func appendCurrentUsage(to fileURL: URL, turnID: String, tokens: Int) throws {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(env.jsonl([[
                "type": "event_msg",
                "timestamp": env.isoString(for: now.addingTimeInterval(TimeInterval(tokens))),
                "payload": [
                    "type": "token_count",
                    "turn_id": turnID,
                    "info": [
                        "last_token_usage": [
                            "input_tokens": tokens,
                            "cached_input_tokens": 0,
                            "output_tokens": 0,
                        ],
                        "model": "openai/gpt-5.4",
                    ],
                ],
            ]]).utf8))
            try handle.close()
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: fileURL.path)
        }

        try appendCurrentUsage(to: firstURL, turnID: "first-current", tokens: 9)
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: now,
            until: now,
            now: now.addingTimeInterval(20),
            options: options)
        let afterLegacyCursor = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(afterLegacyCursor.files[firstURL.path]?.days["2026-04-08"]?["gpt-5.4"]?.first == 9)
        #expect(afterLegacyCursor.codexSessionDiscovery?.metadataCandidateIndex
            == afterLegacyCursor.codexSessionDiscovery?.filePaths.count)

        try appendCurrentUsage(to: secondURL, turnID: "second-current", tokens: 11)
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: now,
            until: now,
            now: now.addingTimeInterval(30),
            options: options)
        let afterSecondSweep = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(afterSecondSweep.files[secondURL.path]?.days["2026-04-08"]?["gpt-5.4"]?.first == 11)
        #expect(afterSecondSweep.codexSessionDiscovery?.metadataCandidateIndex
            == afterSecondSweep.codexSessionDiscovery?.filePaths.count)
    }

    @Test
    func `metadata sweep applies completed historical append and deletion across refreshes`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let historicalDay = try env.makeLocalNoon(year: 2026, month: 4, day: 5)
        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        func session(turnID: String, input: Int) throws -> String {
            try env.jsonl([
                [
                    "type": "turn_context",
                    "timestamp": env.isoString(for: historicalDay),
                    "payload": ["model": "openai/gpt-5.4"],
                ],
                [
                    "type": "event_msg",
                    "timestamp": env.isoString(for: historicalDay.addingTimeInterval(1)),
                    "payload": [
                        "type": "token_count",
                        "turn_id": turnID,
                        "info": [
                            "last_token_usage": [
                                "input_tokens": input,
                                "cached_input_tokens": 0,
                                "output_tokens": 0,
                            ],
                            "model": "openai/gpt-5.4",
                        ],
                    ],
                ],
            ])
        }
        let appendedURL = try env.writeCodexSessionFile(
            day: historicalDay,
            filename: "historical-append.jsonl",
            contents: session(turnID: "initial-append", input: 3))
        let deletedURL = try env.writeCodexSessionFile(
            day: historicalDay,
            filename: "historical-delete.jsonl",
            contents: session(turnID: "initial-delete", input: 5))
        try FileManager.default.setAttributes([.modificationDate: historicalDay], ofItemAtPath: appendedURL.path)
        try FileManager.default.setAttributes([.modificationDate: historicalDay], ofItemAtPath: deletedURL.path)

        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            useCodexCatchUpWorkingSet: true)
        options.refreshMinIntervalSeconds = 0
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: now,
            now: now,
            options: options)
        let initial = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(initial.codexSessionDiscovery?.metadataInventoryEstablished == true)
        #expect(initial.files[appendedURL.path]?.days["2026-04-05"]?["gpt-5.4"]?.first == 3)
        #expect(initial.files[deletedURL.path]?.days["2026-04-05"]?["gpt-5.4"]?.first == 5)

        let handle = try FileHandle(forWritingTo: appendedURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(session(turnID: "historical-append", input: 7).utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: historicalDay], ofItemAtPath: appendedURL.path)
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: now,
            now: now.addingTimeInterval(10),
            options: options)
        let afterAppend = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(afterAppend.files[appendedURL.path]?.days["2026-04-05"]?["gpt-5.4"]?.first == 10)

        try FileManager.default.removeItem(at: deletedURL)
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: historicalDay,
            until: now,
            now: now.addingTimeInterval(20),
            options: options)
        let afterDeletion = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(afterDeletion.files[deletedURL.path] == nil)
        #expect(afterDeletion.files[appendedURL.path]?.days["2026-04-05"]?["gpt-5.4"]?.first == 10)
    }

    @Test
    func `narrow refresh drains retained-window metadata overflow after cache reloads`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let historicalDay = try env.makeLocalNoon(year: 2026, month: 2, day: 8)
        let wideSince = try env.makeLocalNoon(year: 2025, month: 4, day: 9)
        let narrowSince = try env.makeLocalNoon(year: 2026, month: 3, day: 10)

        func session(day: Date, turnID: String, input: Int) throws -> String {
            try env.jsonl([[
                "type": "event_msg",
                "timestamp": env.isoString(for: day),
                "payload": [
                    "type": "token_count",
                    "turn_id": turnID,
                    "info": [
                        "last_token_usage": [
                            "input_tokens": input,
                            "cached_input_tokens": 0,
                            "output_tokens": 0,
                        ],
                        "model": "openai/gpt-5.4",
                    ],
                ],
            ]])
        }

        _ = try env.writeCodexSessionFile(
            day: now,
            filename: "current.jsonl",
            contents: session(day: now, turnID: "current", input: 2))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            useCodexCatchUpWorkingSet: true)
        options.refreshMinIntervalSeconds = 0
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: wideSince,
            until: now,
            now: now,
            options: options)

        // Six files deliberately exceed the four-path immediate hydration cap. The overflow
        // is persisted and drained by later refreshes, which reload the cache from SQLite.
        let historicalURLs = try (0..<6).map { index in
            let url = try env.writeCodexSessionFile(
                day: historicalDay,
                filename: "new-retained-history-\(index).jsonl",
                contents: session(
                    day: historicalDay,
                    turnID: "historical-\(index)",
                    input: 7))
            try FileManager.default.setAttributes(
                [.modificationDate: historicalDay],
                ofItemAtPath: url.path)
            return url
        }

        var afterNarrowRefresh = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        for pass in 1...12 where !historicalURLs.allSatisfy({
            afterNarrowRefresh.files[$0.path] != nil
        }) {
            _ = CostUsageScanner.loadDailyReport(
                provider: .codex,
                since: narrowSince,
                until: now,
                now: now.addingTimeInterval(TimeInterval(pass * 10)),
                options: options)
            afterNarrowRefresh = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        }
        #expect(afterNarrowRefresh.scanSinceKey == "2025-04-10")
        #expect(historicalURLs.allSatisfy {
            afterNarrowRefresh.files[$0.path]?.days["2026-02-08"]?["gpt-5.4"]?.first == 7
        })

        let wideReport = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: wideSince,
            until: now,
            now: now.addingTimeInterval(20),
            options: options)
        #expect(wideReport.data.first(where: { $0.date == "2026-02-08" })?.totalTokens == 42)
    }

    @Test
    func `current day proof rejects an appended cached session from an older partition`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let oldDay = try env.makeLocalNoon(year: 2026, month: 4, day: 5)
        let currentURL = try env.writeCodexSessionFile(
            day: now,
            filename: "current.jsonl",
            contents: "{}\n")
        let resumedURL = try env.writeCodexSessionFile(
            day: oldDay,
            filename: "resumed.jsonl",
            contents: "{}\n")
        let historicalUncachedURL = try env.writeCodexSessionFile(
            day: oldDay,
            filename: "historical-uncached.jsonl",
            contents: "{}\n")
        try FileManager.default.setAttributes([.modificationDate: oldDay], ofItemAtPath: resumedURL.path)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDay],
            ofItemAtPath: historicalUncachedURL.path)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let currentMetadata = CostUsageScanner.codexFileMetadata(fileURL: currentURL)
        let resumedMetadata = CostUsageScanner.codexFileMetadata(fileURL: resumedURL)

        var cache = CostUsageCache()
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.codexSessionDiscovery = Self.completeMetadataDiscovery(
            roots: CostUsageScanner.codexSessionsRoots(options: options),
            filePaths: [currentURL.path, resumedURL.path, historicalUncachedURL.path])
        cache.files[currentURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: currentMetadata.mtimeUnixMs,
            size: currentMetadata.size,
            days: ["2026-04-08": ["gpt-5.4": [1, 0, 0]]],
            parsedBytes: currentMetadata.size,
            codexScanFileId: currentMetadata.fileId,
            codexScanTargetSize: currentMetadata.size,
            codexScanComplete: true)
        cache.files[resumedURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: resumedMetadata.mtimeUnixMs,
            size: resumedMetadata.size,
            days: ["2026-04-05": ["gpt-5.4": [1, 0, 0]]],
            parsedBytes: resumedMetadata.size,
            codexScanFileId: resumedMetadata.fileId,
            codexScanTargetSize: resumedMetadata.size,
            codexScanComplete: true)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
        #expect(CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: cache,
            roots: roots,
            dayKey: "2026-04-08",
            calendar: options.calendar))

        let handle = try FileHandle(forWritingTo: resumedURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{}\n".utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: resumedURL.path)
        #expect(!CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: cache,
            roots: roots,
            dayKey: "2026-04-08",
            calendar: options.calendar))
    }

    @Test
    func `current day proof rejects a new session in an older partition`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let oldDay = try env.makeLocalNoon(year: 2026, month: 4, day: 5)
        let currentURL = try env.writeCodexSessionFile(
            day: now,
            filename: "current.jsonl",
            contents: "{}\n")
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let currentMetadata = CostUsageScanner.codexFileMetadata(fileURL: currentURL)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)

        var cache = CostUsageCache()
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.files[currentURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: currentMetadata.mtimeUnixMs,
            size: currentMetadata.size,
            days: ["2026-04-08": ["gpt-5.4": [1, 0, 0]]],
            parsedBytes: currentMetadata.size,
            codexScanFileId: currentMetadata.fileId,
            codexScanTargetSize: currentMetadata.size,
            codexScanComplete: true)
        cache.codexSessionDiscovery = Self.completeMetadataDiscovery(
            roots: roots,
            filePaths: [currentURL.path])
        #expect(CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: cache,
            roots: roots,
            dayKey: "2026-04-08",
            calendar: options.calendar))

        let newOldPartitionURL = try env.writeCodexSessionFile(
            day: oldDay,
            filename: "new-in-old-partition.jsonl",
            contents: "{}\n")
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: newOldPartitionURL.path)
        #expect(!CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: cache,
            roots: roots,
            dayKey: "2026-04-08",
            calendar: options.calendar))
    }

    @Test
    func `current day proof accepts an integrity checked append after the indexed snapshot`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let currentURL = try env.writeCodexSessionFile(
            day: now,
            filename: "active.jsonl",
            contents: "{\"indexed\":true}\n")
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let indexedMetadata = CostUsageScanner.codexFileMetadata(fileURL: currentURL)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)

        var cache = CostUsageCache()
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.files[currentURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: indexedMetadata.mtimeUnixMs,
            size: indexedMetadata.size,
            days: ["2026-04-08": ["gpt-5.4": [1, 0, 0]]],
            parsedBytes: indexedMetadata.size,
            codexTokenIndexAnchor: CostUsageScanner.codexTokenIndexAnchor(
                fileURL: currentURL,
                indexedBytes: indexedMetadata.size),
            codexScanFileId: indexedMetadata.fileId,
            codexScanTargetSize: indexedMetadata.size,
            codexScanComplete: true)
        cache.codexSessionDiscovery = Self.completeMetadataDiscovery(
            roots: roots,
            filePaths: [currentURL.path])

        let handle = try FileHandle(forWritingTo: currentURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"new\":true}\n".utf8))
        try handle.close()

        #expect(CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: cache,
            roots: roots,
            dayKey: "2026-04-08",
            calendar: options.calendar))

        let rewriteHandle = try FileHandle(forWritingTo: currentURL)
        try rewriteHandle.seek(toOffset: 0)
        try rewriteHandle.write(contentsOf: Data("X".utf8))
        try rewriteHandle.close()

        #expect(!CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: cache,
            roots: roots,
            dayKey: "2026-04-08",
            calendar: options.calendar))
    }

    @Test
    func `current day proof accepts a fully indexed file still queued for historical migration`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let currentURL = try env.writeCodexSessionFile(
            day: now,
            filename: "current-pending.jsonl",
            contents: "{}\n")
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let metadata = CostUsageScanner.codexFileMetadata(fileURL: currentURL)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)

        var cache = CostUsageCache()
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.files[currentURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: metadata.mtimeUnixMs,
            size: metadata.size,
            days: ["2026-04-08": ["gpt-5.4": [1, 0, 0]]],
            parsedBytes: metadata.size,
            codexTokenIndexAnchor: CostUsageScanner.codexTokenIndexAnchor(
                fileURL: currentURL,
                indexedBytes: metadata.size),
            codexScanFileId: metadata.fileId,
            codexScanTargetSize: metadata.size,
            codexScanComplete: true)
        cache.codexSessionDiscovery = Self.completeMetadataDiscovery(
            roots: roots,
            filePaths: [currentURL.path])
        cache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: "2025-04-08",
            rootPaths: roots.map(\.path),
            pendingFilePaths: [currentURL.path])

        #expect(CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: cache,
            roots: roots,
            dayKey: "2026-04-08",
            calendar: options.calendar))

        cache.files[currentURL.path]?.codexScanComplete = false
        #expect(!CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: cache,
            roots: roots,
            dayKey: "2026-04-08",
            calendar: options.calendar))
    }

    @Test
    func `current day proof ignores an unchanged uncached file in the adjacent partition`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let now = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let yesterday = try env.makeLocalNoon(year: 2026, month: 4, day: 7)
        let currentURL = try env.writeCodexSessionFile(
            day: now,
            filename: "current.jsonl",
            contents: "{}\n")
        let adjacentURL = try env.writeCodexSessionFile(
            day: yesterday,
            filename: "adjacent.jsonl",
            contents: "{}\n")
        try FileManager.default.setAttributes(
            [.modificationDate: yesterday],
            ofItemAtPath: adjacentURL.path)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let metadata = CostUsageScanner.codexFileMetadata(fileURL: currentURL)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)

        var cache = CostUsageCache()
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.files[currentURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: metadata.mtimeUnixMs,
            size: metadata.size,
            days: ["2026-04-08": ["gpt-5.4": [1, 0, 0]]],
            parsedBytes: metadata.size,
            codexTokenIndexAnchor: CostUsageScanner.codexTokenIndexAnchor(
                fileURL: currentURL,
                indexedBytes: metadata.size),
            codexScanFileId: metadata.fileId,
            codexScanTargetSize: metadata.size,
            codexScanComplete: true)
        cache.codexSessionDiscovery = Self.completeMetadataDiscovery(
            roots: roots,
            filePaths: [currentURL.path, adjacentURL.path])
        cache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: "2025-04-08",
            rootPaths: roots.map(\.path),
            pendingFilePaths: [adjacentURL.path])

        #expect(CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: cache,
            roots: roots,
            dayKey: "2026-04-08",
            calendar: options.calendar))

        let handle = try FileHandle(forWritingTo: adjacentURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{}\n".utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: adjacentURL.path)

        #expect(!CostUsageScanner.codexCurrentDayProjectionCanPublish(
            cache: cache,
            roots: roots,
            dayKey: "2026-04-08",
            calendar: options.calendar))
    }

    @Test
    func `cached codex token snapshot keeps the cache scan time as updatedAt`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "cached.jsonl",
            tokens: 42)

        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            scannerOptions: options)

        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(cache.lastScanUnixMs > 0)
        let scanTime = Date(timeIntervalSince1970: TimeInterval(cache.lastScanUnixMs) / 1000)

        let hydratedAt = day.addingTimeInterval(50 * 60)
        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: hydratedAt,
            historyDays: 1,
            scannerOptions: options)

        #expect(cached?.snapshot.updatedAt == scanTime)
        #expect(cached?.snapshot.updatedAt != hydratedAt)
        #expect(cached?.lastRefreshAt == scanTime)
    }

    @Test
    func `cached codex token snapshot keeps the oldest scan time when pi sessions merge`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "cached.jsonl",
            tokens: 42)
        try Self.writePiCodexSessionFile(env: env, day: day, tokens: 165)

        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let piOptions = PiSessionCostScanner.Options(
            piSessionsRoot: env.piSessionsRoot,
            cacheRoot: env.cacheRoot,
            refreshMinIntervalSeconds: 0)
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            refreshPricingInBackground: false,
            scannerOptions: options,
            piScannerOptions: piOptions)

        let nativeCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        var piCache = PiSessionCostCacheIO.load(cacheRoot: env.cacheRoot)
        #expect(nativeCache.lastScanUnixMs > 0)
        #expect(piCache.lastScanUnixMs > 0)
        piCache.lastScanUnixMs = nativeCache.lastScanUnixMs - 30 * 60 * 1000
        PiSessionCostCacheIO.save(cache: piCache, cacheRoot: env.cacheRoot)
        let oldestScanTime = Date(timeIntervalSince1970: TimeInterval(piCache.lastScanUnixMs) / 1000)

        let hydratedAt = day.addingTimeInterval(50 * 60)
        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: hydratedAt,
            historyDays: 1,
            scannerOptions: options)

        #expect(cached?.snapshot.sessionTokens == 207)
        #expect(cached?.snapshot.updatedAt == oldestScanTime)
        #expect(cached?.snapshot.updatedAt != hydratedAt)
        #expect(cached?.lastRefreshAt == nil)
    }

    @Test
    func `cached codex token snapshot keeps pi scan time when only pi sessions exist`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writePiCodexSessionFile(env: env, day: day, tokens: 165)

        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let piOptions = PiSessionCostScanner.Options(
            piSessionsRoot: env.piSessionsRoot,
            cacheRoot: env.cacheRoot,
            refreshMinIntervalSeconds: 0)
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            refreshPricingInBackground: false,
            scannerOptions: options,
            piScannerOptions: piOptions)

        let piCache = PiSessionCostCacheIO.load(cacheRoot: env.cacheRoot)
        #expect(piCache.lastScanUnixMs > 0)
        let piScanTime = Date(timeIntervalSince1970: TimeInterval(piCache.lastScanUnixMs) / 1000)

        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: day.addingTimeInterval(50 * 60),
            historyDays: 1,
            scannerOptions: options)

        #expect(cached?.snapshot.sessionTokens == 165)
        #expect(cached?.snapshot.updatedAt == piScanTime)
        #expect(cached?.lastRefreshAt == nil)
    }

    @Test
    func `cached codex token snapshot keeps native scan time when pi cache lacks one`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "cached.jsonl",
            tokens: 42)
        try Self.writePiCodexSessionFile(env: env, day: day, tokens: 165)

        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let piOptions = PiSessionCostScanner.Options(
            piSessionsRoot: env.piSessionsRoot,
            cacheRoot: env.cacheRoot,
            refreshMinIntervalSeconds: 0)
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            refreshPricingInBackground: false,
            scannerOptions: options,
            piScannerOptions: piOptions)

        var piCache = PiSessionCostCacheIO.load(cacheRoot: env.cacheRoot)
        piCache.lastScanUnixMs = 0
        PiSessionCostCacheIO.save(cache: piCache, cacheRoot: env.cacheRoot)

        let nativeCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(nativeCache.lastScanUnixMs > 0)
        let nativeScanTime = Date(
            timeIntervalSince1970: TimeInterval(nativeCache.lastScanUnixMs) / 1000)

        let hydratedAt = day.addingTimeInterval(50 * 60)
        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: hydratedAt,
            historyDays: 1,
            scannerOptions: options)

        #expect(cached?.sessionTokens == 207)
        #expect(cached?.updatedAt == nativeScanTime)
        #expect(cached?.updatedAt != hydratedAt)
    }

    @Test
    func `cached codex token snapshot refuses expanded or managed scopes`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "cached.jsonl",
            tokens: 42)

        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            scannerOptions: options)

        let expanded = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: day,
            historyDays: 7,
            scannerOptions: options)
        let managed = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: day,
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 1,
            scannerOptions: options)
        let scopedFetcher = CostUsageFetcher(scannerOptions: options)
        let allowedManaged = await scopedFetcher.loadCachedCodexTokenSnapshotResult(
            now: day,
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 1,
            allowScopedCodexHome: true)

        #expect(expanded == nil)
        #expect(managed == nil)
        #expect(allowedManaged?.snapshot.sessionTokens == 42)
    }

    @Test
    func `cached codex token snapshot omits projects until metadata migration`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "cached.jsonl",
            tokens: 42)

        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            scannerOptions: options)

        let current = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: day,
            historyDays: 1,
            scannerOptions: options)
        #expect(current?.projects.count == 1)

        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        cache.codexProjectMetadataVersion = nil
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache)

        let legacy = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: day,
            historyDays: 1,
            scannerOptions: options)
        #expect(legacy?.sessionTokens == 42)
        #expect(legacy?.projects.isEmpty == true)
    }

    @Test
    func `cached codex token snapshot refuses mismatched roots fingerprint`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "cached.jsonl",
            tokens: 42)

        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            scannerOptions: options)

        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        cache.roots = [env.root.appendingPathComponent("other/sessions", isDirectory: true).path: 0]
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache)

        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: day,
            historyDays: 1,
            scannerOptions: options)

        #expect(cached == nil)
    }

    @Test
    func `cached codex token snapshot merges cached pi sessions`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "cached.jsonl",
            tokens: 42)
        try Self.writePiCodexSessionFile(env: env, day: day, tokens: 165)

        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let piOptions = PiSessionCostScanner.Options(
            piSessionsRoot: env.piSessionsRoot,
            cacheRoot: env.cacheRoot,
            refreshMinIntervalSeconds: 0)
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            refreshPricingInBackground: false,
            scannerOptions: options,
            piScannerOptions: piOptions)

        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: day,
            historyDays: 1,
            scannerOptions: options)

        #expect(cached?.sessionTokens == 207)
        #expect(cached?.last30DaysTokens == 207)
        #expect(cached?.sessions.isEmpty == true)
    }

    @Test
    func `cached codex token snapshot loads cached pi sessions without native codex cache`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writePiCodexSessionFile(env: env, day: day, tokens: 165)

        let piOptions = PiSessionCostScanner.Options(
            piSessionsRoot: env.piSessionsRoot,
            cacheRoot: env.cacheRoot,
            refreshMinIntervalSeconds: 0)
        _ = PiSessionCostScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: piOptions)

        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: day,
            historyDays: 1,
            scannerOptions: CostUsageScanner.Options(
                codexSessionsRoot: env.codexSessionsRoot,
                cacheRoot: env.cacheRoot))

        #expect(cached?.sessionTokens == 165)
        #expect(cached?.last30DaysTokens == 165)
    }

    @Test
    func `cached codex token snapshot still loads pi sessions when native cache roots mismatch`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "cached.jsonl",
            tokens: 42)
        try Self.writePiCodexSessionFile(env: env, day: day, tokens: 165)

        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        let piOptions = PiSessionCostScanner.Options(
            piSessionsRoot: env.piSessionsRoot,
            cacheRoot: env.cacheRoot,
            refreshMinIntervalSeconds: 0)
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            refreshPricingInBackground: false,
            scannerOptions: options,
            piScannerOptions: piOptions)

        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        cache.roots = [env.root.appendingPathComponent("other/sessions", isDirectory: true).path: 0]
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: cache)

        let cached = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: day,
            historyDays: 1,
            scannerOptions: options)

        #expect(cached?.sessionTokens == 165)
        #expect(cached?.last30DaysTokens == 165)
    }

    @Test
    func `cached snapshot reads keep the pinned timezone instead of the current zone`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let day = try #require(losAngeles.date(from: DateComponents(
            timeZone: losAngeles.timeZone,
            year: 2026,
            month: 4,
            day: 8,
            hour: 12)))
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "cached.jsonl",
            tokens: 42)

        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot)
        options.calendar = losAngeles
        options.refreshMinIntervalSeconds = 0
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            refreshPricingInBackground: false,
            scannerOptions: options)

        let fetcher = CostUsageFetcher(scannerOptions: options)
        let pinned = await fetcher.loadCachedCodexTokenSnapshotResult(
            now: day,
            historyDays: 1,
            calendar: losAngeles)
        let travelled = await fetcher.loadCachedCodexTokenSnapshotResult(
            now: day,
            historyDays: 1,
            calendar: shanghai)

        #expect(pinned?.snapshot.sessionTokens == 42)
        #expect(pinned?.snapshot.costProvenance == .listPriceEstimate)
        #expect(travelled == nil)
    }

    @discardableResult
    private static func writeCodexSessionFile(
        homeRoot: URL,
        env: CostUsageTestEnvironment,
        day: Date,
        filename: String,
        tokens: Int) throws -> URL
    {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let dir = homeRoot
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(String(format: "%04d", comps.year ?? 1970), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", comps.month ?? 1), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", comps.day ?? 1), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = "openai/gpt-5.4"
        let url = dir.appendingPathComponent(filename, isDirectory: false)
        try env.jsonl([
            [
                "type": "turn_context",
                "timestamp": env.isoString(for: day),
                "payload": ["model": model],
            ],
            [
                "type": "event_msg",
                "timestamp": env.isoString(for: day.addingTimeInterval(1)),
                "payload": [
                    "type": "token_count",
                    "info": [
                        "last_token_usage": [
                            "input_tokens": tokens,
                            "cached_input_tokens": 0,
                            "output_tokens": 0,
                        ],
                        "model": model,
                    ],
                ],
            ],
        ]).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func writePiCodexSessionFile(
        env: CostUsageTestEnvironment,
        day: Date,
        tokens: Int) throws
    {
        _ = try env.writePiSessionFile(
            relativePath: "nested/run-0/2026-04-08T10-00-00-000Z_test.jsonl",
            contents: env.jsonl([
                [
                    "type": "message",
                    "timestamp": env.isoString(for: day),
                    "message": [
                        "role": "assistant",
                        "provider": "openai-codex",
                        "model": "openai/gpt-5.4",
                        "timestamp": Int(day.timeIntervalSince1970 * 1000),
                        "usage": [
                            "input": tokens,
                            "output": 0,
                            "cacheRead": 0,
                            "cacheWrite": 0,
                            "totalTokens": tokens,
                        ],
                    ],
                ],
            ]))
    }

    private static func completeMetadataDiscovery(
        roots: [URL],
        filePaths: [String]) -> CostUsageCodexSessionDiscovery
    {
        let rootPaths = roots.map(\.standardizedFileURL.path).sorted()
        var directoryPaths: [String] = []
        var directoryStamps: [String: CostUsageCodexSessionDiscovery.DirectoryStamp] = [:]
        var discoveredFilePaths = Set(filePaths)
        var pendingDirectories = roots
        while !pendingDirectories.isEmpty {
            let directory = pendingDirectories.removeFirst()
            let path = directory.standardizedFileURL.path
            guard directoryStamps[path] == nil else { continue }
            let items = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
            var jsonlFileCount = 0
            for item in items {
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values?.isDirectory == true {
                    pendingDirectories.append(item)
                } else if item.pathExtension.lowercased() == "jsonl" {
                    jsonlFileCount += 1
                    discoveredFilePaths.insert(item.standardizedFileURL.path)
                }
            }
            let metadata = CostUsageScanner.codexFileMetadata(fileURL: directory)
            directoryPaths.append(path)
            directoryStamps[path] = CostUsageCodexSessionDiscovery.DirectoryStamp(
                mtimeUnixMs: metadata.mtimeUnixMs,
                jsonlFileCount: jsonlFileCount)
        }
        directoryPaths.sort()
        return CostUsageCodexSessionDiscovery(
            roots: rootPaths,
            generation: nil,
            directoryStamps: directoryStamps,
            directoryPaths: directoryPaths,
            nextDirectoryIndex: directoryPaths.count,
            filePaths: discoveredFilePaths.sorted(),
            nextFileIndex: 0,
            metadataCandidateIndex: discoveredFilePaths.count,
            fileStamps: [:],
            headScan: nil,
            filePathBySessionId: [:],
            missingSessionIds: [],
            pendingSessionIds: [],
            validationDirectoryIndex: 0,
            isComplete: false)
    }

    private static func incompleteMetadataDiscovery(
        roots: [URL],
        filePaths: [String]) -> CostUsageCodexSessionDiscovery
    {
        let rootPaths = roots.map(\.standardizedFileURL.path).sorted()
        return CostUsageCodexSessionDiscovery(
            roots: rootPaths,
            generation: nil,
            directoryStamps: [:],
            directoryPaths: rootPaths,
            nextDirectoryIndex: 0,
            filePaths: filePaths,
            nextFileIndex: 0,
            fileStamps: [:],
            headScan: nil,
            filePathBySessionId: [:],
            missingSessionIds: [],
            pendingSessionIds: [],
            validationDirectoryIndex: 0,
            isComplete: false)
    }
}
