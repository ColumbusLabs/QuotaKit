import Foundation

extension CostUsageStore {
    enum CodexTokenSnapshotHydrationResult: Sendable {
        case loaded([String: [CostUsageStoreTokenSnapshot]])
        case stale
        case unavailable
    }

    /// An unforgeable handle to the one decoded store snapshot retained for a scanner pass.
    /// It intentionally carries no cache state or SQLite connection across the scanner boundary.
    final class CodexBaselineReceipt: Sendable {
        let id = UUID()
        private let store: CostUsageStore

        init(store: CostUsageStore) {
            self.store = store
        }

        deinit {
            let store = self.store
            let id = self.id
            Task { await store.releaseCodexBaseline(id: id) }
        }
    }

    struct CodexPersistenceState {
        var metadata: CostUsageStoreMetadata
        var files: [CostUsageStoreFile]
        var snapshotCounts: [String: Int]
        var tokenSnapshotsLoaded: Bool
        var tokenSnapshotMarkersByPath: [String: Bool]
        var unloadedTokenSnapshotPaths: Set<String>
        var malformedDetailsPaths: Set<String>
        var rowCounts: [String: Int]
        var fileAggregatesByPath: [String: [CostUsageStoreDayAggregate]]

        init(
            snapshot: CostUsageStoreSnapshot,
            tokenSnapshotMarkersByPath: [String: Bool] = [:],
            usageRowCountsByPath: [String: Int]? = nil)
        {
            self.metadata = snapshot.metadata
            self.files = snapshot.files.map { file in
                var file = file
                // Resume data is already represented by the typed cache. Keep details payloads
                // because the QuotaKit writer uses their ledger/parser metadata during replace.
                file.scanState.resumePayload = nil
                return file
            }
            self.snapshotCounts = snapshot.tokenSnapshotCounts
                ?? snapshot.tokenSnapshots.reduce(into: [:]) { $0[$1.path, default: 0] += 1 }
            self.tokenSnapshotsLoaded = snapshot.tokenSnapshotsLoaded
            self.tokenSnapshotMarkersByPath = tokenSnapshotMarkersByPath
            self.malformedDetailsPaths = CostUsageStore.codexMalformedDetailsPaths(from: snapshot.files)
            self.unloadedTokenSnapshotPaths = snapshot.tokenSnapshotsLoaded
                ? []
                : Set(self.snapshotCounts.compactMap { path, count in count > 0 ? path : nil })
                .union(self.malformedDetailsPaths)
            self.rowCounts = usageRowCountsByPath
                ?? snapshot.usageRows.reduce(into: [:]) { $0[$1.path, default: 0] += 1 }
            self.fileAggregatesByPath = Dictionary(grouping: snapshot.fileDayAggregates, by: \.path)
                .mapValues { $0.map(\.aggregate) }
        }
    }

    struct CodexDecodedBaseline {
        var decoded: CostUsageCache
        var persistence: CodexPersistenceState
        var stamp: CodexScanStamp
    }

    struct RetainedCodexBaseline {
        var id: UUID
        var baseline: CodexDecodedBaseline?
    }

    func releaseCodexBaseline(_ receipt: CodexBaselineReceipt) {
        self.releaseCodexBaseline(id: receipt.id)
    }

    func releaseCodexBaseline(id: UUID) {
        guard self.retainedCodexBaseline?.id == id else { return }
        self.retainedCodexBaseline = nil
        #if DEBUG
        let observer = self.codexBaselineReleaseObserverForTesting
        self.codexBaselineReleaseObserverForTesting = nil
        observer?()
        #endif
    }

    func takeCodexBaseline(_ receipt: CodexBaselineReceipt?) -> CodexDecodedBaseline? {
        guard let receipt else {
            self.retainedCodexBaseline = nil
            return self.readCodexBaseline()
        }
        guard self.retainedCodexBaseline?.id == receipt.id else { return nil }
        defer { self.retainedCodexBaseline = nil }
        return self.retainedCodexBaseline?.baseline
    }

    func readCodexBaseline() -> CodexDecodedBaseline? {
        guard let read = self.readStampedCodexScanSnapshot() else { return nil }
        return Self.codexBaseline(from: read.snapshot, stamp: read.stamp)
    }

    static func codexBaseline(
        from snapshot: CostUsageStoreSnapshot,
        stamp: CodexScanStamp,
        decoded: CostUsageCache? = nil,
        usageRowsByPath: [String: [CostUsageScanner.CodexUsageRow]]? = nil,
        usageRowCountsByPath: [String: Int]? = nil) -> CodexDecodedBaseline
    {
        let decoded = decoded ?? Self.decodeCodexCache(
            from: snapshot,
            tokenSnapshotsLoaded: snapshot.tokenSnapshotsLoaded,
            preserveMalformedFiles: !snapshot.tokenSnapshotsLoaded,
            decodedUsageRowsByPath: usageRowsByPath)
        var persistence = CodexPersistenceState(
            snapshot: snapshot,
            tokenSnapshotMarkersByPath: Self.codexTokenSnapshotMarkersByPath(from: snapshot.files),
            usageRowCountsByPath: usageRowCountsByPath)
        if !snapshot.tokenSnapshotsLoaded {
            persistence.unloadedTokenSnapshotPaths = Set(persistence.snapshotCounts.compactMap { path, count in
                guard count > 0, decoded.files[path]?.codexTokenSnapshots == nil else { return nil }
                return path
            }).union(persistence.malformedDetailsPaths)
        }
        return CodexDecodedBaseline(
            decoded: decoded,
            persistence: persistence,
            stamp: stamp)
    }

    func codexBaselineIsCurrent(_ baseline: CodexDecodedBaseline) -> Bool {
        self.currentCodexScanStamp() == baseline.stamp
    }

    /// Retention and budget enforcement may write while the save owns the writer lock.
    /// Re-read their result before using it as a new content certificate; external changes
    /// still invalidate the original baseline through every stamp field except totalChanges.
    func codexBaselineAfterRetention(_ baseline: CodexDecodedBaseline) -> CodexDecodedBaseline? {
        guard let current = self.currentCodexScanStamp() else { return nil }
        if current == baseline.stamp { return baseline }
        var expected = baseline.stamp
        expected.totalChanges = current.totalChanges
        let loadedTokenSnapshotPaths = Set(baseline.persistence.snapshotCounts.compactMap { path, count in
            guard count > 0,
                  baseline.decoded.files[path]?.codexTokenSnapshots != nil
            else { return nil }
            return path
        })
        guard expected == current,
              let read = self.readCodexScanSnapshotInCurrentTransaction(
                  loadTokenSnapshots: baseline.persistence.tokenSnapshotsLoaded,
                  loadedTokenSnapshotPaths: loadedTokenSnapshotPaths),
              read.stamp == current
        else { return nil }
        return Self.codexBaseline(
            from: read.snapshot,
            stamp: read.stamp,
            usageRowsByPath: read.usageRowsByPath,
            usageRowCountsByPath: read.usageRowCountsByPath)
    }

    #if DEBUG
    var retainedCodexBaselineCountForTesting: Int {
        self.retainedCodexBaseline == nil ? 0 : 1
    }
    #endif
}
