import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageArchivePresenceSweepTests {
    @Test
    func `presence sweep advances past inaccessible paths and resumes from persisted state`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let original = try env.writeCodexSessionFile(day: day, filename: "original.jsonl", contents: env.jsonl([[
            "type": "session_meta", "payload": ["id": "presence-fixture", "timestamp": env.isoString(for: day)],
        ]]))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.refreshMinIntervalSeconds = 0
        _ = CostUsageScanner.loadDailyReport(provider: .codex, since: day, until: day, now: day, options: options)
        var cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        let usage = try #require(cache.files[original.path])
        let loop = env.root.appendingPathComponent("presence-loop")
        try FileManager.default.createSymbolicLink(atPath: loop.path, withDestinationPath: loop.path)
        let inaccessible = loop.appendingPathComponent("unknown.jsonl")
        let missing = (0..<514).map { env.codexSessionsRoot.appendingPathComponent("missing-\($0).jsonl") }
        let archive = env.codexSessionsRoot.appendingPathComponent("last.jsonl")
        try Data().write(to: archive.appendingPathExtension("zst"))
        let files = [inaccessible] + missing + [archive]
        cache.files = Dictionary(uniqueKeysWithValues: files.map { ($0.path, usage) })
        let roots = [env.codexSessionsRoot]
        var index = CostUsageScanner.CodexSessionFileIndex(files: files, roots: roots)
        func visit(_ index: CostUsageScanner.CodexSessionFileIndex) throws -> [URL] {
            try index.takeMetadataRefreshCandidates(
                cache: &cache,
                dayKey: "2026-08-30",
                scanSinceKey: "2026-08-30",
                calendar: .current,
                visitLimit: 512,
                restartCompletedSweep: true)
        }
        _ = try visit(index)
        let first = index.persistedState
        #expect(first.metadataCandidateIndex == 512)
        #expect(index.metadataPresenceVisits == 512)
        #expect(index.remainingPresenceVisits(unlimited: false) == 0)
        #expect(index.remainingPresenceVisits(unlimited: true) >= files.count)
        #expect(first.metadataPresenceEstablished == false)
        #expect(first.metadataUnavailablePaths?.contains(inaccessible.path) == true)
        let encoded = try JSONEncoder().encode(first)
        let decoded = try JSONDecoder().decode(CostUsageCodexSessionDiscovery.self, from: encoded)
        index = CostUsageScanner.CodexSessionFileIndex(files: files, roots: roots, cachedDiscovery: decoded)
        let resumedCandidates = try visit(index)
        #expect(!resumedCandidates.contains { $0.path == archive.path })
        var second = first
        second.metadataCandidateIndex = (first.metadataCandidateIndex ?? 0) + 1
        var firstCache = cache
        firstCache.codexSessionDiscovery = first
        var secondCache = cache
        secondCache.codexSessionDiscovery = second
        #expect(CostUsageFetcher.codexScanProgressKey(cache: firstCache, scopedFiles: [:])
            != CostUsageFetcher.codexScanProgressKey(cache: secondCache, scopedFiles: [:]))
        let firstProjection = try Self.projection(first)
        let secondProjection = try Self.projection(second)
        #expect(CostUsageFetcher.codexScanProgressKey(projection: firstProjection, scopedFiles: [])
            != CostUsageFetcher.codexScanProgressKey(projection: secondProjection, scopedFiles: []))
        var rotated = second
        second.metadataUnavailablePaths = ["first", "second"]
        rotated.metadataUnavailablePaths = ["second", "first"]
        secondCache.codexSessionDiscovery = second
        var rotatedCache = secondCache
        rotatedCache.codexSessionDiscovery = rotated
        #expect(CostUsageFetcher.codexScanProgressKey(cache: secondCache, scopedFiles: [:])
            == CostUsageFetcher.codexScanProgressKey(cache: rotatedCache, scopedFiles: [:]))
        #expect(try CostUsageFetcher.codexScanProgressKey(projection: Self.projection(second), scopedFiles: [])
            == CostUsageFetcher.codexScanProgressKey(projection: Self.projection(rotated), scopedFiles: []))
        #expect(index.persistedState.metadataArchivedPaths?.contains(archive.path) == true)
        #expect(index.persistedState.metadataPresenceEstablished == false)
        #expect(index.persistedState.metadataUnavailablePaths?.contains(inaccessible.path) == true)
        try FileManager.default.removeItem(at: loop)
        try FileManager.default.createDirectory(at: loop, withIntermediateDirectories: false)
        try Data().write(to: inaccessible)
        for _ in 0..<4 where index.persistedState.metadataPresenceEstablished != true {
            _ = try visit(index)
        }
        #expect(index.persistedState.metadataUnavailablePaths?.isEmpty != false)
        #expect(index.persistedState.metadataPresenceEstablished == true)
        let legacyIndex = CostUsageScanner.CodexSessionFileIndex(
            files: [], roots: roots, cachedInventoryPaths: [archive.path])
        #expect(legacyIndex.persistedState.filePaths.contains(archive.path))
        _ = try visit(legacyIndex)
        #expect(legacyIndex.persistedState.metadataArchivedPaths?.contains(archive.path) == true)
        #expect(legacyIndex.persistedState.metadataPresenceEstablished == true)
        let beforeZero = legacyIndex.persistedState
        _ = try legacyIndex.takeMetadataRefreshCandidates(
            cache: &cache,
            dayKey: "2026-08-30",
            scanSinceKey: "2026-08-30",
            calendar: .current,
            visitLimit: 0,
            restartCompletedSweep: true)
        #expect(legacyIndex.persistedState == beforeZero)
        var legacy = index.persistedState
        legacy.metadataPresenceEstablished = nil
        legacy.metadataArchivedPaths = nil
        legacy.metadataUnavailablePaths = nil
        legacy.metadataCandidateIndex = legacy.filePaths.count
        index = CostUsageScanner.CodexSessionFileIndex(files: files, roots: roots, cachedDiscovery: legacy)
        _ = try visit(index)
        #expect(index.persistedState.metadataCandidateIndex == 512)
        #expect(index.persistedState.metadataPresenceEstablished == false)
        for _ in 0..<3 where index.persistedState.metadataPresenceEstablished != true {
            _ = try visit(index)
        }
        #expect(index.persistedState.metadataPresenceEstablished == true)
        try FileManager.default.removeItem(at: archive.appendingPathExtension("zst"))
        var deletion: [URL] = []
        for _ in 0..<3 {
            deletion += try visit(index)
        }
        #expect(deletion.contains { $0.path == archive.path })
        #expect(index.persistedState.metadataArchivedPaths?.contains(archive.path) != true)
    }

    @Test
    func `completed archive inventory requires established proof and a settled generation`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let path = env.codexSessionsRoot.appendingPathComponent("archive.jsonl").path
        var cache = CostUsageCache()
        var usage = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 10,
            days: [:],
            parsedBytes: 10,
            codexScanFileId: "1:42",
            codexScanComplete: true)
        usage.codexArchived = true
        usage.codexParserRevision = 0 // A compatible predecessor remains valid for archived history.
        cache.files[path] = usage
        cache.codexScanInventoryPaths = [path]
        let index = CostUsageScanner.CodexSessionFileIndex(files: [URL(fileURLWithPath: path)], roots: [])
        var discovery = index.persistedState
        discovery.metadataPresenceEstablished = true
        discovery.metadataArchivedPaths = [path]
        cache.codexSessionDiscovery = discovery
        let completed = CostUsageStore.completedCodexScanInventory(cache: cache, expectedTotalFiles: 1)
        #expect(completed?.fileCount == 1)
        #expect(completed?.totalBytes == 10)
        cache.codexSessionDiscovery?.metadataPresenceEstablished = false
        #expect(CostUsageStore.completedCodexScanInventory(cache: cache, expectedTotalFiles: 1)?.fileCount == nil)
        cache.codexSessionDiscovery?.metadataPresenceEstablished = true
        cache.codexSessionDiscovery?.metadataUnavailablePaths = [path]
        #expect(CostUsageStore.completedCodexScanInventory(cache: cache, expectedTotalFiles: 1)?.fileCount == nil)
        cache.codexSessionDiscovery?.metadataUnavailablePaths = nil
        cache.files[path]?.codexReplacementScanPending = true
        #expect(CostUsageStore.completedCodexScanInventory(cache: cache, expectedTotalFiles: 1)?.fileCount == nil)
        cache.files[path]?.codexReplacementScanPending = false
        cache.files[path]?.codexHasBufferedUnresolvedForkLines = true
        #expect(CostUsageStore.completedCodexScanInventory(cache: cache, expectedTotalFiles: 1)?.fileCount == nil)
    }

    @Test
    func `current day admission leaves settled archive absence to the presence sweep`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 8, day: 30)
        let file = env.codexSessionsRoot.appendingPathComponent("archive-admission.jsonl")
        var usage = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: Int64(day.timeIntervalSince1970 * 1000),
            size: 10,
            days: [:],
            parsedBytes: 10,
            codexScanFileId: "1:42",
            codexScanComplete: true)
        usage.codexArchived = true
        var cache = CostUsageCache()
        cache.files[file.path] = usage
        let index = CostUsageScanner.CodexSessionFileIndex(files: [file], roots: [env.codexSessionsRoot])
        var discovery = index.persistedState
        discovery.metadataPresenceEstablished = true
        discovery.metadataArchivedPaths = [file.path]
        cache.codexSessionDiscovery = discovery
        var metadata = CostUsageScanner.CodexFileMetadata(
            path: file.path,
            mtimeUnixMs: 0,
            size: 0,
            fileId: nil)
        func candidates() -> [URL] {
            CostUsageScanner.codexChangedCurrentDayCachedFiles(
                cache: cache,
                roots: [env.codexSessionsRoot],
                dayKey: "2026-08-30",
                calendar: .current,
                metadata: { _ in metadata })
        }
        #expect(candidates().isEmpty)
        #expect(candidates().isEmpty)

        // Restoring the plain source invalidates archive reuse even if its metadata matches.
        metadata = .init(
            path: file.path,
            mtimeUnixMs: usage.mtimeUnixMs,
            size: usage.size,
            fileId: usage.codexScanFileId)
        #expect(candidates() == [file])
        metadata = .init(path: file.path, mtimeUnixMs: usage.mtimeUnixMs, size: usage.size, fileId: "1:43")
        #expect(candidates() == [file])
        metadata = .init(path: file.path, mtimeUnixMs: 0, size: 0, fileId: nil)
        cache.codexSessionDiscovery?.metadataPresenceEstablished = false
        #expect(candidates() == [file])
        cache.codexSessionDiscovery = discovery
        cache.codexSessionDiscovery?.metadataUnavailablePaths = [file.path]
        #expect(candidates() == [file])

        // A stale saved archive classification cannot hide a deleted archive from the sweep.
        cache.codexSessionDiscovery = discovery
        let missing = try index.takeMetadataRefreshCandidates(
            cache: &cache,
            dayKey: "2026-08-30",
            scanSinceKey: "2026-08-30",
            calendar: .current,
            visitLimit: 512,
            restartCompletedSweep: true)
        cache.codexSessionDiscovery = index.persistedState
        #expect(missing.contains(file))
        #expect(cache.files[file.path]?.codexArchived != true)
        #expect(candidates() == [file])
    }

    @Test
    func `an empty invalidated inventory can establish presence without restarting a sweep`() throws {
        let index = CostUsageScanner.CodexSessionFileIndex(files: [], roots: [])
        var cache = CostUsageCache()
        _ = try index.takeMetadataRefreshCandidates(
            cache: &cache,
            dayKey: "2026-08-30",
            scanSinceKey: "2026-08-30",
            calendar: .current,
            visitLimit: 512,
            restartCompletedSweep: false)
        #expect(index.persistedState.metadataPresenceEstablished == true)
        #expect(index.metadataPresenceVisits == 0)
    }

    @Test
    func `repeated status checks do not probe unchanged file presence`() {
        let files = (0..<1025).map { index in
            CostUsageStoreCatchUpFile(
                path: "/synthetic/\(index).jsonl",
                inode: 1,
                mtimeUnixMs: 1,
                size: 1,
                fileIdentity: "1:1",
                parsedBytes: 1,
                scanTargetSize: 1,
                resumeOffset: nil,
                scanComplete: true,
                forkedFromID: nil,
                forkBaselineDependencyKey: nil,
                hasBufferedSubagentLines: false,
                hasBufferedUnresolvedForkLines: false)
        }
        let counter = ArchivePresenceCounter()
        var hooks = CostUsageStoreTestHooks()
        hooks.codexRolloutPresenceVisit = { counter.increment() }
        CostUsageStoreTestHooks.$current.withValue(hooks) {
            for _ in 0..<3 {
                #expect(!CostUsageStore.codexCatchUpProjectionNeedsIdentityValidation(files: files, rootMtimes: nil))
            }
        }
        #expect(counter.value == 0)
    }

    private static func projection(_ discovery: CostUsageCodexSessionDiscovery) throws
    -> CostUsageStoreCatchUpProjection {
        var projection = CostUsageStoreCatchUpProjection.empty
        projection.discoveryState = try CostUsageStoreDiscoveryState(
            roots: discovery.roots,
            generation: discovery.generation,
            directoryPaths: discovery.directoryPaths,
            nextDirectoryIndex: discovery.nextDirectoryIndex,
            filePaths: discovery.filePaths,
            nextFileIndex: discovery.nextFileIndex,
            filePathBySessionID: discovery.filePathBySessionId,
            missingSessionIDs: discovery.missingSessionIds,
            pendingSessionIDs: discovery.pendingSessionIds,
            validationDirectoryIndex: discovery.validationDirectoryIndex,
            isComplete: discovery.isComplete,
            payload: JSONEncoder().encode(discovery))
        return projection
    }
}

private final class ArchivePresenceCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var visits = 0

    func increment() { self.lock.withLock { self.visits += 1 } }
    var value: Int {
        self.lock.withLock { self.visits }
    }
}
