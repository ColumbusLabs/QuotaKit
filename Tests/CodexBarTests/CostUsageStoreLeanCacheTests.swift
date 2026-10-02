import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageStoreLeanCacheTests {
    @Test
    func `ordinary Codex load hydrates only requested raw history`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaKit-LazyHistory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let requestedPath = "/sessions/requested-history.jsonl"
        let untouchedPath = "/sessions/untouched-history.jsonl"
        let emptyPath = "/sessions/empty-history.jsonl"

        func snapshots(_ input: Int) -> [CostUsageCodexTokenSnapshot] {
            [0, 1].map { index in
                CostUsageCodexTokenSnapshot(
                    timestamp: "2026-08-30T12:00:0\(index)Z",
                    last: CostUsageCodexTotals(input: input + index, cached: 0, output: 1),
                    total: CostUsageCodexTotals(input: input + index, cached: 0, output: index + 1),
                    endOffset: Int64(100 + index))
            }
        }

        func usage(fileID: String, snapshots: [CostUsageCodexTokenSnapshot]) -> CostUsageFileUsage {
            var usage = CostUsageFileUsage(mtimeUnixMs: 1000, size: 200, days: [:])
            usage.parsedBytes = 200
            usage.codexScanFileId = fileID
            usage.codexScanTargetSize = 200
            usage.codexScanComplete = true
            usage.codexTokenTimestampsMonotonic = true
            usage.codexTokenSnapshots = snapshots
            return usage
        }

        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-30"
        cache.scanUntilKey = "2026-08-30"
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        let requestedSnapshots = snapshots(10)
        let untouchedSnapshots = snapshots(20)
        cache.files[requestedPath] = usage(fileID: "1:101", snapshots: requestedSnapshots)
        cache.files[untouchedPath] = usage(fileID: "1:102", snapshots: untouchedSnapshots)
        cache.files[emptyPath] = usage(fileID: "1:103", snapshots: [])
        let writer = CostUsageStore(cacheRoot: root)
        let saved = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-30", untilKey: "2026-08-30"))
        #expect(!saved.catchUpRequired)
        let expectedRequestedRows = await writer.fetchTokenSnapshots(path: requestedPath)
        let expectedUntouchedRows = await writer.fetchTokenSnapshots(path: untouchedPath)

        let tokenTableReads = LockIsolated(0)
        let tokenSnapshotPaths = LockIsolated<[String?]>([])
        let observedStorePath = writer.databaseURL.standardizedFileURL.path
        var hooks = CostUsageStoreTestHooks.current
        hooks.tokenSnapshotsRead = { storeURL in
            guard storeURL.standardizedFileURL.path == observedStorePath else { return }
            tokenTableReads.setValue(tokenTableReads.value + 1)
        }
        hooks.tokenSnapshotPathRead = { storeURL, path in
            guard storeURL.standardizedFileURL.path == observedStorePath else { return }
            tokenSnapshotPaths.setValue(tokenSnapshotPaths.value + [path])
        }
        let loaded = CostUsageStoreTestHooks.$current.withValue(hooks) {
            CostUsageStoreAccess.load(cacheRoot: root, calendar: calendar)
        }

        defer { loaded.release() }
        #expect(tokenTableReads.value == 0)
        #expect(tokenSnapshotPaths.value.isEmpty)
        #expect(loaded.cache.files[requestedPath]?.codexTokenSnapshots == nil)
        #expect(loaded.cache.files[untouchedPath]?.codexTokenSnapshots == nil)
        #expect(loaded.cache.files[emptyPath]?.codexTokenSnapshots == [])

        let hydrator = CodexScanHistoryHydrator(storeLoad: loaded, checkCancellation: nil)
        let hydration = try CostUsageStoreTestHooks.$current.withValue(hooks) {
            try hydrator.hydrate(paths: [requestedPath])
        }
        #expect(hydration == .ready)
        var hydratedCache = loaded.cache
        hydrator.applyHydratedSnapshots(to: &hydratedCache)
        #expect(hydratedCache.files[requestedPath]?.codexTokenSnapshots == requestedSnapshots)
        #expect(hydratedCache.files[untouchedPath]?.codexTokenSnapshots == nil)
        #expect(tokenTableReads.value == 1)
        #expect(tokenSnapshotPaths.value == [requestedPath])

        let savedAfterHydration = CostUsageStoreAccess.save(
            store: loaded.store,
            cache: hydratedCache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-30", untilKey: "2026-08-30"),
            skipIdenticalContent: true,
            expectedScanStamp: loaded.scanStamp,
            receipt: loaded.receipt,
            requireScanStamp: true)
        #expect(!savedAfterHydration.catchUpRequired)

        #expect(await loaded.store.fetchTokenSnapshots(path: requestedPath) == expectedRequestedRows)
        #expect(await loaded.store.fetchTokenSnapshots(path: untouchedPath) == expectedUntouchedRows)
        #expect(await loaded.store.fetchDetailCounts(path: untouchedPath).snapshotCount == untouchedSnapshots.count)
        let untouchedFile = try #require(await loaded.store.fetchFile(path: untouchedPath))
        let detailsPayload = try #require(untouchedFile.scanState.detailsPayload)
        let details = try #require(JSONSerialization.jsonObject(with: detailsPayload) as? [String: Any])
        #expect(details["hasTokenSnapshots"] as? Bool == true)

        let reopened = CostUsageStoreAccess.read(cacheRoot: root, calendar: calendar)
        #expect(reopened.files[requestedPath]?.codexTokenSnapshots == requestedSnapshots)
        #expect(reopened.files[untouchedPath]?.codexTokenSnapshots == untouchedSnapshots)
        #expect(reopened.files[emptyPath]?.codexTokenSnapshots == [])
    }

    @Test
    func `unavailable raw history hydration preserves stored rows`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaKit-LazyHistoryFailure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let path = "/sessions/unavailable-history.jsonl"
        let snapshots = [
            CostUsageCodexTokenSnapshot(
                timestamp: "2026-08-30T12:00:00Z",
                last: CostUsageCodexTotals(input: 3, cached: 0, output: 1),
                total: CostUsageCodexTotals(input: 3, cached: 0, output: 1),
                endOffset: 100),
        ]
        var usage = CostUsageFileUsage(mtimeUnixMs: 1000, size: 100, days: [:])
        usage.parsedBytes = 100
        usage.codexScanFileId = "1:201"
        usage.codexScanTargetSize = 100
        usage.codexScanComplete = true
        usage.codexTokenTimestampsMonotonic = true
        usage.codexTokenSnapshots = snapshots
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-30"
        cache.scanUntilKey = "2026-08-30"
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.files[path] = usage
        let writer = CostUsageStore(cacheRoot: root)
        let initialSave = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-30", untilKey: "2026-08-30"))
        #expect(!initialSave.catchUpRequired)

        let loaded = CostUsageStoreAccess.load(cacheRoot: root, calendar: calendar)
        defer { loaded.release() }
        let storedRows = await loaded.store.fetchTokenSnapshots(path: path)
        var hooks = CostUsageStoreTestHooks.current
        hooks.codexTokenSnapshotHydrationFailure = { storeURL, paths in
            storeURL.standardizedFileURL.path == writer.databaseURL.standardizedFileURL.path
                && paths == [path]
        }

        let hydrator = CodexScanHistoryHydrator(storeLoad: loaded, checkCancellation: nil)
        let hydration = try CostUsageStoreTestHooks.$current.withValue(hooks) {
            try hydrator.hydrate(paths: [path])
        }
        #expect(hydration == .unavailable)
        #expect(loaded.cache.files[path]?.codexTokenSnapshots == nil)

        let savedAfterFailure = CostUsageStoreAccess.save(
            store: loaded.store,
            cache: loaded.cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-30", untilKey: "2026-08-30"),
            skipIdenticalContent: true,
            expectedScanStamp: loaded.scanStamp,
            receipt: loaded.receipt,
            requireScanStamp: true)
        #expect(!savedAfterFailure.catchUpRequired)
        #expect(await loaded.store.fetchTokenSnapshots(path: path) == storedRows)
        #expect(await loaded.store.fetchDetailCounts(path: path).snapshotCount == snapshots.count)
    }

    @Test
    func `lazy baseline keeps malformed history manifests visible`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaKit-LazyHistoryMalformed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let path = "/sessions/malformed-history-manifest.jsonl"
        let snapshots = [
            CostUsageCodexTokenSnapshot(
                timestamp: "2026-08-30T12:00:00Z",
                last: CostUsageCodexTotals(input: 5, cached: 0, output: 1),
                total: CostUsageCodexTotals(input: 5, cached: 0, output: 1),
                endOffset: 100),
        ]
        var usage = CostUsageFileUsage(mtimeUnixMs: 1000, size: 100, days: [:])
        usage.parsedBytes = 100
        usage.codexScanFileId = "1:301"
        usage.codexScanTargetSize = 100
        usage.codexScanComplete = true
        usage.codexTokenTimestampsMonotonic = true
        usage.codexTokenSnapshots = snapshots
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-30"
        cache.scanUntilKey = "2026-08-30"
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.files[path] = usage
        let writer = CostUsageStore(cacheRoot: root)
        let initialSave = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-30", untilKey: "2026-08-30"))
        #expect(!initialSave.catchUpRequired)
        let storedRows = await writer.fetchTokenSnapshots(path: path)
        var malformedFile = try #require(await writer.fetchFile(path: path))
        malformedFile.scanState.detailsPayload = Data("{malformed".utf8)
        #expect(await writer.upsertFile(malformedFile))

        let loaded = CostUsageStoreAccess.load(cacheRoot: root, calendar: calendar)
        defer { loaded.release() }
        #expect(loaded.cache.files[path] != nil)
        #expect(loaded.cache.files[path]?.codexTokenSnapshots == nil)
        let hydrator = CodexScanHistoryHydrator(storeLoad: loaded, checkCancellation: nil)
        #expect(try hydrator.hydrate(paths: [path]) == .ready)
        let malformedUsage = try #require(loaded.cache.files[path])
        #expect(hydrator.usageWithHydratedSnapshots(malformedUsage, path: path).codexTokenSnapshots == snapshots)

        let savedAfterMalformedManifest = CostUsageStoreAccess.save(
            store: loaded.store,
            cache: loaded.cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-30", untilKey: "2026-08-30"),
            skipIdenticalContent: true,
            expectedScanStamp: loaded.scanStamp,
            receipt: loaded.receipt,
            requireScanStamp: true)
        #expect(!savedAfterMalformedManifest.catchUpRequired)
        #expect(await loaded.store.fetchTokenSnapshots(path: path) == storedRows)
        #expect(await loaded.store.fetchFile(path: path) == malformedFile)
    }

    @Test
    func `lean cache skips token snapshot materialization and preserves report fields`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaKit-LeanCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let path = "/sessions/lean-cache.jsonl"
        let snapshots = [
            CostUsageCodexTokenSnapshot(
                timestamp: "2026-08-30T12:00:00Z",
                last: CostUsageCodexTotals(input: 10, cached: 2, output: 3, reasoning: nil),
                total: CostUsageCodexTotals(input: 10, cached: 2, output: 3, reasoning: nil),
                endOffset: 80),
            CostUsageCodexTokenSnapshot(
                timestamp: "2026-08-30T12:01:00Z",
                last: CostUsageCodexTotals(input: 11, cached: 3, output: 4, reasoning: nil),
                total: CostUsageCodexTotals(input: 21, cached: 5, output: 7, reasoning: nil),
                endOffset: 160),
        ]
        let row = CostUsageScanner.CodexUsageRow(
            day: "2026-08-30",
            model: "gpt-5.6-sol",
            turnID: "turn-1",
            eventIndex: 0,
            timestampUnixMs: 1_756_560_000_000,
            input: 21,
            cached: 5,
            output: 7)
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-30"
        cache.scanUntilKey = "2026-08-30"
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.files[path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1000,
            size: 160,
            days: ["2026-08-30": ["gpt-5.6-sol": [21, 5, 7]]],
            parsedBytes: 160,
            lastTotals: CostUsageCodexTotals(input: 21, cached: 5, output: 7, reasoning: nil),
            sessionId: "session-1",
            codexRows: [row],
            codexTokenSnapshots: snapshots,
            codexTokenCheckpoints: CostUsageScanner.codexTokenCheckpoints(for: snapshots),
            codexTokenTimestampsMonotonic: true,
            codexScanFileId: "1:1",
            codexScanTargetSize: 160,
            codexScanComplete: true)
        let store = CostUsageStore(cacheRoot: root)
        let save = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-30", untilKey: "2026-08-30"))
        #expect(!save.catchUpRequired)

        let tokenTableReads = LockIsolated(0)
        let observedStorePath = store.databaseURL.standardizedFileURL.path
        var hooks = CostUsageStoreTestHooks.current
        hooks.tokenSnapshotsRead = { storeURL in
            guard storeURL.standardizedFileURL.path == observedStorePath else { return }
            tokenTableReads.setValue(tokenTableReads.value + 1)
        }

        let full = CostUsageStoreTestHooks.$current.withValue(hooks) {
            CostUsageStoreAccess.read(cacheRoot: root, calendar: calendar)
        }
        #expect(tokenTableReads.value == 1)
        #expect(full.files[path]?.codexTokenSnapshots?.count == snapshots.count)
        #expect(full.files[path]?.codexTokenCheckpoints != nil)

        let lean = CostUsageStoreAccess.readWithoutTokenSnapshots(cacheRoot: root, calendar: calendar)
        #expect(tokenTableReads.value == 1)
        #expect(lean.files[path]?.codexTokenSnapshots == nil)
        #expect(lean.files[path]?.codexTokenCheckpoints == nil)
        #expect(lean.files[path]?.codexRows == full.files[path]?.codexRows)
        #expect(lean.files[path]?.days == full.files[path]?.days)
        #expect(lean.days == full.days)
        #expect(lean.timeZoneIdentifier == full.timeZoneIdentifier)
    }
}
