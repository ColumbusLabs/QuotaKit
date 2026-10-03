import Foundation
import Testing
@testable import CodexBarCore

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

struct CostUsageStoreBaselineTests {
    @Test
    func `unchanged Codex scan reuses one decoded snapshot`() async throws {
        let fixture = try BaselineStoreFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let writer = CostUsageStore(cacheRoot: fixture.root)
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files["/sessions/a.jsonl"] = CostUsageFileUsage(mtimeUnixMs: 1, size: 0, days: [:])
        _ = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))

        #if DEBUG
        let reads = LockIsolated(0)
        var hooks = CostUsageStoreTestHooks.current
        hooks.snapshotRead = { url in
            if url == writer.databaseURL { reads.setValue(reads.value + 1) }
        }
        let first = CostUsageStoreTestHooks.$current.withValue(hooks) {
            CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        }
        #else
        let first = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        #endif
        defer { first.release() }
        let second = first.store.syncLoadCodexScan(calendar: calendar)
        defer { second.release() }
        #expect(first.scanStamp != nil)
        #expect(second.cache.files == first.cache.files)
        #if DEBUG
        #expect(reads.value == 1)
        #endif
        var metadataUpdate = second.cache
        metadataUpdate.lastScanUnixMs += 1000
        metadataUpdate.codexPriorityTurnsCursor = Self.cursor(
            databasePath: second.store.databaseURL.path,
            lastRowID: 10)
        let writesBefore = await second.store.persistenceWriteMetricsForTesting()
        let saved = CostUsageStoreAccess.save(
            store: second.store,
            cache: metadataUpdate,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            skipIdenticalContent: true,
            expectedScanStamp: second.scanStamp,
            receipt: second.receipt,
            requireScanStamp: true)
        let writesAfter = await second.store.persistenceWriteMetricsForTesting()
        #expect(!saved.catchUpRequired)
        #expect(writesAfter.rows - writesBefore.rows == 1)
        #if DEBUG
        // The receipt carries the already decoded baseline through save.
        #expect(reads.value == 1)
        #endif
        #if DEBUG
        let third = CostUsageStoreTestHooks.$current.withValue(hooks) {
            second.store.syncLoadCodexScan(calendar: calendar)
        }
        #else
        let third = second.store.syncLoadCodexScan(calendar: calendar)
        #endif
        defer { third.release() }
        #expect(third.cache.files == second.cache.files)
        #expect(third.cache.lastScanUnixMs == metadataUpdate.lastScanUnixMs)
        #expect(third.cache.codexPriorityTurnsCursor == metadataUpdate.codexPriorityTurnsCursor)
        #if DEBUG
        #expect(reads.value == 1)
        #endif
        var changed = third.cache
        changed.files["/sessions/a.jsonl"]?.lastModel = "gpt-5"
        let changedSave = CostUsageStoreAccess.save(
            store: third.store,
            cache: changed,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            skipIdenticalContent: true,
            expectedScanStamp: third.scanStamp,
            receipt: third.receipt,
            requireScanStamp: true)
        #expect(!changedSave.catchUpRequired)
        #if DEBUG
        // Changed-content persistence also uses the loaded receipt without a second snapshot.
        #expect(reads.value == 1)
        #endif
        var otherCalendar = calendar
        otherCalendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let otherZone = third.store.syncLoadCodexScan(calendar: otherCalendar)
        defer { otherZone.release() }
        #expect(otherZone.cache.files.isEmpty)
    }

    @Test
    func `empty token history does not force a full content rewrite`() async throws {
        let fixture = try BaselineStoreFixture()
        defer { fixture.remove() }
        let calendar = Calendar(identifier: .gregorian)
        let store = CostUsageStore(cacheRoot: fixture.root)
        let path = "/sessions/empty-history.jsonl"
        var usage = CostUsageFileUsage(mtimeUnixMs: 1, size: 0, days: [:])
        usage.codexTokenSnapshots = []
        usage.codexTokenCheckpoints = []
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 1000
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files[path] = usage
        #expect(!store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01")).catchUpRequired)

        let loaded = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        defer { loaded.release() }
        #expect(loaded.cache.files[path]?.codexTokenSnapshots == [])
        var incoming = loaded.cache
        incoming.files[path]?.codexTokenSnapshots = []
        incoming.files[path]?.codexTokenCheckpoints = []
        incoming.lastScanUnixMs += 1000
        let before = await loaded.store.persistenceWriteMetricsForTesting()
        let saved = CostUsageStoreAccess.save(
            store: loaded.store,
            cache: incoming,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            skipIdenticalContent: true,
            expectedScanStamp: loaded.scanStamp,
            receipt: loaded.receipt,
            requireScanStamp: true)
        let after = await loaded.store.persistenceWriteMetricsForTesting()

        #expect(!saved.catchUpRequired)
        #expect(after.rows - before.rows == 1)
        #expect(await store.fetchTokenSnapshots(path: path).isEmpty)
    }

    #if DEBUG
    @Test(arguments: ["usage", "metadata"])
    func `external write after metadata commit invalidates retained baseline`(externalWrite: String) async throws {
        let fixture = try BaselineStoreFixture()
        defer { fixture.remove() }
        let calendar = Calendar(identifier: .gregorian)
        let store = CostUsageStore(cacheRoot: fixture.root)
        let path = "/sessions/post-commit.jsonl"
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: ["2026-08-01": ["gpt-5": [10, 2, 3]]])
        usage.parsedBytes = 100
        usage.codexScanComplete = true
        usage.codexRows = [CostUsageScanner.CodexUsageRow(
            day: "2026-08-01",
            model: "gpt-5",
            turnID: "turn-1",
            eventIndex: 0,
            input: 10,
            cached: 2,
            output: 3,
            knownCostNanos: 1200,
            pricingMode: "standard")]
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 1000
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files[path] = usage
        cache.days = usage.days
        let window = (sinceKey: "2026-08-01", untilKey: "2026-08-01")
        #expect(!store.syncSaveCodexCache(cache, calendar: calendar, requestedScanWindow: window).catchUpRequired)

        let loaded = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        defer { loaded.release() }
        var incoming = loaded.cache
        incoming.lastScanUnixMs += 1000
        var saveHooks = CostUsageStoreTestHooks.current
        saveHooks.identicalContentPostCommitCheckpoint = (store.databaseURL, {
            let sql = externalWrite == "usage"
                ? "DELETE FROM usage_rows WHERE rowid = (SELECT MIN(rowid) FROM usage_rows)"
                : "UPDATE scan_metadata SET payload = json_set(CAST(payload AS TEXT), '$.lastScanUnixMs', 12345)"
            do {
                try BaselineSQLite.execute(at: store.databaseURL, sql)
            } catch {
                Issue.record(error)
            }
        })
        let saved = CostUsageStoreTestHooks.$current.withValue(saveHooks) {
            CostUsageStoreAccess.save(
                store: loaded.store,
                cache: incoming,
                calendar: calendar,
                requestedScanWindow: window,
                skipIdenticalContent: true,
                expectedScanStamp: loaded.scanStamp,
                receipt: loaded.receipt,
                requireScanStamp: true)
        }
        #expect(!saved.catchUpRequired)

        let reads = LockIsolated(0)
        var readHooks = CostUsageStoreTestHooks.current
        readHooks.snapshotRead = { url in
            if url == store.databaseURL { reads.setValue(reads.value + 1) }
        }
        let fresh = CostUsageStoreTestHooks.$current.withValue(readHooks) {
            loaded.store.syncLoadCodexScan(calendar: calendar)
        }
        defer { fresh.release() }
        #expect(reads.value == 1)
        if externalWrite == "metadata" {
            #expect(fresh.cache.lastScanUnixMs == 12345)
        } else {
            #expect(await loaded.store.fetchUsageRows(path: path).isEmpty)
        }
    }
    #endif

    @Test
    func `released Codex baseline receipt cannot authorize a save`() throws {
        let fixture = try BaselineStoreFixture()
        defer { fixture.remove() }
        let calendar = Calendar(identifier: .gregorian)
        let store = CostUsageStore(cacheRoot: fixture.root)
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files["/sessions/a.jsonl"] = CostUsageFileUsage(mtimeUnixMs: 1, size: 0, days: [:])
        _ = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))

        let loaded = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        defer { loaded.release() }
        loaded.release()
        let refused = CostUsageStoreAccess.save(
            store: loaded.store,
            cache: loaded.cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            expectedScanStamp: loaded.scanStamp,
            receipt: loaded.receipt,
            requireScanStamp: true)

        #expect(refused.catchUpRequired)
        #expect(CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar)
            .files["/sessions/a.jsonl"] != nil)
    }

    @Test
    func `failed store operation invalidates the Codex baseline generation`() async throws {
        let fixture = try BaselineStoreFixture()
        defer { fixture.remove() }
        let calendar = Calendar(identifier: .gregorian)
        let store = CostUsageStore(cacheRoot: fixture.root)
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files["/sessions/a.jsonl"] = CostUsageFileUsage(mtimeUnixMs: 1, size: 0, days: [:])
        _ = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))

        let loaded = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        defer { loaded.release() }
        let originalStamp = try #require(loaded.scanStamp)
        let failed: Bool = await loaded.store.withDatabase(default: false) { _ in
            throw CostUsageStore.StoreError.sqlite(SQLITE_FULL)
        }
        let currentStamp = await loaded.store.currentCodexScanStamp()

        #expect(!failed)
        #expect(currentStamp?.failureGeneration != originalStamp.failureGeneration)
        let refused = CostUsageStoreAccess.save(
            store: loaded.store,
            cache: loaded.cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            expectedScanStamp: originalStamp,
            receipt: loaded.receipt,
            requireScanStamp: true)
        #expect(refused.catchUpRequired)
    }

    @Test
    func `cursor-only save preserves verified coverage refreshed in the transaction`() async throws {
        let fixture = try BaselineStoreFixture()
        defer { fixture.remove() }
        let calendar = Calendar(identifier: .gregorian)
        let writer = CostUsageStore(cacheRoot: fixture.root)
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 1000
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.codexPriorityTurnsCursor = Self.cursor(databasePath: writer.databaseURL.path, lastRowID: 10)
        cache.files["/sessions/a.jsonl"] = CostUsageFileUsage(mtimeUnixMs: 1, size: 0, days: [:])
        _ = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))

        var staleMetadata = await writer.fetchMetadata()
        staleMetadata.verifiedScanSinceDay = nil
        staleMetadata.verifiedScanUntilDay = nil
        staleMetadata.verifiedUpdatedAtUnixMs = nil
        staleMetadata.verifiedTimeZoneIdentifier = nil
        staleMetadata.verifiedRootPaths = nil
        staleMetadata.verifiedLedgerVersion = nil
        #expect(await writer.setMetadata(staleMetadata))

        let loaded = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        defer { loaded.release() }
        var changed = loaded.cache
        let advancedCursor = Self.cursor(databasePath: writer.databaseURL.path, lastRowID: 11)
        changed.codexPriorityTurnsCursor = advancedCursor
        let saved = CostUsageStoreAccess.save(
            store: loaded.store,
            cache: changed,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            skipIdenticalContent: true,
            expectedScanStamp: loaded.scanStamp,
            receipt: loaded.receipt,
            requireScanStamp: true)

        #expect(!saved.catchUpRequired)
        let currentMetadata = await loaded.store.fetchMetadata()
        #expect(currentMetadata.verifiedScanSinceDay == "2026-08-01")
        #expect(currentMetadata.verifiedScanUntilDay == "2026-08-01")
        #expect(currentMetadata.verifiedUpdatedAtUnixMs == 1000)
        #expect(currentMetadata.verifiedTimeZoneIdentifier == calendar.timeZone.identifier)
        #expect(CostUsageStoreAccess.read(cacheRoot: fixture.root, calendar: calendar)
            .codexPriorityTurnsCursor == advancedCursor)
    }

    @Test
    func `metadata refresh preserves partially hydrated token history`() async throws {
        let fixture = try BaselineStoreFixture()
        defer { fixture.remove() }
        let calendar = Calendar(identifier: .gregorian)
        let store = CostUsageStore(cacheRoot: fixture.root)
        let path = "/sessions/partial-history.jsonl"
        let snapshot = CostUsageCodexTokenSnapshot(
            timestamp: "2026-08-01T12:00:00Z",
            last: CostUsageCodexTotals(input: 10, cached: 2, output: 3),
            total: CostUsageCodexTotals(input: 100, cached: 20, output: 30),
            endOffset: 100)
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: ["2026-08-01": ["gpt-5": [10, 2, 3]]])
        usage.parsedBytes = 100
        usage.codexScanComplete = true
        usage.codexTokenTimestampsMonotonic = true
        usage.codexTokenSnapshots = [snapshot]
        usage.codexTokenCheckpoints = CostUsageScanner.codexTokenCheckpoints(for: [snapshot])
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 1000
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.codexScanCatchUpPending = false
        cache.files[path] = usage
        cache.days = usage.days
        let window = (sinceKey: "2026-08-01", untilKey: "2026-08-01")
        #expect(!store.syncSaveCodexCache(cache, calendar: calendar, requestedScanWindow: window).catchUpRequired)

        var staleMetadata = await store.fetchMetadata()
        staleMetadata.verifiedScanSinceDay = nil
        staleMetadata.verifiedScanUntilDay = nil
        staleMetadata.verifiedUpdatedAtUnixMs = nil
        staleMetadata.verifiedTimeZoneIdentifier = nil
        staleMetadata.verifiedRootPaths = nil
        staleMetadata.verifiedLedgerVersion = nil
        #expect(await store.setMetadata(staleMetadata))

        let loaded = store.syncLoadCodexScan(calendar: calendar)
        defer { loaded.release() }
        let expectedStamp = try #require(loaded.scanStamp)
        #expect(loaded.cache.files[path]?.codexTokenSnapshots == nil)
        guard case let .loaded(hydrated) = try loaded.store.syncHydrateCodexTokenSnapshots(
            paths: [path],
            receipt: #require(loaded.receipt),
            expectedScanStamp: expectedStamp)
        else {
            Issue.record("Expected the selected token history to hydrate")
            return
        }

        var incoming = loaded.cache
        let hydratedSnapshots = (hydrated[path] ?? []).map(CostUsageStore.tokenSnapshot(from:))
        incoming.files[path]?.codexTokenSnapshots = hydratedSnapshots
        incoming.files[path]?.codexTokenCheckpoints = CostUsageScanner.codexTokenCheckpoints(for: hydratedSnapshots)
        incoming.lastScanUnixMs += 1000
        func save() -> CostUsageStoreBudgetResult {
            CostUsageStoreAccess.save(
                store: loaded.store,
                cache: incoming,
                calendar: calendar,
                requestedScanWindow: window,
                skipIdenticalContent: true,
                expectedScanStamp: expectedStamp,
                receipt: loaded.receipt,
                requireScanStamp: true)
        }
        #if DEBUG
        let tokenReadPaths = LockIsolated<[String]>([])
        var hooks = CostUsageStoreTestHooks.current
        hooks.tokenSnapshotPathRead = { url, readPath in
            if url == store.databaseURL { tokenReadPaths.setValue(tokenReadPaths.value + [readPath ?? "<all>"]) }
        }
        let saved = CostUsageStoreTestHooks.$current.withValue(hooks) { save() }
        #expect(tokenReadPaths.value == [path])
        #else
        let saved = save()
        #endif

        #expect(!saved.catchUpRequired)
        let persistedSnapshots = await loaded.store.fetchTokenSnapshots(path: path)
        #expect(persistedSnapshots.map(CostUsageStore.tokenSnapshot(from:)) == [snapshot])
    }

    @Test(arguments: [false, true])
    func `trigger content writes cannot be certified as metadata-only`(duringBudgetRefresh: Bool) async throws {
        let fixture = try BaselineStoreFixture()
        defer { fixture.remove() }
        let store = CostUsageStore(cacheRoot: fixture.root)
        let path = "/sessions/triggered.jsonl"
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1000,
            size: 100,
            days: ["2026-08-01": ["gpt-5": [10, 2, 3]]])
        usage.parsedBytes = 100
        usage.codexScanComplete = true
        usage.codexRows = [CostUsageScanner.CodexUsageRow(
            day: "2026-08-01",
            model: "gpt-5",
            turnID: "turn-1",
            eventIndex: 0,
            input: 10,
            cached: 2,
            output: 3,
            knownCostNanos: 1200,
            pricingMode: "standard")]
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 1000
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files[path] = usage
        cache.days = usage.days
        let window = (sinceKey: "2026-08-01", untilKey: "2026-08-01")
        #expect(!store.syncSaveCodexCache(cache, calendar: .current, requestedScanWindow: window).catchUpRequired)

        if duringBudgetRefresh {
            var staleMetadata = await store.fetchMetadata()
            staleMetadata.verifiedScanSinceDay = nil
            staleMetadata.verifiedScanUntilDay = nil
            staleMetadata.verifiedUpdatedAtUnixMs = nil
            staleMetadata.verifiedTimeZoneIdentifier = nil
            staleMetadata.verifiedRootPaths = nil
            staleMetadata.verifiedLedgerVersion = nil
            #expect(await store.setMetadata(staleMetadata))
        }
        try BaselineSQLite.execute(at: store.databaseURL, """
        CREATE TRIGGER delete_usage_after_metadata_write
        AFTER UPDATE ON scan_metadata
        BEGIN
            DELETE FROM usage_rows WHERE rowid = (SELECT MIN(rowid) FROM usage_rows);
        END
        """)

        let loaded = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: .current)
        defer { loaded.release() }
        var incoming = loaded.cache
        incoming.lastScanUnixMs += 1000
        let saved = CostUsageStoreAccess.save(
            store: loaded.store,
            cache: incoming,
            calendar: .current,
            requestedScanWindow: window,
            skipIdenticalContent: true,
            expectedScanStamp: loaded.scanStamp,
            receipt: loaded.receipt,
            requireScanStamp: true)

        #expect(saved.catchUpRequired)
        #expect(await store.fetchUsageRows(path: path).count == 1)
        #expect(await store.rebuildCount == 0)
    }

    @Test
    func `database inode replacement invalidates a loaded Codex baseline`() async throws {
        let fixture = try BaselineStoreFixture()
        defer { fixture.remove() }
        let calendar = Calendar(identifier: .gregorian)
        let store = CostUsageStore(cacheRoot: fixture.root)
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.files["/sessions/a.jsonl"] = CostUsageFileUsage(mtimeUnixMs: 1, size: 0, days: [:])
        _ = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))

        let loaded = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        defer { loaded.release() }
        try FileManager.default.removeItem(at: store.databaseURL)
        try Data().write(to: store.databaseURL)

        let refused = CostUsageStoreAccess.save(
            store: loaded.store,
            cache: loaded.cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            expectedScanStamp: loaded.scanStamp,
            receipt: loaded.receipt,
            requireScanStamp: true)

        #expect(refused.catchUpRequired)
        #expect(await loaded.store.rebuildCount == 0)

        let reopened = loaded.store.syncLoadCodexScan(calendar: calendar)
        defer { reopened.release() }
        #expect(reopened.cache.files.isEmpty)
        #expect(reopened.scanStamp?.connectionGeneration != loaded.scanStamp?.connectionGeneration)
    }

    private static func cursor(
        databasePath: String,
        lastRowID: Int64) -> CostUsageScanner.CodexPriorityTurnsPersistedCursor
    {
        CostUsageScanner.CodexPriorityTurnsPersistedCursor(
            databasePath: databasePath,
            coverageSinceEpoch: 0,
            lastRowID: lastRowID,
            fileIdentity: nil,
            anchorRowID: 0,
            anchorDigest: "",
            turns: [:],
            requestSourcesByTurnID: [:],
            priorityCompletedModelsByTurnID: [:],
            completedModelsByTurnID: [:],
            completedTurnIDInsertionOrder: [],
            completedTurnIDInsertionOrderStartIndex: 0)
    }
}

private enum BaselineSQLite {
    enum TestError: Error {
        case sqlite(Int32)
    }

    static func execute(at url: URL, _ sql: String) throws {
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil)
        guard opened == SQLITE_OK, let database else { throw TestError.sqlite(opened) }
        defer { sqlite3_close_v2(database) }
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw TestError.sqlite(result) }
    }
}

private struct BaselineStoreFixture: Sendable {
    let root: URL

    init() throws {
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar-CostUsageBaselineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: self.root)
    }
}
