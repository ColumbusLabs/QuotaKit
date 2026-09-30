import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageStoreReadPerformanceTests {
    @Test
    func `warm activity and status reuse the stamped activity view`() throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let writer = CostUsageStore(cacheRoot: fixture.root)
        let cache = Self.seededCache()
        let saved = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!saved.catchUpRequired)

        #if DEBUG
        var snapshotPurposes: [CostUsageStoreReadPurpose] = []
        var decodePurposes: [CostUsageStoreReadPurpose] = []
        var integrityChecks = 0
        var usageRowReads = 0
        CostUsageStore.codexReadViewIntegrityCheckForTesting = { url in
            if url == writer.databaseURL { integrityChecks += 1 }
        }
        CostUsageStore.codexReadViewSnapshotForTesting = { url, purpose in
            if url == writer.databaseURL { snapshotPurposes.append(purpose) }
        }
        CostUsageStore.codexReadViewDecodeForTesting = { url, purpose in
            if url == writer.databaseURL { decodePurposes.append(purpose) }
        }
        CostUsageStore.codexReadViewUsageRowsForTesting = { url in
            if url == writer.databaseURL { usageRowReads += 1 }
        }
        defer {
            CostUsageStore.codexReadViewIntegrityCheckForTesting = nil
            CostUsageStore.codexReadViewSnapshotForTesting = nil
            CostUsageStore.codexReadViewDecodeForTesting = nil
            CostUsageStore.codexReadViewUsageRowsForTesting = nil
        }
        #endif

        let activity = CostUsageStoreAccess.readView(
            cacheRoot: fixture.root,
            calendar: calendar,
            purpose: .activity)
        let status = CostUsageStoreAccess.readView(
            cacheRoot: fixture.root,
            calendar: calendar,
            purpose: .status)

        #expect(activity.days == status.days)
        #expect(activity.days["2026-08-01"]?["gpt-5.5"] == [10, 0, 3])
        #if DEBUG
        #expect(snapshotPurposes == [.activity])
        #expect(decodePurposes == [.activity])
        #expect(integrityChecks == 1)
        #expect(usageRowReads == 0)
        #endif
    }

    @Test
    func `report reads stay transient and do not replace the activity view`() throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let writer = CostUsageStore(cacheRoot: fixture.root)
        let saved = writer.syncSaveCodexCache(
            Self.seededCache(),
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!saved.catchUpRequired)

        #if DEBUG
        var snapshotPurposes: [CostUsageStoreReadPurpose] = []
        var decodePurposes: [CostUsageStoreReadPurpose] = []
        var usageRowReads = 0
        CostUsageStore.codexReadViewSnapshotForTesting = { url, purpose in
            if url == writer.databaseURL { snapshotPurposes.append(purpose) }
        }
        CostUsageStore.codexReadViewDecodeForTesting = { url, purpose in
            if url == writer.databaseURL { decodePurposes.append(purpose) }
        }
        CostUsageStore.codexReadViewUsageRowsForTesting = { url in
            if url == writer.databaseURL { usageRowReads += 1 }
        }
        defer {
            CostUsageStore.codexReadViewSnapshotForTesting = nil
            CostUsageStore.codexReadViewDecodeForTesting = nil
            CostUsageStore.codexReadViewUsageRowsForTesting = nil
        }
        #endif

        let activity = CostUsageStoreAccess.readView(
            cacheRoot: fixture.root,
            calendar: calendar,
            purpose: .activity)
        _ = CostUsageStoreAccess.readView(
            cacheRoot: fixture.root,
            calendar: calendar,
            purpose: .report)
        let status = CostUsageStoreAccess.readView(
            cacheRoot: fixture.root,
            calendar: calendar,
            purpose: .status)

        #expect(activity.days == status.days)
        #if DEBUG
        #expect(snapshotPurposes == [.activity, .report])
        #expect(decodePurposes == [.activity, .report])
        #expect(usageRowReads == 1)
        #endif
    }

    @Test
    func `external database commits invalidate retained activity`() throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let writer = CostUsageStore(cacheRoot: fixture.root)
        var cache = Self.seededCache()
        let saved = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!saved.catchUpRequired)

        #if DEBUG
        var snapshots = 0
        var decodes = 0
        CostUsageStore.codexReadViewSnapshotForTesting = { url, _ in
            if url == writer.databaseURL { snapshots += 1 }
        }
        CostUsageStore.codexReadViewDecodeForTesting = { url, _ in
            if url == writer.databaseURL { decodes += 1 }
        }
        defer {
            CostUsageStore.codexReadViewSnapshotForTesting = nil
            CostUsageStore.codexReadViewDecodeForTesting = nil
        }
        #endif

        _ = CostUsageStoreAccess.readView(
            cacheRoot: fixture.root,
            calendar: calendar,
            purpose: .activity)
        cache.days["2026-08-01"]?["gpt-5.5"] = [20, 0, 6]
        let updated = writer.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!updated.catchUpRequired)

        let refreshed = CostUsageStoreAccess.readView(
            cacheRoot: fixture.root,
            calendar: calendar,
            purpose: .activity)
        #expect(refreshed.days["2026-08-01"]?["gpt-5.5"] == [20, 0, 6])
        #if DEBUG
        #expect(snapshots == 2)
        #expect(decodes == 2)
        #endif
    }

    @Test
    func `read view use preserves the scanner save receipt`() throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let store = CostUsageStore(cacheRoot: fixture.root)
        let saved = store.syncSaveCodexCache(
            Self.seededCache(),
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!saved.catchUpRequired)

        let scan = store.syncLoadCodexScan(calendar: calendar)
        defer { scan.release() }
        _ = store.syncLoadCodexReadView(calendar: calendar, purpose: .activity)
        var updated = scan.cache
        updated.files["/sessions/read-view-receipt.jsonl"] = CostUsageFileUsage(
            mtimeUnixMs: 1,
            size: 0,
            days: [:])
        let result = store.syncSaveCodexCache(
            updated,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"),
            expectedScanStamp: scan.scanStamp,
            receipt: scan.receipt)

        #expect(!result.catchUpRequired)
    }

    @Test
    func `scanner streams physical usage rows with the eager fallback semantics`() async throws {
        let fixture = try ReadPerformanceFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let store = CostUsageStore(cacheRoot: fixture.root)
        let partialPath = "/sessions/a-partial.jsonl"
        let fallbackPath = "/sessions/z-malformed.jsonl"
        let first = Self.row(model: "gpt-5.5", input: 10, eventIndex: 0)
        let second = Self.row(model: "gpt-5.5", input: 20, eventIndex: 1)
        var cache = Self.seededCache()
        var partial = CostUsageFileUsage(mtimeUnixMs: 1, size: 64, days: [
            "2026-08-01": ["gpt-5.5": [30, 0, 6]],
        ])
        partial.codexRows = [first, second]
        cache.files[partialPath] = partial
        var fallback = CostUsageFileUsage(mtimeUnixMs: 2, size: 32, days: [
            "2026-08-01": ["gpt-5.6-sol": [7, 0, 2]],
        ])
        fallback.codexRows = [Self.row(model: "gpt-5.6-sol", input: 7, eventIndex: 0)]
        cache.files[fallbackPath] = fallback
        // Persist the files before marking the partial path as retained by a hydration retry.
        // Full saves preserve retained paths without creating or rewriting their file rows.
        let seeded = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!seeded.catchUpRequired)

        let retry = CodexHistoryHydrationRetry(retainedPaths: [partialPath], forceFullRescan: true)
        cache.codexHistoryHydrationRetries = [partialPath: retry]
        let saved = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: "2026-08-01", untilKey: "2026-08-01"))
        #expect(!saved.catchUpRequired)

        #expect(await store.replaceUsageRows(path: partialPath, rows: [
            Self.persistedRow(path: partialPath, index: 0, row: first),
            CostUsageStoreUsageRow(path: partialPath, rowIndex: 1, payload: Data("invalid-json".utf8)),
            Self.persistedRow(path: partialPath, index: 2, row: second),
        ]))
        #expect(await store.replaceUsageRows(path: fallbackPath, rows: [
            CostUsageStoreUsageRow(path: fallbackPath, rowIndex: 0, payload: Data("bad-row-a".utf8)),
            CostUsageStoreUsageRow(path: fallbackPath, rowIndex: 1, payload: Data("bad-row-b".utf8)),
        ]))

        let eager = await store.readSnapshot()
        let expected = CostUsageStore.decodeCodexCache(
            from: eager,
            preserveMalformedFiles: true)
        #if DEBUG
        var visits: [(path: String, rowIndex: Int, payloadBytes: Int, decoded: Bool)] = []
        CostUsageStore.codexStreamedUsageRowForTesting = { path, rowIndex, payloadBytes, decoded in
            visits.append((path, rowIndex, payloadBytes, decoded))
        }
        defer { CostUsageStore.codexStreamedUsageRowForTesting = nil }
        #endif
        let loaded = store.syncLoadCodexScan(calendar: calendar)
        defer { loaded.release() }

        #expect(loaded.cache.files[partialPath]?.codexRows == expected.files[partialPath]?.codexRows)
        #expect(loaded.cache.files[fallbackPath]?.codexRows == expected.files[fallbackPath]?.codexRows)
        #expect(loaded.cache.codexHistoryHydrationRetries == cache.codexHistoryHydrationRetries)
        #if DEBUG
        #expect(visits.map { ($0.path, $0.rowIndex) }.map { "\($0.0)#\($0.1)" } == [
            "\(partialPath)#0",
            "\(partialPath)#1",
            "\(partialPath)#2",
            "\(fallbackPath)#0",
            "\(fallbackPath)#1",
        ])
        #expect(visits.map(\.decoded) == [true, false, true, false, false])
        #expect(await store.fetchDetailCounts(path: partialPath).rowCount == 3)
        #expect(await store.fetchDetailCounts(path: fallbackPath).rowCount == 2)
        #endif
    }

    private static func seededCache() -> CostUsageCache {
        var cache = CostUsageCache()
        cache.scanSinceKey = "2026-08-01"
        cache.scanUntilKey = "2026-08-01"
        cache.roots = [:]
        cache.days = ["2026-08-01": ["gpt-5.5": [10, 0, 3]]]
        return cache
    }

    private static func row(model: String, input: Int, eventIndex: Int) -> CostUsageScanner.CodexUsageRow {
        CostUsageScanner.CodexUsageRow(
            day: "2026-08-01",
            model: model,
            turnID: "turn-\(eventIndex)",
            eventIndex: eventIndex,
            input: input,
            cached: 0,
            output: input / 2,
            reasoning: 0,
            knownCostNanos: nil,
            unpricedTokens: nil,
            pricingModel: model,
            pricingMode: "standard")
    }

    private static func persistedRow(
        path: String,
        index: Int,
        row: CostUsageScanner.CodexUsageRow) -> CostUsageStoreUsageRow
    {
        CostUsageStoreUsageRow(
            path: path,
            rowIndex: index,
            payload: (try? JSONEncoder().encode(row)) ?? Data())
    }
}

private struct ReadPerformanceFixture: Sendable {
    let root: URL

    init() throws {
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar-CostUsageReadPerformance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: self.root)
    }
}
