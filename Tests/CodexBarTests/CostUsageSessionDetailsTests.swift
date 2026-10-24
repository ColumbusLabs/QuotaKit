import Foundation
import Testing
@testable import CodexBarCore
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

struct CostUsageSessionDetailsTests {
    @Test
    func `ordinary summaries stay compact while selected requests reconcile to the same totals`() throws {
        let fixture = try Fixture(fileCount: 2)
        defer { fixture.remove() }
        let summaries = CostUsageScanner.buildCodexSessionBreakdownsFromCache(
            cache: fixture.cache,
            range: fixture.dayRange,
            modelsDevCatalog: ModelsDevCatalog(providers: [:]),
            modelsDevCacheRoot: fixture.root)
        #expect(summaries.count == 2)
        #expect(summaries.flatMap(\.turns).isEmpty)
        let selected = try #require(summaries.first { $0.sessionID == "session-0" })
        #expect(selected.requestDetailSource == fixture.source)

        // A different session's malformed payload must never be decoded by this inspector.
        try fixture.execute("""
        UPDATE usage_rows SET payload = x'00'
        WHERE file_id IN (SELECT id FROM files WHERE session_id != 'session-0')
        """)
        let details = try fixture.read()
        #expect(details.map(\.turnID) == ["turn-0", "turn-1"])
        #expect(details.compactMap(\.totalTokens).reduce(0, +) == selected.totalTokens)
        #expect(abs(details.compactMap(\.costUSD).reduce(0, +) - (selected.costUSD ?? -1)) < 1e-12)
        #expect(details.flatMap(\.requests).count == 2)
        #expect(selected.turns.isEmpty)
    }

    @Test
    func `request and payload budgets reject truncation`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var limits = CostUsageSessionDetailLoader.Limits()
        limits.requests = 1
        #expect(throws: CostUsageSessionDetailError.limitExceeded) { try fixture.read(limits: limits) }
        limits.requests = 2
        #expect(try fixture.read(limits: limits).count == 2)
        limits.payloadBytes = 1
        #expect(throws: CostUsageSessionDetailError.limitExceeded) { try fixture.read(limits: limits) }
    }

    @Test
    func `file metadata aggregate and fork lineage budgets are checked`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var limits = CostUsageSessionDetailLoader.Limits()
        limits.metadataBytes = 1
        #expect(throws: CostUsageSessionDetailError.limitExceeded) { try fixture.read(limits: limits) }
        limits = .init()
        limits.aggregates = 0
        #expect(throws: CostUsageSessionDetailError.limitExceeded) { try fixture.read(limits: limits) }
    }

    @Test
    func `changed source identity timestamp or schema cannot reuse the summary`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let wrongSession = CostUsageSessionDetailSource(
            databaseURL: fixture.source.databaseURL,
            sessionSource: .init(fileURL: fixture.source.sessionSource.fileURL, sessionID: "another-account"),
            parsedBytes: fixture.source.parsedBytes,
            pricingKey: fixture.source.pricingKey,
            ledgerRevision: fixture.source.ledgerRevision)
        #expect(throws: CostUsageSessionDetailError.unavailable) {
            try CostUsageSessionDetailLoader.read(
                source: wrongSession,
                lastActivity: fixture.now,
                range: fixture.range,
                timeZone: fixture.calendar.timeZone)
        }
        #expect(throws: CostUsageSessionDetailError.sourceChanged) {
            try CostUsageSessionDetailLoader.read(
                source: fixture.source,
                lastActivity: fixture.now.addingTimeInterval(1),
                range: fixture.range,
                timeZone: fixture.calendar.timeZone)
        }
        try fixture.execute("PRAGMA user_version = 1")
        #expect(throws: CostUsageSessionDetailError.sourceChanged) { try fixture.read() }
    }

    @Test
    func `missing database is not created by inspection`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("missing.sqlite")
        let source = CostUsageSessionDetailSource(
            databaseURL: database,
            sessionSource: .init(fileURL: root.appendingPathComponent("session.jsonl"), sessionID: "missing"),
            parsedBytes: nil)
        let now = Date(timeIntervalSince1970: 1_792_562_400)
        #expect(throws: CostUsageSessionDetailError.unavailable) {
            try CostUsageSessionDetailLoader.read(
                source: source,
                lastActivity: now,
                range: now..<now.addingTimeInterval(1),
                timeZone: try #require(TimeZone(identifier: "Asia/Shanghai")))
        }
        #expect(!FileManager.default.fileExists(atPath: database.path))
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test
    func `persisted priority pricing metadata matches the session summary`() throws {
        let fixture = try Fixture(priority: true)
        defer { fixture.remove() }
        let summary = try #require(CostUsageScanner.buildCodexSessionBreakdownsFromCache(
            cache: fixture.cache,
            range: fixture.dayRange,
            modelsDevCatalog: ModelsDevCatalog(providers: [:]),
            modelsDevCacheRoot: fixture.root).first)
        let details = try fixture.read()
        #expect(try #require(summary.costUSD) > 0)
        #expect(abs(details.compactMap(\.costUSD).reduce(0, +) - (summary.costUSD ?? -1)) < 1e-12)
    }

    @Test
    func `production report projection supplies a committed detail source`() throws {
        let fixture = try Fixture(fileCount: 2)
        defer { fixture.remove() }
        let projection = CostUsageStore(cacheRoot: fixture.root).syncReadCodexReportProjection(
            calendar: fixture.calendar,
            temporalRange: (fixture.dayRange.sinceKey, fixture.dayRange.untilKey))
        let report = CostUsageCodexReportProjectionBuilder.build(
            projection: projection,
            roots: [fixture.root],
            range: fixture.dayRange,
            cacheRoot: fixture.root,
            includeBreakdowns: true)
        let selected = try #require(report.sessions.first { $0.sessionID == "session-0" })
        let source = try #require(selected.requestDetailSource)
        #expect(source == fixture.source)
        #expect(source.pricingKey == projection.cache.codexPricingKey)
        #expect(source.ledgerRevision == projection.cache.files[fixture.source.sessionSource.fileURL.path]?
            .codexLedgerRevision)
        let details = try fixture.read(source: source)
        #expect(details.map(\.turnID) == ["turn-0", "turn-1"])
    }

    #if DEBUG
    @Test
    func `pricing overlay changes invalidate selected detail source`() throws {
        let overlayA = CostUsageCustomPricing(
            entries: ["fictional-selected-model": .init(input: 1, output: 1, cacheRead: 1)],
            fingerprint: "overlay-a")
        let overlayB = CostUsageCustomPricing(
            entries: ["fictional-selected-model": .init(input: 2, output: 2, cacheRead: 2)],
            fingerprint: "overlay-b")
        let fixture = try Fixture(customPricing: overlayA)
        defer { fixture.remove() }
        let projection = CostUsageStore(cacheRoot: fixture.root).syncReadCodexReportProjection(
            calendar: fixture.calendar,
            temporalRange: (fixture.dayRange.sinceKey, fixture.dayRange.untilKey))
        let report = CostUsageCodexReportProjectionBuilder.build(
            projection: projection,
            roots: [fixture.root],
            range: fixture.dayRange,
            cacheRoot: fixture.root,
            includeBreakdowns: true)
        let source = try #require(report.sessions.first?.requestDetailSource)
        var hooks = CostUsageStoreTestHooks.current
        hooks.customPricingOverlay = overlayA
        let details = try CostUsageStoreTestHooks.$current.withValue(hooks) {
            try fixture.read(source: source)
        }
        #expect(details.contains { ($0.costUSD ?? 0) > 0 })

        hooks.customPricingOverlay = overlayB
        #expect(throws: CostUsageSessionDetailError.sourceChanged) {
            try CostUsageStoreTestHooks.$current.withValue(hooks) {
                try fixture.read(source: source)
            }
        }
    }

    @Test
    func `same checkpoint row migration invalidates selected detail source`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.source
        var updatedCache = fixture.cache
        let path = source.sessionSource.fileURL.path
        var usage = try #require(updatedCache.files[path])
        var rows = try #require(usage.codexRows)
        let row = rows[0]
        rows[0] = CostUsageScanner.CodexUsageRow(
            day: row.day,
            model: row.model,
            rawModel: row.rawModel,
            turnID: row.turnID.map { $0 + "-migrated" },
            eventIndex: row.eventIndex,
            timestampUnixMs: row.timestampUnixMs,
            input: row.input,
            cached: row.cached,
            output: row.output,
            reasoning: row.reasoning,
            knownCostNanos: row.knownCostNanos,
            unpricedTokens: row.unpricedTokens,
            pricingModel: row.pricingModel,
            pricingMode: row.pricingMode,
            responseID: row.responseID,
            requestMirrorKeys: row.requestMirrorKeys)
        usage.codexRows = rows
        updatedCache.files[path] = usage
        let replacement = CostUsageStoreAccess.replace(
            cacheRoot: fixture.root,
            cache: updatedCache,
            calendar: fixture.calendar)
        #expect(!replacement.catchUpRequired)
        let current = CostUsageStore(cacheRoot: fixture.root).syncLoadCodexCache(
            calendar: fixture.calendar,
            hydratingPaths: [])
        #expect(current.files[path]?.mtimeUnixMs == Int64(fixture.now.timeIntervalSince1970 * 1000))
        #expect(current.files[path]?.parsedBytes == source.parsedBytes)
        #expect(current.files[path]?.codexLedgerRevision != source.ledgerRevision)
        #expect(throws: CostUsageSessionDetailError.sourceChanged) { try fixture.read(source: source) }
    }
    #endif

    private struct Fixture {
        let root: URL
        let now: Date
        let calendar: Calendar
        let range: Range<Date>
        let dayRange: CostUsageScanner.CostUsageDayRange
        let cache: CostUsageCache
        let source: CostUsageSessionDetailSource

        init(
            fileCount: Int = 1,
            priority: Bool = false,
            customPricing: CostUsageCustomPricing? = nil) throws
        {
            self.root = FileManager.default.temporaryDirectory.appendingPathComponent("session-details-\(UUID())")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            self.calendar = calendar
            self.now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 15)))
            let timestamp = Int64(self.now.timeIntervalSince1970 * 1000)
            let start = calendar.startOfDay(for: self.now)
            self.range = start..<start.addingTimeInterval(86400)
            self.dayRange = .init(since: self.now, until: self.now, calendar: calendar)
            let day = self.dayRange.sinceKey
            let model = priority ? "gpt-5.4" : "fictional-selected-model"
            var cache = CostUsageCache()
            cache.timeZoneIdentifier = calendar.timeZone.identifier
            for index in 0..<fileCount {
                let rows = (0..<2).map { event in
                    CostUsageScanner.CodexUsageRow(
                        day: day,
                        model: model,
                        turnID: priority ? "priority-\(event)" : "turn-\(event)",
                        eventIndex: event,
                        timestampUnixMs: timestamp + Int64(event * 1000),
                        input: 100,
                        cached: 80,
                        output: 10,
                        reasoning: 4,
                        knownCostNanos: priority || customPricing != nil ? nil : 100_000_000,
                        pricingModel: model,
                        pricingMode: priority ? "priority" : "standard")
                }
                let usage = CostUsageScanner.makeFileUsage(
                    mtimeUnixMs: Int64(self.now.timeIntervalSince1970 * 1000),
                    size: 1,
                    days: [day: [model: [200, 160, 20]]],
                    parsedBytes: 1,
                    sessionId: "session-\(index)",
                    codexRows: rows,
                    codexScanComplete: true)
                cache.files[self.root.appendingPathComponent("session-\(index).jsonl").path] = usage
                CostUsageScanner.applyFileDays(cache: &cache, fileDays: usage.days, sign: 1)
            }
            cache.codexPricingKey = CostUsageScanner.codexPricingKey(
                modelsDevArtifact: ModelsDevCache.load(cacheRoot: self.root).artifact,
                customPricing: customPricing ?? .empty)
            if let customPricing {
                #if DEBUG
                var hooks = CostUsageStoreTestHooks.current
                hooks.customPricingOverlay = customPricing
                _ = CostUsageStoreTestHooks.$current.withValue(hooks) {
                    CostUsageStoreAccess.replace(cacheRoot: self.root, cache: cache, calendar: calendar)
                }
                #else
                _ = CostUsageStoreAccess.replace(cacheRoot: self.root, cache: cache, calendar: calendar)
                #endif
            } else {
                _ = CostUsageStoreAccess.replace(cacheRoot: self.root, cache: cache, calendar: calendar)
            }
            let persisted = CostUsageStore(cacheRoot: self.root).syncLoadCodexCache(
                calendar: calendar,
                hydratingPaths: [])
            let selectedPath = self.root.appendingPathComponent("session-0.jsonl").path
            for path in cache.files.keys {
                cache.files[path]?.codexLedgerRevision = persisted.files[path]?.codexLedgerRevision
                cache.files[path]?.codexReplacementScanPending = persisted.files[path]?.codexReplacementScanPending
            }
            self.cache = cache
            self.source = .init(
                databaseURL: CostUsageStore.databaseURL(cacheRoot: self.root),
                sessionSource: .init(fileURL: URL(fileURLWithPath: selectedPath), sessionID: "session-0"),
                parsedBytes: 1,
                pricingKey: persisted.codexPricingKey,
                ledgerRevision: persisted.files[selectedPath]?.codexLedgerRevision)
        }

        func read(
            source: CostUsageSessionDetailSource? = nil,
            limits: CostUsageSessionDetailLoader.Limits = .init()) throws -> [CostUsageSessionTurn]
        {
            try CostUsageSessionDetailLoader.read(
                source: source ?? self.source,
                lastActivity: self.now,
                range: self.range,
                timeZone: self.calendar.timeZone,
                limits: limits,
                catalog: ModelsDevCatalog(providers: [:]))
        }

        func execute(_ sql: String) throws {
            var database: OpaquePointer?
            let opened = sqlite3_open_v2(self.source.databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil)
            let pointer = try #require(database)
            defer { sqlite3_close_v2(pointer) }
            #expect(opened == SQLITE_OK)
            sqlite3_busy_timeout(pointer, 5000)
            let result = sqlite3_exec(pointer, sql, nil, nil, nil)
            #expect(result == SQLITE_OK, "SQLite result: \(result)")
        }

        func remove() { try? FileManager.default.removeItem(at: self.root) }
    }
}
