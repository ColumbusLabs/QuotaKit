import Foundation

enum CodexScanHistoryHydrationRetryRegistry {
    struct CommitToken: Sendable {
        var revisionsByTarget: [String: UInt64] = [:]

        init() {}

        mutating func merge(_ other: Self) {
            for (target, revision) in other.revisionsByTarget {
                self.revisionsByTarget[target] = max(self.revisionsByTarget[target] ?? 0, revision)
            }
        }
    }

    private struct Entry: Sendable {
        var retry: CodexHistoryHydrationRetry
        var revision: UInt64
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var nextRevision: UInt64 = 0
    private nonisolated(unsafe) static var retriesByDatabasePath: [String: [String: Entry]] = [:]

    static func retain(
        databaseURL: URL,
        retries: [String: CodexHistoryHydrationRetry]) -> CommitToken
    {
        guard !retries.isEmpty else { return CommitToken() }
        self.lock.lock()
        defer { self.lock.unlock() }
        let databasePath = databaseURL.standardizedFileURL.path
        self.nextRevision &+= 1
        let revision = self.nextRevision
        var stored = self.retriesByDatabasePath[databasePath] ?? [:]
        var token = CommitToken()
        for (target, retry) in retries {
            if var existing = stored[target] {
                existing.retry.merge(retry)
                existing.revision = revision
                stored[target] = existing
            } else {
                stored[target] = Entry(retry: retry, revision: revision)
            }
            token.revisionsByTarget[target] = revision
        }
        self.retriesByDatabasePath[databasePath] = stored
        return token
    }

    static func mergePending(databaseURL: URL, into cache: inout CostUsageCache) -> CommitToken {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let stored = self.retriesByDatabasePath[databaseURL.standardizedFileURL.path] else {
            return CommitToken()
        }
        var retries = cache.codexHistoryHydrationRetries ?? [:]
        var token = CommitToken()
        for (target, entry) in stored {
            if var existing = retries[target] {
                existing.merge(entry.retry)
                retries[target] = existing
            } else {
                retries[target] = entry.retry
            }
            token.revisionsByTarget[target] = entry.revision
        }
        cache.codexHistoryHydrationRetries = retries
        if !stored.isEmpty {
            cache.codexScanCatchUpPending = true
        }
        return token
    }

    static func clear(databaseURL: URL, committed token: CommitToken) {
        guard !token.revisionsByTarget.isEmpty else { return }
        self.lock.lock()
        defer { self.lock.unlock() }
        let databasePath = databaseURL.standardizedFileURL.path
        guard var stored = self.retriesByDatabasePath[databasePath] else { return }
        for (target, committedRevision) in token.revisionsByTarget {
            guard let current = stored[target], current.revision <= committedRevision else { continue }
            stored.removeValue(forKey: target)
        }
        if stored.isEmpty {
            self.retriesByDatabasePath.removeValue(forKey: databasePath)
        } else {
            self.retriesByDatabasePath[databasePath] = stored
        }
    }
}

final class CodexScanHistoryHydrator {
    enum Result: Equatable {
        case ready
        case stale
        case unavailable
    }

    private let storeLoad: CostUsageStoreLoad
    private let checkCancellation: CostUsageScanner.CancellationCheck?
    private var snapshotsByPath: [String: [CostUsageCodexTokenSnapshot]] = [:]
    private(set) var retryDescriptors: [String: CodexHistoryHydrationRetry] = [:]
    private(set) var retryRegistryToken = CodexScanHistoryHydrationRetryRegistry.CommitToken()

    init(
        storeLoad: CostUsageStoreLoad,
        checkCancellation: CostUsageScanner.CancellationCheck?)
    {
        self.storeLoad = storeLoad
        self.checkCancellation = checkCancellation
    }

    func hydrate(
        paths: Set<String>,
        retryTargetPath: String? = nil,
        retainedPaths: Set<String>? = nil) throws -> Result
    {
        guard !paths.isEmpty else { return .ready }
        try self.checkCancellation?()
        guard let receipt = self.storeLoad.receipt,
              let scanStamp = self.storeLoad.scanStamp
        else {
            self.retainRetryDescriptor(targetPath: retryTargetPath, retainedPaths: retainedPaths ?? paths)
            return .unavailable
        }

        let result = self.storeLoad.store.syncHydrateCodexTokenSnapshots(
            paths: paths,
            receipt: receipt,
            expectedScanStamp: scanStamp)
        switch result {
        case let .loaded(snapshots):
            try self.checkCancellation?()
            for (path, stored) in snapshots {
                self.snapshotsByPath[path] = stored.map(CostUsageStore.tokenSnapshot(from:))
            }
            return .ready
        case .stale:
            self.retainRetryDescriptor(targetPath: retryTargetPath, retainedPaths: retainedPaths ?? paths)
            try self.checkCancellation?()
            return .stale
        case .unavailable:
            self.retainRetryDescriptor(targetPath: retryTargetPath, retainedPaths: retainedPaths ?? paths)
            try self.checkCancellation?()
            return .unavailable
        }
    }

    private func retainRetryDescriptor(targetPath: String?, retainedPaths: Set<String>) {
        guard let targetPath else { return }
        let resolvedPath = Self.resolvedPath(URL(fileURLWithPath: targetPath))
        let retry = CodexHistoryHydrationRetry(retainedPaths: retainedPaths, forceFullRescan: true)
        if var existing = self.retryDescriptors[resolvedPath] {
            existing.merge(retry)
            self.retryDescriptors[resolvedPath] = existing
        } else {
            self.retryDescriptors[resolvedPath] = retry
        }
        let token = CodexScanHistoryHydrationRetryRegistry.retain(
            databaseURL: self.storeLoad.store.databaseURL,
            retries: [resolvedPath: retry])
        self.retryRegistryToken.merge(token)
    }

    private static func resolvedPath(_ url: URL) -> String {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix("/private/var/")
            ? String(path.dropFirst("/private".count))
            : path
    }

    func usageWithHydratedSnapshots(
        _ usage: CostUsageFileUsage,
        path: String) -> CostUsageFileUsage
    {
        guard usage.codexTokenSnapshots == nil,
              let snapshots = self.snapshotsByPath[path]
              ?? self.snapshotsByPath[URL(fileURLWithPath: path).standardizedFileURL.path]
        else { return usage }
        var usage = usage
        usage.codexTokenSnapshots = snapshots
        usage.codexTokenCheckpoints = CostUsageScanner.codexTokenCheckpoints(for: snapshots)
        return usage
    }

    func applyHydratedSnapshots(to cache: inout CostUsageCache) {
        for (path, snapshots) in self.snapshotsByPath {
            guard var usage = cache.files[path], usage.codexTokenSnapshots == nil else { continue }
            usage.codexTokenSnapshots = snapshots
            usage.codexTokenCheckpoints = CostUsageScanner.codexTokenCheckpoints(for: snapshots)
            cache.files[path] = usage
        }
    }
}

extension CostUsageScanner {
    static func pruneForceRescanFilesOutsideWindow(
        cache: inout CostUsageCache,
        range: CostUsageDayRange,
        isForceRescan: Bool,
        preservingPaths: Set<String> = [])
    {
        guard isForceRescan else { return }
        for key in cache.files.keys {
            guard !preservingPaths.contains(key), let old = cache.files[key] else { continue }
            guard !old.touchesCodexScanWindow(
                sinceKey: range.scanSinceKey,
                untilKey: range.scanUntilKey,
                calendar: range.calendar)
            else { continue }
            Self.applyFileDays(cache: &cache, fileDays: old.days, sign: -1)
            cache.files.removeValue(forKey: key)
        }
    }

    static func codexHistoryRetryPathKeys(
        cache: CostUsageCache) -> (all: Set<String>, forceFullScan: Set<String>)
    {
        var all: Set<String> = []
        var forceFullScan: Set<String> = []
        for (path, retry) in cache.codexHistoryHydrationRetries ?? [:] {
            let key = Self.codexPathKey(URL(fileURLWithPath: path))
            all.insert(key)
            if retry.forceFullRescan {
                forceFullScan.insert(key)
            }
        }
        return (all, forceFullScan)
    }
}
