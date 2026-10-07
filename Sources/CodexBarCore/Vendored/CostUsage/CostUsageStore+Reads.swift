import Foundation

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

// MARK: - Typed reads

extension CostUsageStore {
    func fetchFile(path: String) -> CostUsageStoreFile? {
        self.withDatabase(default: nil) { database in
            let statement = try Self.prepare(database, Self.fileSelectSQL + " WHERE path = ?")
            defer { sqlite3_finalize(statement) }
            Self.bind(path, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try Self.decodeFile(statement)
        }
    }

    func fetchTokenSnapshots(path: String) -> [CostUsageStoreTokenSnapshot] {
        self.withDatabase(default: []) { database in
            try Self.readTokenSnapshots(database, path: path, storeURL: self.databaseURL)
        }
    }

    func hydrateCodexTokenSnapshots(
        paths: Set<String>,
        receipt: CodexBaselineReceipt,
        expectedScanStamp: CodexScanStamp) -> CodexTokenSnapshotHydrationResult
    {
        guard !paths.isEmpty,
              let retained = self.retainedCodexBaseline,
              retained.id == receipt.id,
              let baseline = retained.baseline,
              baseline.stamp == expectedScanStamp,
              self.currentCodexScanStamp() == expectedScanStamp
        else { return .stale }

        let unloadedPaths = paths.intersection(baseline.persistence.unloadedTokenSnapshotPaths)
        guard unloadedPaths.allSatisfy({
            baseline.persistence.malformedDetailsPaths.contains($0)
                || (baseline.persistence.tokenSnapshotMarkersByPath[$0] == true
                    && (baseline.persistence.snapshotCounts[$0] ?? 0) > 0)
        }) else { return .unavailable }
        guard !unloadedPaths.isEmpty else { return .loaded([:]) }
        #if DEBUG
        if CostUsageStoreTestHooks.current
            .codexTokenSnapshotHydrationFailure?(self.databaseURL, unloadedPaths) == true
        {
            return .unavailable
        }
        #endif

        let read = self.withDatabase(default: nil) { database -> (
            snapshots: [CostUsageStoreTokenSnapshot],
            counts: [String: Int])? in
            try Self.inReadTransaction(database) {
                try (
                    snapshots: Self.readTokenSnapshots(
                        database,
                        paths: unloadedPaths,
                        storeURL: self.databaseURL),
                    counts: Self.readTokenSnapshotCounts(database, paths: unloadedPaths))
            }
        }
        guard let read else { return .unavailable }
        guard self.currentCodexScanStamp() == expectedScanStamp,
              self.retainedCodexBaseline?.id == receipt.id
        else { return .stale }

        let snapshotsByPath = Dictionary(grouping: read.snapshots, by: \.path)
        var hydratedByPath: [String: [CostUsageStoreTokenSnapshot]] = [:]
        for path in unloadedPaths {
            let expectedCount = baseline.persistence.snapshotCounts[path] ?? -1
            let snapshots = snapshotsByPath[path] ?? []
            if baseline.persistence.malformedDetailsPaths.contains(path), expectedCount == 0 {
                guard read.counts[path] == 0, snapshots.isEmpty else { return .unavailable }
                hydratedByPath[path] = []
            } else {
                guard expectedCount > 0,
                      read.counts[path] == expectedCount,
                      snapshots.count == expectedCount,
                      snapshots.enumerated().allSatisfy({ $0.offset == $0.element.eventIndex })
                else { return .unavailable }
                hydratedByPath[path] = snapshots
            }
        }

        var updatedBaseline = baseline
        for path in unloadedPaths {
            let snapshots = (hydratedByPath[path] ?? []).map(Self.tokenSnapshot(from:))
            if var usage = updatedBaseline.decoded.files[path] {
                usage.codexTokenSnapshots = snapshots
                usage.codexTokenCheckpoints = CostUsageScanner.codexTokenCheckpoints(for: snapshots)
                updatedBaseline.decoded.files[path] = usage
            }
            updatedBaseline.persistence.unloadedTokenSnapshotPaths.remove(path)
        }
        self.retainedCodexBaseline = RetainedCodexBaseline(id: receipt.id, baseline: updatedBaseline)

        if let retainedCache = self.retainedCodexScan, retainedCache.stamp == expectedScanStamp {
            var cache = retainedCache.cache
            for path in unloadedPaths {
                guard var usage = cache.files[path] else { continue }
                let snapshots = (hydratedByPath[path] ?? []).map(Self.tokenSnapshot(from:))
                usage.codexTokenSnapshots = snapshots
                usage.codexTokenCheckpoints = CostUsageScanner.codexTokenCheckpoints(for: snapshots)
                cache.files[path] = usage
            }
            self.retainedCodexScan = (expectedScanStamp, cache)
        }
        return .loaded(hydratedByPath)
    }

    func fetchUsageRows(path: String) -> [CostUsageStoreUsageRow] {
        self.withDatabase(default: []) { database in
            try Self.readUsageRows(database, path: path)
        }
    }

    func fetchDetailCounts(path: String) -> (snapshotCount: Int, rowCount: Int) {
        self.withDatabase(default: (0, 0)) { database in
            let statement = try Self.prepare(database, """
            SELECT
                (SELECT COUNT(*) FROM token_snapshots WHERE file_id = f.id),
                (SELECT COUNT(*) FROM usage_rows WHERE file_id = f.id)
            FROM files f WHERE f.path = ?
            """)
            defer { sqlite3_finalize(statement) }
            Self.bind(path, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_ROW else { return (0, 0) }
            return (Int(sqlite3_column_int64(statement, 0)), Int(sqlite3_column_int64(statement, 1)))
        }
    }

    func fetchDayAggregates(sinceDay: String, untilDay: String) -> [CostUsageStoreDayAggregate] {
        guard sinceDay <= untilDay else { return [] }
        return self.withDatabase(default: []) { database in
            try Self.readDayAggregates(database, sinceDay: sinceDay, untilDay: untilDay)
        }
    }

    func fetchFileDayAggregates(path: String) -> [CostUsageStoreDayAggregate] {
        self.withDatabase(default: []) { database in
            try Self.readFileDayAggregates(database, path: path).map(\.aggregate)
        }
    }

    func fetchForkLineage(path: String) -> CostUsageStoreForkLineage? {
        self.withDatabase(default: nil) { database in
            let values = try Self.readForkLineage(database, path: path)
            return values.first
        }
    }

    func fetchBufferedLines(
        path: String,
        kind: CostUsageStoreBufferedLineKind? = nil) -> [CostUsageStoreBufferedLine]
    {
        self.withDatabase(default: []) { database in
            try Self.readBufferedLines(database, path: path, kind: kind)
        }
    }

    func fetchDiscoveryState() -> CostUsageStoreDiscoveryState? {
        self.readSingleton(CostUsageStoreDiscoveryState.self, table: "discovery_state")
    }

    func fetchLookbackState() -> CostUsageStoreLookbackState? {
        self.readSingleton(CostUsageStoreLookbackState.self, table: "lookback_state")
    }

    func fetchMetadata() -> CostUsageStoreMetadata {
        self.readSingleton(CostUsageStoreMetadata.self, table: "scan_metadata") ?? .empty
    }

    func fetchAccumulator(path: String) -> CostUsageStoreAccumulator? {
        self.withDatabase(default: nil) { database in
            try Self.readAccumulators(database, path: path).first
        }
    }

    /// Finds only files whose persisted usage rows mention one of the changed priority turn IDs.
    /// The payload is intentionally queried in SQLite so a priority metadata update does not
    /// require hydrating every file's event ledger into Swift memory.
    func pathsContainingCodexTurnIDs(_ turnIDs: Set<String>) throws -> Set<String> {
        guard !turnIDs.isEmpty else { return [] }
        let database = try self.ensureDatabase()
        return try Self.inReadTransaction(database) {
            var paths: Set<String> = []
            let sortedTurnIDs = turnIDs.sorted()
            for start in stride(from: 0, to: sortedTurnIDs.count, by: 500) {
                let chunk = sortedTurnIDs[start..<min(start + 500, sortedTurnIDs.count)]
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let statement = try Self.prepare(database, """
                SELECT DISTINCT f.path
                FROM usage_rows r
                JOIN files f ON f.id = r.file_id
                WHERE json_extract(r.payload, '$.turnID') IN (\(placeholders))
                ORDER BY f.path
                """)
                defer { sqlite3_finalize(statement) }
                for (index, turnID) in chunk.enumerated() {
                    Self.bind(turnID, to: statement, at: Int32(index + 1))
                }
                var result = sqlite3_step(statement)
                while result == SQLITE_ROW {
                    guard let path = Self.columnText(statement, at: 0) else {
                        throw StoreError.invalidData
                    }
                    paths.insert(path)
                    result = sqlite3_step(statement)
                }
                guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
            }
            return paths
        }
    }

    func readReport(sinceDay: String, untilDay: String) -> CostUsageStoreReport {
        guard sinceDay <= untilDay else {
            return CostUsageStoreReport(metadata: .empty, aggregates: [])
        }
        return self.withDatabase(default: CostUsageStoreReport(metadata: .empty, aggregates: [])) { database in
            try Self.inReadTransaction(database) {
                let metadata = try Self.readSingleton(
                    CostUsageStoreMetadata.self,
                    database: database,
                    table: "scan_metadata") ?? .empty
                let aggregates = try Self.readDayAggregates(
                    database,
                    sinceDay: sinceDay,
                    untilDay: untilDay)
                return CostUsageStoreReport(metadata: metadata, aggregates: aggregates)
            }
        }
    }

    func readCodexCatchUpProjection(calendar: Calendar) -> CostUsageStoreCatchUpProjection {
        self.withDatabase(default: .empty) { database in
            try Self.inReadTransaction(database) {
                let metadata = try Self.readCodexCatchUpMetadata(database)
                guard metadata.timeZoneIdentifier == nil
                    || metadata.timeZoneIdentifier == calendar.timeZone.identifier
                else { return .empty }

                let files = try Self.readCodexCatchUpFiles(database)
                let discoveryState = try Self.readSingleton(
                    CostUsageStoreDiscoveryState.self,
                    database: database,
                    table: "discovery_state")
                let lookbackState = try Self.readSingleton(
                    CostUsageStoreLookbackState.self,
                    database: database,
                    table: "lookback_state")
                return CostUsageStoreCatchUpProjection(
                    rootMtimes: metadata.rootMtimes,
                    catchUpPending: metadata.catchUpPending,
                    processedBytes: metadata.processedBytes,
                    totalBytes: metadata.totalBytes,
                    completedFiles: metadata.completedFiles,
                    totalFiles: metadata.totalFiles,
                    scanInventoryPaths: metadata.scanInventoryPaths,
                    previousReportUpdatedAtUnixMs: metadata.previousReportUpdatedAtUnixMs,
                    files: files,
                    discoveryState: discoveryState,
                    lookbackState: lookbackState)
            }
        }
    }

    /// Builds the persisted v3 status input inside an existing read transaction, without loading
    /// token history or changing the status hash to the activity-cache representation.
    static func readCodexCatchUpProjection(
        _ database: OpaquePointer,
        metadata: CostUsageStoreMetadata,
        discoveryState: CostUsageStoreDiscoveryState?,
        lookbackState: CostUsageStoreLookbackState?) throws -> CostUsageStoreCatchUpProjection
    {
        try CostUsageStoreCatchUpProjection(
            rootMtimes: metadata.rootMtimes,
            catchUpPending: metadata.catchUpPending,
            processedBytes: metadata.processedBytes,
            totalBytes: metadata.totalBytes,
            completedFiles: metadata.completedFiles,
            totalFiles: metadata.totalFiles,
            scanInventoryPaths: metadata.scanInventoryPaths,
            previousReportUpdatedAtUnixMs: try? metadata.previousReportPayload.flatMap { payload in
                try JSONDecoder().decode(PreviousReportTimestamp.self, from: payload).updatedAtUnixMs
            },
            files: readCodexCatchUpFiles(database),
            discoveryState: discoveryState,
            lookbackState: lookbackState)
    }

    func readSnapshot(loadTokenSnapshots: Bool = true) -> CostUsageStoreSnapshot {
        #if DEBUG
        CostUsageStoreTestHooks.current.snapshotRead?(self.databaseURL)
        #endif
        return self.withDatabase(default: Self.emptySnapshot) { database in
            try Self.inReadTransaction(database) {
                try Self.readSnapshot(
                    database,
                    loadTokenSnapshots: loadTokenSnapshots,
                    storeURL: self.databaseURL)
            }
        }
    }

    /// Attach the stamp only after the read transaction commits. A concurrent writer must not
    /// let a decoded older snapshot borrow a newer stamp.
    func readStampedCodexScanSnapshot(
        loadTokenSnapshots: Bool = true) -> (
        snapshot: CostUsageStoreSnapshot,
        stamp: CodexScanStamp,
        usageRowsByPath: [String: [CostUsageScanner.CodexUsageRow]]?,
        usageRowCountsByPath: [String: Int]?)?
    {
        self.withDatabase(default: nil) { database in
            guard let before = self.currentCodexScanStamp() else { return nil }
            #if DEBUG
            CostUsageStoreTestHooks.current.snapshotRead?(self.databaseURL)
            #endif
            let read = try Self.inReadTransaction(database) { () -> (
                snapshot: CostUsageStoreSnapshot,
                usageRowsByPath: [String: [CostUsageScanner.CodexUsageRow]]?,
                usageRowCountsByPath: [String: Int]?) in
                var snapshot = try Self.readSnapshot(
                    database,
                    loadTokenSnapshots: loadTokenSnapshots,
                    loadUsageRows: false,
                    storeURL: self.databaseURL)
                var usageRowsByPath: [String: [CostUsageScanner.CodexUsageRow]]?
                var usageRowCountsByPath: [String: Int]?
                if !loadTokenSnapshots {
                    let markers = Self.codexTokenSnapshotMarkersByPath(from: snapshot.files)
                    let accumulators = Dictionary(uniqueKeysWithValues: snapshot.accumulators.map { ($0.path, $0) })
                    var counts: [String: Int] = [:]
                    var fallbackPaths: Set<String> = []
                    for file in snapshot.files {
                        guard file.scanState.replacementScanPending != true,
                              markers[file.path] == true,
                              let accumulator = accumulators[file.path],
                              accumulator.eventCount > 0
                        else {
                            fallbackPaths.insert(file.path)
                            continue
                        }
                        counts[file.path] = accumulator.eventCount
                    }
                    if !fallbackPaths.isEmpty {
                        try counts.merge(
                            Self.readTokenSnapshotCounts(database, paths: fallbackPaths),
                            uniquingKeysWith: { _, exact in exact })
                    }
                    snapshot.tokenSnapshotCounts = counts
                    snapshot.tokenSnapshotsLoaded = false
                }
                let usageRows = try Self.readDecodedUsageRows(database)
                usageRowsByPath = usageRows.rowsByPath
                usageRowCountsByPath = usageRows.rowCountsByPath
                return (snapshot, usageRowsByPath, usageRowCountsByPath)
            }
            guard let after = self.currentCodexScanStamp(), before == after else { return nil }
            return (
                snapshot: read.snapshot,
                stamp: after,
                usageRowsByPath: read.usageRowsByPath,
                usageRowCountsByPath: read.usageRowCountsByPath)
        }
    }

    /// Reads only indexed row counts; event payloads remain in SQLite until a requested path is
    /// hydrated under its retained scan receipt.
    private static func readTokenSnapshotCounts(
        _ database: OpaquePointer,
        paths: Set<String>? = nil) throws -> [String: Int]
    {
        if let paths, paths.isEmpty { return [:] }
        let pathGroups: [[String]?]
        if let paths {
            let sortedPaths = paths.sorted()
            pathGroups = stride(from: 0, to: sortedPaths.count, by: 500).map { start in
                Array(sortedPaths[start..<min(start + 500, sortedPaths.count)])
            }
        } else {
            pathGroups = [nil]
        }
        var counts: [String: Int] = [:]
        for pathGroup in pathGroups {
            var sql = """
            SELECT f.path, COUNT(t.event_index)
            FROM files f
            LEFT JOIN token_snapshots t ON t.file_id = f.id
            """
            if let pathGroup {
                sql += " WHERE f.path IN (" + Array(repeating: "?", count: pathGroup.count).joined(separator: ",") + ")"
                counts.merge(
                    Dictionary(uniqueKeysWithValues: pathGroup.map { ($0, 0) }),
                    uniquingKeysWith: { old, _ in old })
            }
            sql += " GROUP BY f.id ORDER BY f.path"
            let statement = try Self.prepare(database, sql)
            defer { sqlite3_finalize(statement) }
            for (index, path) in (pathGroup ?? []).enumerated() {
                Self.bind(path, to: statement, at: Int32(index + 1))
            }
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW {
                guard let path = Self.columnText(statement, at: 0),
                      let count = Int(exactly: sqlite3_column_int64(statement, 1))
                else { throw StoreError.invalidData }
                counts[path] = count
                result = sqlite3_step(statement)
            }
            guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        }
        return counts
    }

    /// Reads from the caller's current transaction. The save path uses this after acquiring
    /// its writer lock so content identity and the following write share one SQLite snapshot.
    func readSnapshotInCurrentTransaction() -> CostUsageStoreSnapshot {
        self.withDatabase(default: Self.emptySnapshot) { database in
            try Self.readSnapshot(database, storeURL: self.databaseURL)
        }
    }

    /// Rebuilds the compact Codex baseline from the caller's current transaction. The
    /// unchanged-save path uses this only when retention or budget enforcement made local
    /// writes before metadata certification, so those writes cannot be hidden by a newer stamp.
    func readCodexScanSnapshotInCurrentTransaction(
        loadTokenSnapshots: Bool,
        loadedTokenSnapshotPaths: Set<String>) -> (
        snapshot: CostUsageStoreSnapshot,
        stamp: CodexScanStamp,
        usageRowsByPath: [String: [CostUsageScanner.CodexUsageRow]],
        usageRowCountsByPath: [String: Int])?
    {
        self.withDatabase(default: nil) { database in
            guard sqlite3_get_autocommit(database) == 0,
                  let before = self.currentCodexScanStamp()
            else { return nil }
            #if DEBUG
            CostUsageStoreTestHooks.current.snapshotRead?(self.databaseURL)
            #endif
            var snapshot = try Self.readSnapshot(
                database,
                loadTokenSnapshots: loadTokenSnapshots,
                loadUsageRows: false,
                storeURL: self.databaseURL)
            if !loadTokenSnapshots {
                let markers = Self.codexTokenSnapshotMarkersByPath(from: snapshot.files)
                let accumulators = Dictionary(uniqueKeysWithValues: snapshot.accumulators.map { ($0.path, $0) })
                var counts: [String: Int] = [:]
                var fallbackPaths: Set<String> = []
                for file in snapshot.files {
                    guard file.scanState.replacementScanPending != true,
                          markers[file.path] == true,
                          let accumulator = accumulators[file.path],
                          accumulator.eventCount > 0
                    else {
                        fallbackPaths.insert(file.path)
                        continue
                    }
                    counts[file.path] = accumulator.eventCount
                }
                if !fallbackPaths.isEmpty {
                    try counts.merge(
                        Self.readTokenSnapshotCounts(database, paths: fallbackPaths),
                        uniquingKeysWith: { _, exact in exact })
                }
                if !loadedTokenSnapshotPaths.isEmpty {
                    let loadedSnapshots = try Self.readTokenSnapshots(
                        database,
                        paths: loadedTokenSnapshotPaths,
                        storeURL: self.databaseURL)
                    snapshot.tokenSnapshots = loadedSnapshots
                    let loadedCounts = Dictionary(grouping: loadedSnapshots, by: \.path).mapValues(\.count)
                    for path in loadedTokenSnapshotPaths {
                        counts[path] = loadedCounts[path] ?? 0
                    }
                }
                snapshot.tokenSnapshotCounts = counts
            }
            snapshot.tokenSnapshotsLoaded = loadTokenSnapshots
            let usageRows = try Self.readDecodedUsageRows(database)
            guard let after = self.currentCodexScanStamp(), before == after else { return nil }
            return (
                snapshot: snapshot,
                stamp: after,
                usageRowsByPath: usageRows.rowsByPath,
                usageRowCountsByPath: usageRows.rowCountsByPath)
        }
    }

    /// Reads the compact Codex manifest and aggregate tables without materializing the event
    /// ledger. Event rows are loaded only for `hydratingPaths`, which is the working set selected
    /// by a bounded scanner pass. This intentionally does not call `readSnapshot()` so callers
    /// can prove that routine catch-up never performs a cache-wide event read.
    func readCodexWorkingSetSnapshot(
        hydratingPaths: Set<String>?,
        loadTemporal: Bool = false,
        temporalRange: (sinceDay: String, untilDay: String)? = nil) -> CostUsageStoreSnapshot
    {
        self.withDatabase(default: Self.emptySnapshot) { database in
            try Self.inReadTransaction(database) {
                let files = try Self.readFiles(database, includeBufferedPresence: true)
                let paths = hydratingPaths.map { Set($0) }
                let hydratedPaths = paths ?? Set(files.map(\.path))
                let metadata = try Self.readSingleton(
                    CostUsageStoreMetadata.self,
                    database: database,
                    table: "scan_metadata") ?? .empty
                let temporalSince = temporalRange?.sinceDay ?? metadata.scanSinceDay
                let temporalUntil = temporalRange?.untilDay ?? metadata.scanUntilDay
                let fileTemporal: [CostUsageStoreTemporalAggregate]
                let verifiedTemporal: [CostUsageStoreTemporalAggregate]
                if loadTemporal, let temporalSince, let temporalUntil, temporalSince <= temporalUntil {
                    fileTemporal = try Self.readTemporalAggregates(
                        database,
                        verified: false,
                        sinceDay: temporalSince,
                        untilDay: temporalUntil)
                    verifiedTemporal = try Self.readTemporalAggregates(
                        database,
                        verified: true,
                        sinceDay: temporalSince,
                        untilDay: temporalUntil)
                } else {
                    fileTemporal = []
                    verifiedTemporal = []
                }
                return try CostUsageStoreSnapshot(
                    metadata: metadata,
                    files: files,
                    tokenSnapshots: Self.readTokenSnapshots(
                        database,
                        paths: hydratedPaths,
                        storeURL: self.databaseURL),
                    usageRows: Self.readUsageRows(
                        database,
                        paths: hydratedPaths),
                    fileDayAggregates: Self.readFileDayAggregates(database, path: nil),
                    dayAggregates: Self.readDayAggregates(
                        database,
                        sinceDay: nil,
                        untilDay: nil),
                    verifiedDayAggregates: Self.readVerifiedDayAggregates(database),
                    verifiedDayKeys: Self.readVerifiedDayStatus(
                        database,
                        sinceDay: temporalSince,
                        untilDay: temporalUntil),
                    verifiedDayEvidence: Self.readVerifiedDayEvidence(
                        database,
                        sinceDay: temporalSince,
                        untilDay: temporalUntil),
                    fileTemporalAggregates: fileTemporal,
                    verifiedTemporalAggregates: verifiedTemporal,
                    fileTemporalCoverageIsComplete: loadTemporal
                        ? Self.temporalFileCoverageIsComplete(database) : true,
                    verifiedTemporalCoverageIsComplete: loadTemporal
                        ? Self.verifiedTemporalCoverageIsComplete(database) : false,
                    forkLineage: Self.readForkLineage(database, path: nil),
                    bufferedLines: Self.readBufferedLines(
                        database,
                        paths: hydratedPaths,
                        kind: nil),
                    discoveryState: Self.readSingleton(
                        CostUsageStoreDiscoveryState.self,
                        database: database,
                        table: "discovery_state"),
                    lookbackState: Self.readSingleton(
                        CostUsageStoreLookbackState.self,
                        database: database,
                        table: "lookback_state"),
                    accumulators: Self.readAccumulators(
                        database,
                        paths: hydratedPaths))
            }
        }
    }

    func configuration() -> CostUsageStoreConfiguration? {
        self.withDatabase(default: nil) { database in
            try CostUsageStoreConfiguration(
                journalMode: Self.scalarText(database, "PRAGMA journal_mode") ?? "",
                busyTimeoutMilliseconds: Int(Self.scalarInt(database, "PRAGMA busy_timeout")),
                foreignKeysEnabled: Self.scalarInt(database, "PRAGMA foreign_keys") == 1,
                autoVacuumMode: Int(Self.scalarInt(database, "PRAGMA auto_vacuum")),
                userVersion: Int(Self.scalarInt(database, "PRAGMA user_version")))
        }
    }

    /// SQLite connection counters used by persistence regression tests. These count logical
    /// row changes and cache pages flushed by this connection; they supplement, but are not a
    /// substitute for, filesystem-level write evidence.
    func persistenceWriteMetricsForTesting(resetPageCounter: Bool = false) -> (rows: Int, pages: Int) {
        self.withDatabase(default: (rows: 0, pages: 0)) { database in
            var current: Int32 = 0
            var highwater: Int32 = 0
            let result = sqlite3_db_status(
                database,
                SQLITE_DBSTATUS_CACHE_WRITE,
                &current,
                &highwater,
                resetPageCounter ? 1 : 0)
            guard result == SQLITE_OK else { throw StoreError.sqlite(result) }
            return (rows: Int(sqlite3_total_changes(database)), pages: Int(current))
        }
    }

    func setWALAutoCheckpointForTesting(_ pages: Int32) -> Bool {
        self.withDatabase(default: false) { database in
            let result = sqlite3_wal_autocheckpoint(database, pages)
            guard result == SQLITE_OK else { throw StoreError.sqlite(result) }
            return true
        }
    }

    func truncateWALForTesting() -> Bool {
        self.withDatabase(default: false) { database in
            var logFrames: Int32 = 0
            var checkpointedFrames: Int32 = 0
            let result = sqlite3_wal_checkpoint_v2(
                database,
                nil,
                SQLITE_CHECKPOINT_TRUNCATE,
                &logFrames,
                &checkpointedFrames)
            guard result == SQLITE_OK else { throw StoreError.sqlite(result) }
            return true
        }
    }

    private func readSingleton<Value: Decodable>(_ type: Value.Type, table: String) -> Value? {
        self.withDatabase(default: nil) { database in
            try Self.readSingleton(type, database: database, table: table)
        }
    }
}

// MARK: - Read implementations

extension CostUsageStore {
    private struct CatchUpMetadata {
        var timeZoneIdentifier: String?
        var rootMtimes: [String: Int64]?
        var catchUpPending: Bool
        var processedBytes: Int64?
        var totalBytes: Int64?
        var completedFiles: Int?
        var totalFiles: Int?
        var scanInventoryPaths: [String]?
        var previousReportUpdatedAtUnixMs: Int64?

        static let empty = Self(
            timeZoneIdentifier: nil,
            rootMtimes: nil,
            catchUpPending: false,
            processedBytes: nil,
            totalBytes: nil,
            completedFiles: nil,
            totalFiles: nil,
            scanInventoryPaths: nil,
            previousReportUpdatedAtUnixMs: nil)
    }

    private struct CatchUpScanState: Decodable {
        var resumePayload: Data?
    }

    private struct CatchUpResumeState: Decodable {
        var offset: Int64
    }

    private struct PreviousReportTimestamp: Decodable {
        var updatedAtUnixMs: Int64
    }

    private static var emptySnapshot: CostUsageStoreSnapshot {
        CostUsageStoreSnapshot(
            metadata: .empty,
            files: [],
            tokenSnapshots: [],
            usageRows: [],
            fileDayAggregates: [],
            dayAggregates: [],
            forkLineage: [],
            bufferedLines: [],
            discoveryState: nil,
            lookbackState: nil,
            accumulators: [])
    }

    private static func readSnapshot(
        _ database: OpaquePointer,
        loadTokenSnapshots: Bool = true,
        loadUsageRows: Bool = true,
        storeURL: URL) throws -> CostUsageStoreSnapshot
    {
        try CostUsageStoreSnapshot(
            metadata: self.readSingleton(
                CostUsageStoreMetadata.self,
                database: database,
                table: "scan_metadata") ?? .empty,
            files: self.readFiles(database),
            tokenSnapshots: loadTokenSnapshots
                ? self.readTokenSnapshots(database, path: nil, storeURL: storeURL) : [],
            usageRows: loadUsageRows ? self.readUsageRows(database, path: nil) : [],
            fileDayAggregates: self.readFileDayAggregates(database, path: nil),
            dayAggregates: self.readDayAggregates(database, sinceDay: nil, untilDay: nil),
            forkLineage: self.readForkLineage(database, path: nil),
            bufferedLines: self.readBufferedLines(database, path: nil, kind: nil),
            discoveryState: self.readSingleton(
                CostUsageStoreDiscoveryState.self,
                database: database,
                table: "discovery_state"),
            lookbackState: self.readSingleton(
                CostUsageStoreLookbackState.self,
                database: database,
                table: "lookback_state"),
            accumulators: self.readAccumulators(database, path: nil))
    }

    private static let fileSelectSQL = """
    SELECT path, inode, mtime_ms, size, parsed_bytes, anchor_indexed_bytes,
           anchor_window_start, anchor_sha256, scan_state, scan_target_size,
           scan_complete, session_id, coverage_since_day, coverage_until_day, updated_at_ms,
           EXISTS (SELECT 1 FROM buffered_lines b WHERE b.file_id = files.id AND b.kind = 'subagent'),
           EXISTS (SELECT 1 FROM buffered_lines b WHERE b.file_id = files.id AND b.kind = 'unresolvedFork')
    FROM files
    """

    /// These expressions expect files aliased as f and committed fork_lineage as l.
    /// Object presence distinguishes a staged nil dependency from a legacy state without an overlay.
    static let effectiveCodexForkedFromIDSQL = """
    CASE WHEN json_extract(f.scan_state, '$.replacementScanPending') = 1
              AND json_type(f.scan_state, '$.replacementForkLineage') = 'object'
         THEN json_extract(f.scan_state, '$.replacementForkLineage.forkedFromID')
         ELSE l.forked_from_id END
    """

    static let effectiveCodexForkDependencySQL = """
    CASE WHEN json_extract(f.scan_state, '$.replacementScanPending') = 1
              AND json_type(f.scan_state, '$.replacementForkLineage') = 'object'
         THEN json_extract(f.scan_state, '$.replacementForkLineage.dependencyKey')
         ELSE l.dependency_key END
    """

    private static func readCodexCatchUpFiles(
        _ database: OpaquePointer) throws -> [CostUsageStoreCatchUpFile]
    {
        let statement = try self.prepare(database, """
        SELECT f.path, f.inode, f.mtime_ms, f.size,
               json_extract(f.scan_state, '$.fileIdentity'),
               f.parsed_bytes, f.scan_target_size,
               CASE WHEN f.scan_complete = 0 THEN f.scan_state ELSE NULL END,
               f.scan_complete,
               CASE WHEN json_extract(f.scan_state, '$.replacementScanPending') = 1 THEN 1 ELSE 0 END,
               \(Self.effectiveCodexForkedFromIDSQL), \(Self.effectiveCodexForkDependencySQL),
               EXISTS (
                   SELECT 1 FROM buffered_lines b
                   WHERE b.file_id = f.id AND b.kind = 'subagent'
               ),
               EXISTS (
                   SELECT 1 FROM buffered_lines b
                   WHERE b.file_id = f.id AND b.kind = 'unresolvedFork'
               )
        FROM files f
        LEFT JOIN fork_lineage l ON l.file_id = f.id
        ORDER BY f.path
        """)
        defer { sqlite3_finalize(statement) }
        var values: [CostUsageStoreCatchUpFile] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let path = self.columnText(statement, at: 0) else {
                throw StoreError.invalidData
            }
            let resumeOffset = self.columnData(statement, at: 7).flatMap { data in
                try? JSONDecoder().decode(CatchUpScanState.self, from: data)
            }?.resumePayload.flatMap { data in
                try? JSONDecoder().decode(CatchUpResumeState.self, from: data).offset
            }
            values.append(CostUsageStoreCatchUpFile(
                path: path,
                inode: self.columnInt64(statement, at: 1),
                mtimeUnixMs: sqlite3_column_int64(statement, 2),
                size: sqlite3_column_int64(statement, 3),
                fileIdentity: self.columnText(statement, at: 4),
                parsedBytes: self.columnInt64(statement, at: 5),
                scanTargetSize: self.columnInt64(statement, at: 6),
                resumeOffset: resumeOffset,
                scanComplete: sqlite3_column_int(statement, 8) == 1,
                replacementScanPending: sqlite3_column_int(statement, 9) == 1,
                forkedFromID: self.columnText(statement, at: 10),
                forkBaselineDependencyKey: self.columnText(statement, at: 11),
                hasBufferedSubagentLines: sqlite3_column_int(statement, 12) == 1,
                hasBufferedUnresolvedForkLines: sqlite3_column_int(statement, 13) == 1))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return values
    }

    static func readCodexFileIdentities(
        _ database: OpaquePointer) throws -> [(path: String, identity: String)]
    {
        let statement = try self.prepare(database, """
        SELECT path, json_extract(scan_state, '$.fileIdentity')
        FROM files
        WHERE json_extract(scan_state, '$.fileIdentity') IS NOT NULL
        ORDER BY path
        """)
        defer { sqlite3_finalize(statement) }
        var values: [(path: String, identity: String)] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let path = self.columnText(statement, at: 0),
                  let identity = self.columnText(statement, at: 1)
            else { throw StoreError.invalidData }
            values.append((path: path, identity: identity))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return values
    }

    private static func readCodexCatchUpMetadata(
        _ database: OpaquePointer) throws -> CatchUpMetadata
    {
        let statement = try self.prepare(database, """
        SELECT json_extract(payload, '$.timeZoneIdentifier'),
               json_extract(payload, '$.rootMtimes'),
               COALESCE(json_extract(payload, '$.catchUpPending'), 0),
               json_extract(payload, '$.processedBytes'),
               json_extract(payload, '$.totalBytes'),
               json_extract(payload, '$.completedFiles'),
               json_extract(payload, '$.totalFiles'),
               json_extract(payload, '$.scanInventoryPaths'),
               json_extract(payload, '$.previousReportPayload')
        FROM scan_metadata
        WHERE id = 1
        """)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE {
            return .empty
        }
        guard result == SQLITE_ROW else { throw StoreError.sqlite(result) }

        let rootMtimes = self.columnText(statement, at: 1).flatMap { json in
            try? JSONDecoder().decode([String: Int64].self, from: Data(json.utf8))
        }
        let scanInventoryPaths = self.columnText(statement, at: 7).flatMap { json in
            try? JSONDecoder().decode([String].self, from: Data(json.utf8))
        }
        let previousReportUpdatedAtUnixMs = self.columnText(statement, at: 8)
            .flatMap { Data(base64Encoded: $0) }
            .flatMap { try? JSONDecoder().decode(PreviousReportTimestamp.self, from: $0).updatedAtUnixMs }
        return CatchUpMetadata(
            timeZoneIdentifier: self.columnText(statement, at: 0),
            rootMtimes: rootMtimes,
            catchUpPending: sqlite3_column_int(statement, 2) == 1,
            processedBytes: self.columnInt64(statement, at: 3),
            totalBytes: self.columnInt64(statement, at: 4),
            completedFiles: self.columnInt64(statement, at: 5).flatMap(Int.init(exactly:)),
            totalFiles: self.columnInt64(statement, at: 6).flatMap(Int.init(exactly:)),
            scanInventoryPaths: scanInventoryPaths,
            previousReportUpdatedAtUnixMs: previousReportUpdatedAtUnixMs)
    }

    static func readFiles(
        _ database: OpaquePointer,
        includeBufferedPresence: Bool = false) throws -> [CostUsageStoreFile]
    {
        let statement = try self.prepare(database, self.fileSelectSQL + " ORDER BY path")
        defer { sqlite3_finalize(statement) }
        var values: [CostUsageStoreFile] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            try values.append(self.decodeFile(statement, includeBufferedPresence: includeBufferedPresence))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return values
    }

    static func decodeFile(
        _ statement: OpaquePointer,
        includeBufferedPresence: Bool = false) throws -> CostUsageStoreFile
    {
        guard let path = self.columnText(statement, at: 0),
              let stateData = self.columnData(statement, at: 8)
        else { throw StoreError.invalidData }
        var state = try JSONDecoder().decode(CostUsageStoreScanState.self, from: stateData)
        state.targetSize = self.columnInt64(statement, at: 9)
        state.isComplete = sqlite3_column_int(statement, 10) == 1
        let anchor: CostUsageStoreValidationAnchor? = if let sha = self.columnText(statement, at: 7),
                                                         let indexedBytes = self.columnInt64(statement, at: 5),
                                                         let windowStart = self.columnInt64(statement, at: 6)
        {
            .init(indexedBytes: indexedBytes, windowStart: windowStart, sha256: sha)
        } else {
            nil
        }
        return CostUsageStoreFile(
            path: path,
            inode: self.columnInt64(statement, at: 1),
            mtimeUnixMs: sqlite3_column_int64(statement, 2),
            size: sqlite3_column_int64(statement, 3),
            parsedBytes: self.columnInt64(statement, at: 4),
            anchor: anchor,
            scanState: state,
            sessionID: self.columnText(statement, at: 11),
            coverageSinceDay: self.columnText(statement, at: 12),
            coverageUntilDay: self.columnText(statement, at: 13),
            updatedAtUnixMs: sqlite3_column_int64(statement, 14),
            hasBufferedSubagentLines:
            includeBufferedPresence && sqlite3_column_int(statement, 15) == 1 ? true : nil,
            hasBufferedUnresolvedForkLines:
            includeBufferedPresence && sqlite3_column_int(statement, 16) == 1 ? true : nil)
    }

    static func readTokenSnapshots(
        _ database: OpaquePointer,
        path: String?,
        storeURL: URL) throws -> [CostUsageStoreTokenSnapshot]
    {
        #if DEBUG
        CostUsageStoreTestHooks.current.tokenSnapshotsRead?(storeURL)
        CostUsageStoreTestHooks.current.tokenSnapshotPathRead?(storeURL, path)
        #endif
        var sql = """
        SELECT f.path, t.event_index, t.timestamp, t.timestamp_ms, t.day,
               t.last_input, t.last_cached, t.last_output, t.last_reasoning,
               t.total_input, t.total_cached, t.total_output, t.total_reasoning, t.end_offset
        FROM token_snapshots t JOIN files f ON f.id = t.file_id
        """
        if path != nil {
            sql += " WHERE f.path = ?"
        }
        sql += " ORDER BY f.path, t.event_index"
        let statement = try self.prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        if let path {
            self.bind(path, to: statement, at: 1)
        }
        var values: [CostUsageStoreTokenSnapshot] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let path = self.columnText(statement, at: 0),
                  let eventIndex = Int(exactly: sqlite3_column_int64(statement, 1)),
                  let timestamp = self.columnText(statement, at: 2)
            else { throw StoreError.invalidData }
            values.append(CostUsageStoreTokenSnapshot(
                path: path,
                eventIndex: eventIndex,
                timestamp: timestamp,
                timestampUnixMs: self.columnInt64(statement, at: 3),
                day: self.columnText(statement, at: 4),
                last: self.decodeTotals(statement, startingAt: 5),
                total: self.decodeTotals(statement, startingAt: 9),
                endOffset: self.columnInt64(statement, at: 13)))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return values
    }

    private static func readTokenSnapshots(
        _ database: OpaquePointer,
        paths: Set<String>,
        storeURL: URL) throws -> [CostUsageStoreTokenSnapshot]
    {
        guard !paths.isEmpty else { return [] }
        return try paths.sorted().flatMap {
            try self.readTokenSnapshots(database, path: $0, storeURL: storeURL)
        }
    }

    static func readUsageRows(
        _ database: OpaquePointer,
        path: String?) throws -> [CostUsageStoreUsageRow]
    {
        var values: [CostUsageStoreUsageRow] = []
        _ = try self.forEachUsageRow(database, path: path) { values.append($0) }
        return values
    }

    /// Visits each physical event row in stable file and row-index order without retaining the
    /// encoded payload collection. The return value counts every physical row, including rows
    /// whose payload is malformed or cannot be decoded by a higher-level reader.
    @discardableResult
    static func forEachUsageRow(
        _ database: OpaquePointer,
        path: String?,
        _ visit: (CostUsageStoreUsageRow) throws -> Void) throws -> Int
    {
        var sql = """
        SELECT f.path, r.row_index, r.payload
        FROM usage_rows r JOIN files f ON f.id = r.file_id
        """
        if path != nil {
            sql += " WHERE f.path = ?"
        }
        sql += " ORDER BY f.path, r.row_index"
        let statement = try self.prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        if let path {
            self.bind(path, to: statement, at: 1)
        }
        var physicalRowCount = 0
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let path = self.columnText(statement, at: 0),
                  let rowIndex = Int(exactly: sqlite3_column_int64(statement, 1)),
                  let payload = self.columnData(statement, at: 2)
            else { throw StoreError.invalidData }
            physicalRowCount += 1
            try visit(CostUsageStoreUsageRow(path: path, rowIndex: rowIndex, payload: payload))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return physicalRowCount
    }

    static func readDecodedUsageRows(
        _ database: OpaquePointer) throws -> (
        rowsByPath: [String: [CostUsageScanner.CodexUsageRow]],
        rowCountsByPath: [String: Int])
    {
        let decoder = JSONDecoder()
        var rowsByPath: [String: [CostUsageScanner.CodexUsageRow]] = [:]
        var rowCountsByPath: [String: Int] = [:]
        try self.forEachUsageRow(database, path: nil) { row in
            rowCountsByPath[row.path, default: 0] += 1
            let decoded = try? decoder.decode(CostUsageScanner.CodexUsageRow.self, from: row.payload)
            #if DEBUG
            CostUsageStoreTestHooks.current.codexStreamedUsageRow?(
                row.path,
                row.rowIndex,
                row.payload.count,
                decoded != nil)
            #endif
            if let decoded {
                rowsByPath[row.path, default: []].append(decoded)
            }
        }
        return (rowsByPath, rowCountsByPath)
    }

    private static func readUsageRows(
        _ database: OpaquePointer,
        paths: Set<String>) throws -> [CostUsageStoreUsageRow]
    {
        guard !paths.isEmpty else { return [] }
        return try paths.sorted().flatMap {
            try self.readUsageRows(database, path: $0)
        }
    }

    static func readDayAggregates(
        _ database: OpaquePointer,
        sinceDay: String?,
        untilDay: String?) throws -> [CostUsageStoreDayAggregate]
    {
        var sql = """
        SELECT day, model, input_tokens, cached_tokens, output_tokens, reasoning_tokens,
               request_count, unpriced_request_count, authoritative_cost_nanos,
               standard_authoritative_cost_nanos, priority_authoritative_cost_nanos,
               standard_input_tokens, standard_cached_tokens, standard_output_tokens,
               priority_input_tokens, priority_cached_tokens, priority_output_tokens,
               standard_tokens, priority_tokens, standard_resolved_cost_nanos,
               priority_resolved_cost_nanos, standard_unresolved_pricing_count,
               priority_unresolved_pricing_count
        FROM day_aggregates
        """
        if sinceDay != nil, untilDay != nil {
            sql += " WHERE day >= ? AND day <= ?"
        }
        sql += " ORDER BY day, model"
        let statement = try self.prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        if let sinceDay, let untilDay {
            self.bind(sinceDay, to: statement, at: 1)
            self.bind(untilDay, to: statement, at: 2)
        }
        var values: [CostUsageStoreDayAggregate] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let day = self.columnText(statement, at: 0),
                  let model = self.columnText(statement, at: 1)
            else { throw StoreError.invalidData }
            values.append(CostUsageStoreDayAggregate(
                day: day,
                model: model,
                inputTokens: sqlite3_column_int64(statement, 2),
                cachedTokens: sqlite3_column_int64(statement, 3),
                outputTokens: sqlite3_column_int64(statement, 4),
                reasoningTokens: sqlite3_column_int64(statement, 5),
                requestCount: sqlite3_column_int64(statement, 6),
                unpricedRequestCount: sqlite3_column_int64(statement, 7),
                authoritativeCostNanos: sqlite3_column_int64(statement, 8),
                standardAuthoritativeCostNanos: sqlite3_column_int64(statement, 9),
                priorityAuthoritativeCostNanos: sqlite3_column_int64(statement, 10),
                standardInputTokens: sqlite3_column_int64(statement, 11),
                standardCachedTokens: sqlite3_column_int64(statement, 12),
                standardOutputTokens: sqlite3_column_int64(statement, 13),
                priorityInputTokens: sqlite3_column_int64(statement, 14),
                priorityCachedTokens: sqlite3_column_int64(statement, 15),
                priorityOutputTokens: sqlite3_column_int64(statement, 16),
                standardTokens: sqlite3_column_int64(statement, 17),
                priorityTokens: sqlite3_column_int64(statement, 18),
                standardResolvedCostNanos: sqlite3_column_int64(statement, 19),
                priorityResolvedCostNanos: sqlite3_column_int64(statement, 20),
                standardUnresolvedPricingCount: sqlite3_column_int64(statement, 21),
                priorityUnresolvedPricingCount: sqlite3_column_int64(statement, 22)))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return values
    }

    static func readFileDayAggregates(
        _ database: OpaquePointer,
        path: String?) throws -> [CostUsageStoreFileDayAggregate]
    {
        var sql = """
        SELECT f.path, a.day, a.model, a.input_tokens, a.cached_tokens, a.output_tokens,
               a.reasoning_tokens, a.request_count, a.unpriced_request_count, a.authoritative_cost_nanos,
               a.standard_authoritative_cost_nanos, a.priority_authoritative_cost_nanos,
               a.standard_input_tokens, a.standard_cached_tokens, a.standard_output_tokens,
               a.priority_input_tokens, a.priority_cached_tokens, a.priority_output_tokens,
               a.standard_tokens, a.priority_tokens, a.standard_resolved_cost_nanos,
               a.priority_resolved_cost_nanos, a.standard_unresolved_pricing_count,
               a.priority_unresolved_pricing_count
        FROM file_day_aggregates a JOIN files f ON f.id = a.file_id
        """
        if path != nil {
            sql += " WHERE f.path = ?"
        }
        sql += " ORDER BY f.path, a.day, a.model"
        let statement = try self.prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        if let path {
            self.bind(path, to: statement, at: 1)
        }
        var values: [CostUsageStoreFileDayAggregate] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let path = self.columnText(statement, at: 0),
                  let day = self.columnText(statement, at: 1),
                  let model = self.columnText(statement, at: 2)
            else { throw StoreError.invalidData }
            values.append(CostUsageStoreFileDayAggregate(
                path: path,
                aggregate: CostUsageStoreDayAggregate(
                    day: day,
                    model: model,
                    inputTokens: sqlite3_column_int64(statement, 3),
                    cachedTokens: sqlite3_column_int64(statement, 4),
                    outputTokens: sqlite3_column_int64(statement, 5),
                    reasoningTokens: sqlite3_column_int64(statement, 6),
                    requestCount: sqlite3_column_int64(statement, 7),
                    unpricedRequestCount: sqlite3_column_int64(statement, 8),
                    authoritativeCostNanos: sqlite3_column_int64(statement, 9),
                    standardAuthoritativeCostNanos: sqlite3_column_int64(statement, 10),
                    priorityAuthoritativeCostNanos: sqlite3_column_int64(statement, 11),
                    standardInputTokens: sqlite3_column_int64(statement, 12),
                    standardCachedTokens: sqlite3_column_int64(statement, 13),
                    standardOutputTokens: sqlite3_column_int64(statement, 14),
                    priorityInputTokens: sqlite3_column_int64(statement, 15),
                    priorityCachedTokens: sqlite3_column_int64(statement, 16),
                    priorityOutputTokens: sqlite3_column_int64(statement, 17),
                    standardTokens: sqlite3_column_int64(statement, 18),
                    priorityTokens: sqlite3_column_int64(statement, 19),
                    standardResolvedCostNanos: sqlite3_column_int64(statement, 20),
                    priorityResolvedCostNanos: sqlite3_column_int64(statement, 21),
                    standardUnresolvedPricingCount: sqlite3_column_int64(statement, 22),
                    priorityUnresolvedPricingCount: sqlite3_column_int64(statement, 23))))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return values
    }
}

extension CostUsageStore {
    static func readForkLineage(
        _ database: OpaquePointer,
        path: String?) throws -> [CostUsageStoreForkLineage]
    {
        var sql = """
        SELECT f.path, l.session_id, l.forked_from_id, l.fork_timestamp,
               l.dependency_key, l.subagent_state, l.accounting_state
        FROM fork_lineage l JOIN files f ON f.id = l.file_id
        """
        if path != nil {
            sql += " WHERE f.path = ?"
        }
        sql += " ORDER BY f.path"
        let statement = try self.prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        if let path {
            self.bind(path, to: statement, at: 1)
        }
        var values: [CostUsageStoreForkLineage] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let path = self.columnText(statement, at: 0) else { throw StoreError.invalidData }
            values.append(CostUsageStoreForkLineage(
                path: path,
                sessionID: self.columnText(statement, at: 1),
                forkedFromID: self.columnText(statement, at: 2),
                forkTimestamp: self.columnText(statement, at: 3),
                dependencyKey: self.columnText(statement, at: 4),
                subagentState: self.columnData(statement, at: 5),
                accountingState: self.columnData(statement, at: 6)))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return values
    }

    static func readBufferedLines(
        _ database: OpaquePointer,
        path: String?,
        kind: CostUsageStoreBufferedLineKind?) throws -> [CostUsageStoreBufferedLine]
    {
        var sql = """
        SELECT f.path, b.kind, b.line_index, b.ordinal, b.end_offset, b.payload
        FROM buffered_lines b JOIN files f ON f.id = b.file_id
        """
        var clauses: [String] = []
        if path != nil {
            clauses.append("f.path = ?")
        }
        if kind != nil {
            clauses.append("b.kind = ?")
        }
        if !clauses.isEmpty {
            sql += " WHERE " + clauses.joined(separator: " AND ")
        }
        sql += " ORDER BY f.path, b.kind, b.line_index"
        let statement = try self.prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        var index: Int32 = 1
        if let path {
            self.bind(path, to: statement, at: index)
            index += 1
        }
        if let kind {
            self.bind(kind.rawValue, to: statement, at: index)
        }
        var values: [CostUsageStoreBufferedLine] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let path = self.columnText(statement, at: 0),
                  let rawKind = self.columnText(statement, at: 1),
                  let kind = CostUsageStoreBufferedLineKind(rawValue: rawKind),
                  let lineIndex = Int(exactly: sqlite3_column_int64(statement, 2)),
                  let payload = self.columnData(statement, at: 5)
            else { throw StoreError.invalidData }
            values.append(CostUsageStoreBufferedLine(
                path: path,
                kind: kind,
                lineIndex: lineIndex,
                ordinal: self.columnInt64(statement, at: 3).flatMap(Int.init(exactly:)),
                endOffset: self.columnInt64(statement, at: 4),
                payload: payload))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return values
    }

    private static func readBufferedLines(
        _ database: OpaquePointer,
        paths: Set<String>,
        kind: CostUsageStoreBufferedLineKind?) throws -> [CostUsageStoreBufferedLine]
    {
        guard !paths.isEmpty else { return [] }
        return try paths.sorted().flatMap {
            try self.readBufferedLines(database, path: $0, kind: kind)
        }
    }

    static func readAccumulators(
        _ database: OpaquePointer,
        path: String?) throws -> [CostUsageStoreAccumulator]
    {
        var sql = """
        SELECT f.path, a.event_count, a.next_usage_row_index,
               a.counted_input, a.counted_cached, a.counted_output, a.counted_reasoning,
               a.baseline_input, a.baseline_cached, a.baseline_output, a.baseline_reasoning,
               a.watermark_input, a.watermark_cached, a.watermark_output, a.watermark_reasoning,
               a.saw_divergent, a.saw_interleaved, a.seen_raw_totals, a.updated_at_ms
        FROM accumulators a JOIN files f ON f.id = a.file_id
        """
        if path != nil {
            sql += " WHERE f.path = ?"
        }
        sql += " ORDER BY f.path"
        let statement = try self.prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        if let path {
            self.bind(path, to: statement, at: 1)
        }
        var values: [CostUsageStoreAccumulator] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let path = self.columnText(statement, at: 0),
                  let eventCount = Int(exactly: sqlite3_column_int64(statement, 1)),
                  let seenData = self.columnData(statement, at: 17)
            else { throw StoreError.invalidData }
            let seen = try JSONDecoder().decode([CostUsageStoreTotals].self, from: seenData)
            values.append(CostUsageStoreAccumulator(
                path: path,
                eventCount: eventCount,
                nextUsageRowIndex: self.columnInt64(statement, at: 2).flatMap(Int.init(exactly:)),
                countedTotals: self.decodeTotals(statement, startingAt: 3),
                rawTotalsBaseline: self.decodeTotals(statement, startingAt: 7),
                rawTotalsWatermark: self.decodeTotals(statement, startingAt: 11),
                sawDivergentTotals: sqlite3_column_int(statement, 15) == 1,
                sawInterleavedTotals: sqlite3_column_int(statement, 16) == 1,
                seenRawTotals: seen,
                updatedAtUnixMs: sqlite3_column_int64(statement, 18)))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return values
    }

    private static func readAccumulators(
        _ database: OpaquePointer,
        paths: Set<String>) throws -> [CostUsageStoreAccumulator]
    {
        guard !paths.isEmpty else { return [] }
        return try paths.sorted().compactMap {
            try self.readAccumulators(database, path: $0).first
        }
    }
}

// MARK: - Read helpers

extension CostUsageStore {
    static func readSingleton<Value: Decodable>(
        _ type: Value.Type,
        database: OpaquePointer,
        table: String) throws -> Value?
    {
        let statement = try self.prepare(database, "SELECT payload FROM \(table) WHERE id = 1")
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE {
            return nil
        }
        guard result == SQLITE_ROW, let payload = self.columnData(statement, at: 0) else {
            throw StoreError.sqlite(result)
        }
        return try JSONDecoder().decode(type, from: payload)
    }

    static func decodeTotals(_ statement: OpaquePointer, startingAt index: Int32) -> CostUsageStoreTotals? {
        guard let input = self.columnInt64(statement, at: index),
              let cached = self.columnInt64(statement, at: index + 1),
              let output = self.columnInt64(statement, at: index + 2)
        else { return nil }
        return CostUsageStoreTotals(
            input: input,
            cached: cached,
            output: output,
            reasoning: self.columnInt64(statement, at: index + 3))
    }

    static func inReadTransaction<T>(_ database: OpaquePointer, _ operation: () throws -> T) throws -> T {
        try self.execute(database, "BEGIN")
        do {
            let value = try operation()
            try self.execute(database, "COMMIT")
            return value
        } catch {
            try? self.execute(database, "ROLLBACK")
            throw error
        }
    }
}
