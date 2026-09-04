import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageRequestedWindowProjectionTests {
    @Test
    func `requested 30 day projection ignores older pending migration but rejects incomplete requested file`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let since = try env.makeLocalNoon(year: 2026, month: 8, day: 1)
        let until = try #require(Calendar.current.date(byAdding: .day, value: 29, to: since))
        let range = CostUsageScanner.CostUsageDayRange(since: since, until: until)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
        let rootPaths = roots.map(\.standardizedFileURL.path)

        let requestedURL = try env.writeCodexSessionFile(
            day: until,
            filename: "requested-window.jsonl",
            contents: "{}\n")
        let requestedMetadata = CostUsageScanner.codexFileMetadata(fileURL: requestedURL)
        let oldDay = try #require(Calendar.current.date(byAdding: .day, value: -40, to: since))
        let oldPendingURL = try env.writeCodexSessionFile(
            day: oldDay,
            filename: "old-pending-migration.jsonl",
            contents: "{}\n")
        try FileManager.default.setAttributes(
            [.modificationDate: oldDay],
            ofItemAtPath: oldPendingURL.path)
        let oldPendingMetadata = CostUsageScanner.codexFileMetadata(fileURL: oldPendingURL)

        var cache = CostUsageCache()
        cache.codexScanCatchUpPending = true
        cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
        cache.files[requestedURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: requestedMetadata.mtimeUnixMs,
            size: requestedMetadata.size,
            days: [range.untilKey: [:]],
            parsedBytes: requestedMetadata.size,
            codexScanFileId: requestedMetadata.fileId,
            codexScanComplete: true)
        cache.files[oldPendingURL.path] = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: oldPendingMetadata.mtimeUnixMs,
            size: oldPendingMetadata.size,
            days: [:],
            parsedBytes: 0,
            codexScanFileId: oldPendingMetadata.fileId,
            codexScanComplete: false)
        cache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: range.scanSinceKey,
            rootPaths: rootPaths,
            pendingFilePaths: [oldPendingURL.path],
            completedCurrentWindowRootPaths: rootPaths,
            completedCurrentWindowFlatRootPaths: rootPaths)

        #expect(CostUsageScanner.codexRequestedWindowProjectionCanPublish(
            cache: cache,
            roots: roots,
            sinceKey: range.sinceKey,
            untilKey: range.untilKey,
            calendar: range.calendar))

        var incompleteRequestedCache = cache
        incompleteRequestedCache.files[requestedURL.path]?.codexScanComplete = false
        #expect(!CostUsageScanner.codexRequestedWindowProjectionCanPublish(
            cache: incompleteRequestedCache,
            roots: roots,
            sinceKey: range.sinceKey,
            untilKey: range.untilKey,
            calendar: range.calendar))
    }
}
