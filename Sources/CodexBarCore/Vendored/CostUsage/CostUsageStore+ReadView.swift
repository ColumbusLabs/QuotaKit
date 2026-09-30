import Foundation

/// Immutable adapter for report builders and status progress. Its scanner-shaped cache remains
/// private so omitted history can never become a scanner persistence baseline.
struct CostUsageStoreReadView: Sendable {
    fileprivate let cache: CostUsageCache
    fileprivate let catchUpProjection: CostUsageStoreCatchUpProjection?

    init(cache: CostUsageCache, catchUpProjection: CostUsageStoreCatchUpProjection? = nil) {
        self.cache = cache
        self.catchUpProjection = catchUpProjection
    }

    var roots: [String: Int64]? {
        self.cache.roots
    }

    var timeZoneIdentifier: String? {
        self.cache.timeZoneIdentifier
    }

    var scanSinceKey: String? {
        self.cache.scanSinceKey
    }

    var scanUntilKey: String? {
        self.cache.scanUntilKey
    }

    var lastScanUnixMs: Int64 {
        self.cache.lastScanUnixMs
    }

    var projectMetadataVersion: Int? {
        self.cache.codexProjectMetadataVersion
    }

    var days: [String: [String: [Int]]] {
        self.cache.days
    }

    var hasPendingScan: Bool {
        self.cache.codexScanCatchUpPending == true || self.cache.files.values.contains {
            $0.codexScanComplete == false || $0.hasBufferedCodexForkRetryLines
        }
    }

    func scoped(to roots: [URL]) -> Self {
        Self(
            cache: CostUsageScanner.codexCache(self.cache, scopedTo: roots),
            catchUpProjection: self.catchUpProjection)
    }

    func windowExpandsCache(_ range: CostUsageScanner.CostUsageDayRange) -> Bool {
        CostUsageScanner.requestedWindowExpandsCache(range: range, cache: self.cache)
    }

    func historyCoverageIsEstablished(
        range: CostUsageScanner.CostUsageDayRange,
        rootsFingerprint: [String: Int64]) -> Bool
    {
        self.lastScanUnixMs > 0
            && self.timeZoneIdentifier == range.calendar.timeZone.identifier
            && self.roots == rootsFingerprint
            && !self.hasPendingScan
            && !self.windowExpandsCache(range)
    }

    func previousReport(
        range: CostUsageScanner.CostUsageDayRange,
        rootsFingerprint: [String: Int64]) -> CostUsageCodexPreviousReport?
    {
        CostUsageScanner.codexPreviousReport(cache: self.cache, range: range, rootsFingerprint: rootsFingerprint)
    }

    func dailyReport(range: CostUsageScanner.CostUsageDayRange, cacheRoot: URL?) -> CostUsageDailyReport {
        CostUsageScanner.buildCodexReportFromCache(
            cache: self.cache,
            range: range,
            modelsDevCacheRoot: cacheRoot)
    }

    func projects(range: CostUsageScanner.CostUsageDayRange, cacheRoot: URL?) -> [CostUsageProjectBreakdown] {
        CostUsageScanner.buildCodexProjectBreakdownsFromCache(
            cache: self.cache,
            range: range,
            modelsDevCacheRoot: cacheRoot)
    }

    func sessions(
        range: CostUsageScanner.CostUsageDayRange,
        cacheRoot: URL?,
        roots: [URL]) -> [CostUsageSessionBreakdown]
    {
        CostUsageScanner.buildCodexSessionBreakdownsFromCache(
            cache: self.cache,
            range: range,
            modelsDevCacheRoot: cacheRoot,
            sessionRoots: roots)
    }

    func catchUpStatus(
        roots: [URL],
        rootsFingerprint: [String: Int64]) -> CostUsageFetcher.CodexScanCatchUpStatus
    {
        let projection = self.catchUpProjection ?? .empty
        guard projection.rootMtimes == rootsFingerprint else {
            return .init(pending: false, progressKey: "scope-mismatch")
        }
        let scopedFiles = projection.files.filter {
            CostUsageScanner.isWithinCodexRoots(fileURL: URL(fileURLWithPath: $0.path), roots: roots)
        }
        let needsIdentityValidation = CostUsageStore.codexCatchUpProjectionNeedsIdentityValidation(
            files: scopedFiles,
            rootMtimes: projection.rootMtimes)
        let hasIncompleteFile = scopedFiles.contains { !$0.scanComplete }
        let pending = projection.catchUpPending || hasIncompleteFile || needsIdentityValidation
        let staleSnapshotUpdatedAt = projection.previousReportUpdatedAtUnixMs.flatMap { timestamp -> Date? in
            guard timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        }
        return .init(
            pending: pending,
            progressKey: CostUsageFetcher.codexScanProgressKey(
                projection: projection,
                scopedFiles: scopedFiles),
            processedBytes: projection.processedBytes ?? 0,
            totalBytes: projection.totalBytes ?? 0,
            completedFiles: projection.completedFiles ?? 0,
            totalFiles: projection.totalFiles ?? 0,
            staleSnapshotUpdatedAt: pending ? staleSnapshotUpdatedAt : nil)
    }
}

enum CostUsageStoreReadPurpose: Equatable, Sendable {
    case status
    /// Scoped token totals and coverage only; no event-level history.
    case activity
    /// Detailed report input stays transient and never replaces a retained activity view.
    case report

    func includes(_ requested: Self) -> Bool {
        self == requested || self == .report || (self == .activity && requested == .status)
    }
}

struct RetainedCodexRead {
    var decoded: CostUsageCache
    var persistence: CostUsageStore.CodexPersistenceState
    var catchUpProjection: CostUsageStoreCatchUpProjection?
    var stamp: CostUsageStore.CodexScanStamp
    var purpose: CostUsageStoreReadPurpose
}

extension CostUsageStoreAccess {
    /// Separate from the scanner registry so read projections never share writer baselines.
    final class ReadStoreRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(path: String, store: CostUsageStore)] = []
        private let capacity: Int

        init(capacity: Int = 4) {
            self.capacity = max(1, capacity)
        }

        func store(cacheRoot: URL?) -> CostUsageStore {
            let candidate = CostUsageStore(cacheRoot: cacheRoot)
            let path = candidate.databaseURL.standardizedFileURL.path
            return self.lock.withLock {
                let store: CostUsageStore = if let index = self.entries.firstIndex(where: { $0.path == path }) {
                    self.entries.remove(at: index).store
                } else {
                    candidate
                }
                self.entries.append((path, store))
                if self.entries.count > self.capacity { self.entries.removeFirst() }
                return store
            }
        }
    }

    private static let readStores = ReadStoreRegistry()

    static func readView(
        cacheRoot: URL?,
        calendar: Calendar,
        purpose: CostUsageStoreReadPurpose) -> CostUsageStoreReadView
    {
        self.readStores.store(cacheRoot: cacheRoot)
            .syncLoadCodexReadView(calendar: calendar, purpose: purpose)
    }
}
