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
    func `unchanged Codex scan reuses one decoded snapshot`() throws {
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
        var reads = 0
        CostUsageStore.snapshotReadForTesting = { url in
            if url == writer.databaseURL { reads += 1 }
        }
        defer { CostUsageStore.snapshotReadForTesting = nil }
        #endif
        let first = CostUsageStoreAccess.load(cacheRoot: fixture.root, calendar: calendar)
        defer { first.release() }
        let second = first.store.syncLoadCodexScan(calendar: calendar)
        defer { second.release() }
        #expect(first.scanStamp != nil)
        #expect(second.cache.files == first.cache.files)
        #if DEBUG
        #expect(reads == 1)
        #endif
        let saved = CostUsageStoreAccess.save(
            store: second.store,
            cache: second.cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            skipIdenticalContent: true,
            expectedScanStamp: second.scanStamp,
            receipt: second.receipt,
            requireScanStamp: true)
        #expect(!saved.catchUpRequired)
        #if DEBUG
        // The receipt carries the already decoded baseline through save.
        #expect(reads == 1)
        #endif
        let third = second.store.syncLoadCodexScan(calendar: calendar)
        defer { third.release() }
        #expect(third.cache.files == second.cache.files)
        #if DEBUG
        #expect(reads == 2)
        #endif
        var changed = third.cache
        changed.files["/sessions/a.jsonl"]?.lastModel = "gpt-5.6-sol"
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
        #expect(reads == 2)
        #endif
        var otherCalendar = calendar
        otherCalendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let otherZone = third.store.syncLoadCodexScan(calendar: otherCalendar)
        defer { otherZone.release() }
        #expect(otherZone.cache.files.isEmpty)
    }

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
