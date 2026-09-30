import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageStoreLeanCacheTests {
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

        var tokenTableReads = 0
        let observedStorePath = store.databaseURL.standardizedFileURL.path
        CostUsageStore.tokenSnapshotsReadForTesting = { storeURL in
            guard storeURL.standardizedFileURL.path == observedStorePath else { return }
            tokenTableReads += 1
        }
        defer { CostUsageStore.tokenSnapshotsReadForTesting = nil }

        let full = CostUsageStoreAccess.read(cacheRoot: root, calendar: calendar)
        #expect(tokenTableReads == 1)
        #expect(full.files[path]?.codexTokenSnapshots?.count == snapshots.count)
        #expect(full.files[path]?.codexTokenCheckpoints != nil)

        let lean = CostUsageStoreAccess.readWithoutTokenSnapshots(cacheRoot: root, calendar: calendar)
        #expect(tokenTableReads == 1)
        #expect(lean.files[path]?.codexTokenSnapshots == nil)
        #expect(lean.files[path]?.codexTokenCheckpoints == nil)
        #expect(lean.files[path]?.codexRows == full.files[path]?.codexRows)
        #expect(lean.files[path]?.days == full.files[path]?.days)
        #expect(lean.days == full.days)
        #expect(lean.timeZoneIdentifier == full.timeZoneIdentifier)
    }
}
