import Foundation

extension CostUsageStore {
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
        var rowCounts: [String: Int]
        var fileAggregatesByPath: [String: [CostUsageStoreDayAggregate]]

        init(snapshot: CostUsageStoreSnapshot) {
            self.metadata = snapshot.metadata
            self.files = snapshot.files.map { file in
                var file = file
                // Resume data is already represented by the typed cache. Keep details payloads
                // because the QuotaKit writer uses their ledger/parser metadata during replace.
                file.scanState.resumePayload = nil
                return file
            }
            self.snapshotCounts = snapshot.tokenSnapshots.reduce(into: [:]) { $0[$1.path, default: 0] += 1 }
            self.rowCounts = snapshot.usageRows.reduce(into: [:]) { $0[$1.path, default: 0] += 1 }
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
        decoded: CostUsageCache? = nil) -> CodexDecodedBaseline
    {
        CodexDecodedBaseline(
            decoded: decoded ?? decodeCodexCache(from: snapshot),
            persistence: CodexPersistenceState(snapshot: snapshot),
            stamp: stamp)
    }

    func codexBaselineIsCurrent(_ baseline: CodexDecodedBaseline) -> Bool {
        self.currentCodexScanStamp() == baseline.stamp
    }

    #if DEBUG
    var retainedCodexBaselineCountForTesting: Int {
        self.retainedCodexBaseline == nil ? 0 : 1
    }
    #endif
}
