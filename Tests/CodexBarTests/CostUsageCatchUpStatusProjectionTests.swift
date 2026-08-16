import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageCatchUpStatusProjectionTests {
    @Test
    func `status polling does not hydrate the full usage snapshot`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        let path = env.codexSessionsRoot.appendingPathComponent("partial.jsonl").path
        var cache = CostUsageCache()
        cache.timeZoneIdentifier = options.calendar.timeZone.identifier
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.codexScanCatchUpPending = true
        cache.codexScanProcessedBytes = 40
        cache.codexScanTotalBytes = 100
        cache.codexScanCompletedFiles = 0
        cache.codexScanTotalFiles = 1
        cache.files[path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 100,
            days: [:],
            parsedBytes: 40,
            codexScanFileId: "1:1",
            codexScanTargetSize: 100,
            codexScanComplete: false)
        CostUsageStoreAccess.replace(
            cacheRoot: env.cacheRoot,
            cache: cache,
            calendar: options.calendar)

        let targetDatabase = CostUsageStore(cacheRoot: env.cacheRoot).databaseURL.standardizedFileURL
        let snapshotReads = SnapshotReadCounter(targetDatabase: targetDatabase)
        CostUsageStore.snapshotReadForTesting = { snapshotReads.record(databaseURL: $0) }
        defer { CostUsageStore.snapshotReadForTesting = nil }

        let status = await CostUsageFetcher(scannerOptions: options).codexScanCatchUpStatus()

        #expect(status.pending)
        #expect(status.processedBytes == 40)
        #expect(status.totalBytes == 100)
        #expect(status.completedFiles == 0)
        #expect(status.totalFiles == 1)
        #expect(status.progressKey.hasPrefix("v3:1:"))
        #expect(snapshotReads.value == 0)
    }

    @Test
    func `projection progress key includes resumable discovery head offset`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let iso = env.isoString(for: day)
        let body = #"{"type":"session_meta","timestamp":"\#(iso)","payload":{"session_id":"known","cwd":""#
            + String(repeating: "x", count: 512)
            + #""}}"#
            + "\n"
        let fileURL = try env.writeCodexSessionFile(
            day: day,
            filename: "projection-head.jsonl",
            contents: body)

        let firstIndex = CostUsageScanner.CodexSessionFileIndex(
            files: [fileURL],
            roots: [env.codexSessionsRoot],
            cachedDiscovery: nil,
            scanBudget: .init(maxFileBytes: 32, maxBytesPerRefresh: 32))
        _ = try firstIndex.lookup(sessionId: "absent")
        let firstDiscovery = firstIndex.persistedState
        let secondIndex = CostUsageScanner.CodexSessionFileIndex(
            files: [fileURL],
            roots: [env.codexSessionsRoot],
            cachedDiscovery: firstDiscovery,
            scanBudget: .init(maxFileBytes: 32, maxBytesPerRefresh: 32))
        _ = try secondIndex.lookup(sessionId: "absent")
        let secondDiscovery = secondIndex.persistedState

        var first = CostUsageStoreCatchUpProjection.empty
        first.discoveryState = try Self.storeDiscovery(firstDiscovery)
        var second = CostUsageStoreCatchUpProjection.empty
        second.discoveryState = try Self.storeDiscovery(secondDiscovery)

        #expect(firstDiscovery.headScan?.offset == secondDiscovery.headScan?.offset)
        #expect((secondDiscovery.headScan?.resumeState?.offset ?? 0)
            > (firstDiscovery.headScan?.resumeState?.offset ?? 0))
        #expect(CostUsageFetcher.codexScanProgressKey(projection: first, scopedFiles: [])
            != CostUsageFetcher.codexScanProgressKey(projection: second, scopedFiles: []))
    }

    @Test
    func `projection progress key includes file resume and buffered dependency state`() {
        let initial = CostUsageStoreCatchUpFile(
            path: "/sessions/fork.jsonl",
            inode: 1,
            mtimeUnixMs: 1,
            size: 100,
            fileIdentity: "1:1",
            parsedBytes: 40,
            scanTargetSize: 100,
            resumeOffset: 48,
            scanComplete: false,
            forkedFromID: "missing-parent",
            forkBaselineDependencyKey: nil,
            hasBufferedSubagentLines: false,
            hasBufferedUnresolvedForkLines: true)
        let initialKey = CostUsageFetcher.codexScanProgressKey(
            projection: .empty,
            scopedFiles: [initial])

        var resumed = initial
        resumed.resumeOffset = 64
        let resumedKey = CostUsageFetcher.codexScanProgressKey(
            projection: .empty,
            scopedFiles: [resumed])

        var dependencyResolved = resumed
        dependencyResolved.forkBaselineDependencyKey = "parent:resolved"
        let dependencyKey = CostUsageFetcher.codexScanProgressKey(
            projection: .empty,
            scopedFiles: [dependencyResolved])

        var replayed = dependencyResolved
        replayed.hasBufferedUnresolvedForkLines = false
        let replayedKey = CostUsageFetcher.codexScanProgressKey(
            projection: .empty,
            scopedFiles: [replayed])

        #expect(resumedKey != initialKey)
        #expect(dependencyKey != resumedKey)
        #expect(replayedKey != dependencyKey)
    }

    @Test
    func `status keeps catch up pending when device identity validation exceeds its bounded slice`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 5, day: 10)
        let iso = env.isoString(for: day)
        let corpusSize = CostUsageScanner.codexCatchUpScanCandidateLimit + 1
        for index in 0..<corpusSize {
            _ = try env.writeCodexSessionFile(
                day: day,
                filename: String(format: "identity-%04d.jsonl", index),
                contents: #"{"type":"session_meta","timestamp":"\#(iso)","payload":"#
                    + #"{"session_id":"identity-\#(index)"}}"#
                    + "\n")
        }

        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.refreshMinIntervalSeconds = 0
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)

        let fetcher = CostUsageFetcher(scannerOptions: options)
        let initialStatus = await fetcher.codexScanCatchUpStatus()
        #expect(!initialStatus.pending)

        let store = CostUsageStore(cacheRoot: env.cacheRoot)
        let snapshot = await store.readSnapshot()
        #expect(snapshot.files.count == corpusSize)
        for var file in snapshot.files {
            let identity = try #require(file.scanState.fileIdentity)
            let inode = try #require(identity.split(separator: ":").last)
            file.scanState.fileIdentity = "0:\(inode)"
            #expect(await store.upsertFile(file))
        }

        let counter = ProjectionIdentityValidationCounter()
        CostUsageStore.codexCatchUpReconciliationVisitForTesting = { counter.increment() }
        defer { CostUsageStore.codexCatchUpReconciliationVisitForTesting = nil }

        let status = await fetcher.codexScanCatchUpStatus()
        #expect(status.pending)
        #expect(counter.value == CostUsageScanner.codexCatchUpScanCandidateLimit)
    }

    private static func storeDiscovery(
        _ value: CostUsageCodexSessionDiscovery) throws -> CostUsageStoreDiscoveryState
    {
        try CostUsageStoreDiscoveryState(
            roots: value.roots,
            generation: value.generation,
            directoryPaths: value.directoryPaths,
            nextDirectoryIndex: value.nextDirectoryIndex,
            filePaths: value.filePaths,
            nextFileIndex: value.nextFileIndex,
            filePathBySessionID: value.filePathBySessionId,
            missingSessionIDs: value.missingSessionIds,
            pendingSessionIDs: value.pendingSessionIds,
            validationDirectoryIndex: value.validationDirectoryIndex,
            isComplete: value.isComplete,
            payload: JSONEncoder().encode(value))
    }
}

private final class ProjectionIdentityValidationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        self.lock.withLock { self.count += 1 }
    }

    var value: Int {
        self.lock.withLock { self.count }
    }
}

private final class SnapshotReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let targetDatabase: URL
    private var count = 0

    init(targetDatabase: URL) {
        self.targetDatabase = targetDatabase
    }

    func record(databaseURL: URL) {
        guard databaseURL.standardizedFileURL == self.targetDatabase else { return }
        self.lock.withLock { self.count += 1 }
    }

    var value: Int {
        self.lock.withLock { self.count }
    }
}
