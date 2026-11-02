import Foundation

enum CodexHomeCostStoreScope {
    static let openCodeSource = "quotakit:opencode-local-history"

    static func key(options: CostUsageScanner.Options = .init()) -> String {
        self.key(sessionsRoot: CostUsageScanner.defaultCodexSessionsRoot(options: options))
    }

    static func key(sessionsRoot: URL) -> String {
        CostUsageScanner.codexPathKey(sessionsRoot.resolvingSymlinksInPath().standardizedFileURL)
    }
}

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

extension CostUsageStore {
    /// Re-key the existing SQLite cache without deleting its files, checkpoints or verified proof.
    /// The caller holds the schema migration transaction.
    func migrateHomeScope(_ database: OpaquePointer) throws {
        let metadataStatement = try Self.prepare(database, "SELECT payload FROM scan_metadata WHERE id = 1")
        defer { sqlite3_finalize(metadataStatement) }
        let metadata: CostUsageStoreMetadata? = if sqlite3_step(metadataStatement) == SQLITE_ROW,
                                                   let payload = Self.columnData(metadataStatement, at: 0)
        {
            try JSONDecoder().decode(CostUsageStoreMetadata.self, from: payload)
        } else {
            nil
        }
        sqlite3_reset(metadataStatement)
        let roots = (metadata?.rootMtimes?.keys.map { URL(fileURLWithPath: $0) } ?? [])
            .sorted { $0.path < $1.path }
        let primary = roots.first(where: { $0.lastPathComponent == "sessions" }) ?? roots.first
        let sessionsRoot = primary.map { root in
            root.lastPathComponent == "archived_sessions"
                ? root.deletingLastPathComponent().appendingPathComponent("sessions", isDirectory: true) : root
        }
        let legacyHome: String
        if let sessionsRoot {
            try Self.validateLegacyFileOwnership(database, roots: roots)
            legacyHome = CodexHomeCostStoreScope.key(sessionsRoot: sessionsRoot)
        } else {
            legacyHome = try Self.legacyHomeFromStoredFiles(database) ?? CodexHomeCostStoreScope.key()
        }
        let sharedHome = CodexHomeCostStoreScope.openCodeSource

        for table in ["scan_metadata", "discovery_state", "lookback_state"] {
            try Self.execute(database, "ALTER TABLE \(table) RENAME TO legacy_\(table)")
            try Self.execute(database, """
            CREATE TABLE \(table) (
                home TEXT NOT NULL, id INTEGER NOT NULL CHECK (id = 1), payload BLOB NOT NULL,
                PRIMARY KEY(home, id))
            """)
            let copy = try Self.prepare(database, "INSERT INTO \(table) SELECT ?, id, payload FROM legacy_\(table)")
            Self.bind(legacyHome, to: copy, at: 1)
            defer { sqlite3_finalize(copy) }
            try Self.stepDone(copy, database: database)
            try Self.execute(database, "DROP TABLE legacy_\(table)")
        }

        // Older stores could combine optional source rows with the native verified baseline.
        // Their proof cannot be assigned to native history without independently proving its inputs.
        let importedCount = try Self.scalarInt(database, """
        SELECT COUNT(*) FROM files
        WHERE json_extract(CAST(scan_state AS TEXT), '$.source') = 'opencodeLocalHistory'
        """)
        var hasVerifiedProof = metadata?.verifiedScanSinceDay != nil
            || metadata?.verifiedScanUntilDay != nil
            || metadata?.verifiedUpdatedAtUnixMs != nil
        for table in [
            "verified_day_aggregates",
            "verified_day_status",
            "verified_day_evidence",
            "verified_temporal_aggregates",
        ] {
            let exists = try Self.scalarInt(database, """
            SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '\(table)'
            """) > 0
            if exists, try Self.scalarInt(database, "SELECT COUNT(*) FROM \(table)") > 0 {
                hasVerifiedProof = true
            }
        }
        if try Self.optionalMetaValue(database, key: "verified_temporal_version") != nil {
            hasVerifiedProof = true
        }
        let invalidateMixedProof = importedCount > 0 && hasVerifiedProof
        if invalidateMixedProof {
            // A native file that is unavailable cannot establish fresh evidence. Preserve the
            // old store instead of discarding the only proof for a compressed-only rollout.
            let nativeFiles = try Self.readFiles(database).filter { !$0.belongsToOpenCodeLocalHistory }
            for file in nativeFiles {
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                      attributes[.type] as? FileAttributeType == .typeRegular,
                      let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: file.path))
                else { throw StoreError.invalidData }
                try handle.close()
            }
            // Preserve the prior proof if a source disappears while native evidence is rebuilt.
            try Self.saveRecoverySnapshot(of: self.databaseURL)
        }

        try Self.execute(database, "ALTER TABLE files ADD COLUMN home TEXT NOT NULL DEFAULT ''")
        let files = try Self.prepare(database, """
        UPDATE files SET home = CASE
            WHEN json_extract(CAST(scan_state AS TEXT), '$.source') = 'opencodeLocalHistory' THEN ?
            ELSE ? END
        """)
        defer { sqlite3_finalize(files) }
        Self.bind(sharedHome, to: files, at: 1)
        Self.bind(legacyHome, to: files, at: 2)
        try Self.stepDone(files, database: database)
        try Self.execute(database, "CREATE INDEX files_home_path_idx ON files(home, path)")

        for table in [
            "day_aggregates",
            "verified_day_aggregates",
            "verified_temporal_aggregates",
            "verified_day_status",
            "verified_day_evidence",
        ] {
            try Self.migrateLegacyHomeTable(database, table: table, home: legacyHome)
        }
        if importedCount > 0 {
            try Self.redistributeLegacyAggregates(database)
        }
        for key in [
            "verified_ledger_version",
            "verified_day_lineage_id",
            "verified_day_revision",
            "verified_temporal_version",
        ] {
            if let value = try Self.optionalMetaValue(database, key: key) {
                try Self.writeMetaValue(value, key: Self.verifiedMetaKey(key, home: legacyHome), database: database)
            }
        }
        if invalidateMixedProof {
            try Self.ensureTemporalAggregateTables(database)
            try Self.clearVerifiedDayAggregates(database, home: legacyHome)
            try Self.deleteHomeRows(database, table: "verified_day_status", home: legacyHome)
            try Self.deleteHomeRows(database, table: "verified_day_evidence", home: legacyHome)
            try Self.deleteHomeRows(database, table: "verified_temporal_aggregates", home: legacyHome)
            try Self.invalidateVerifiedTemporalCoverage(database, home: legacyHome)
            if var nativeMetadata = try Self.readSingleton(
                CostUsageStoreMetadata.self, database: database, table: "scan_metadata", home: legacyHome)
            {
                Self.clearVerifiedCoverage(&nativeMetadata)
                nativeMetadata.previousReportPayload = nil
                nativeMetadata.catchUpPending = true
                try Self.writeSingleton(nativeMetadata, database: database, table: "scan_metadata", home: legacyHome)
            }
        }
    }

    /// Root metadata can describe the most recent scan while stale rows from another
    /// home still exist. Reject that migration rather than attributing them to this home.
    private static func validateLegacyFileOwnership(_ database: OpaquePointer, roots: [URL]) throws {
        let allowed = roots.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        let statement = try self.prepare(database, """
        SELECT path FROM files
        WHERE COALESCE(json_extract(CAST(scan_state AS TEXT), '$.source'), 'nativeCodexSessionLogs')
            != 'opencodeLocalHistory'
        """)
        defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let path = self.columnText(statement, at: 0) else { throw StoreError.invalidData }
            let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            guard allowed.contains(where: { canonical.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") })
            else { throw StoreError.invalidData }
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
    }

    private static func legacyHomeFromStoredFiles(_ database: OpaquePointer) throws -> String? {
        let statement = try self.prepare(database, """
        SELECT path FROM files
        WHERE COALESCE(json_extract(CAST(scan_state AS TEXT), '$.source'), 'nativeCodexSessionLogs')
            != 'opencodeLocalHistory'
        """)
        defer { sqlite3_finalize(statement) }
        var owner: String?
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let path = self.columnText(statement, at: 0) else { throw StoreError.invalidData }
            var root = URL(fileURLWithPath: path).deletingLastPathComponent()
            while root.path != "/" && !["sessions", "archived_sessions"].contains(root.lastPathComponent) {
                root.deleteLastPathComponent()
            }
            guard root.path != "/" else { throw StoreError.invalidData }
            if root.lastPathComponent == "archived_sessions" {
                root = root.deletingLastPathComponent().appendingPathComponent("sessions", isDirectory: true)
            }
            let key = CodexHomeCostStoreScope.key(sessionsRoot: root)
            guard owner == nil || owner == key else { throw StoreError.invalidData }
            owner = key
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return owner
    }

    /// Redistribute the former single aggregate only when the old totals can be proven
    /// exactly equal to the sum of the retained per-file rows. Otherwise roll back intact.
    private static func redistributeLegacyAggregates(_ database: OpaquePointer) throws {
        let schema = try self.prepare(database, "PRAGMA table_info(file_day_aggregates)")
        defer { sqlite3_finalize(schema) }
        var fields: [String] = []
        var result = sqlite3_step(schema)
        while result == SQLITE_ROW {
            if let name = self.columnText(schema, at: 1), !["file_id", "day", "model"].contains(name) {
                guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
                    throw StoreError.invalidData
                }
                fields.append(name)
            }
            result = sqlite3_step(schema)
        }
        guard result == SQLITE_DONE, !fields.isEmpty else { throw StoreError.invalidData }
        let names = fields.joined(separator: ", ")
        let sums = fields.map { "SUM(a.\($0))" }.joined(separator: ", ")
        let rebuilt = "SELECT a.day, a.model, \(sums) FROM file_day_aggregates a GROUP BY a.day, a.model"
        let previous = "SELECT day, model, \(names) FROM day_aggregates"
        guard try self.scalarInt(database, "SELECT COUNT(*) FROM (\(previous) EXCEPT \(rebuilt))") == 0,
              try self.scalarInt(database, "SELECT COUNT(*) FROM (\(rebuilt) EXCEPT \(previous))") == 0
        else { throw StoreError.invalidData }
        try self.execute(database, "DELETE FROM day_aggregates")
        try self.execute(database, """
        INSERT INTO day_aggregates(home, day, model, \(names))
        SELECT f.home, a.day, a.model, \(sums)
        FROM file_day_aggregates a JOIN files f ON f.id = a.file_id
        GROUP BY f.home, a.day, a.model
        """)
    }

    private static func migrateLegacyHomeTable(_ database: OpaquePointer, table: String, home: String) throws {
        let query = try self.prepare(database, "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?")
        defer { sqlite3_finalize(query) }
        self.bind(table, to: query, at: 1)
        guard sqlite3_step(query) == SQLITE_ROW, let sql = self.columnText(query, at: 0) else { return }
        sqlite3_reset(query)
        let indexQuery = try self.prepare(
            database, "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = ? AND sql IS NOT NULL")
        defer { sqlite3_finalize(indexQuery) }
        self.bind(table, to: indexQuery, at: 1)
        var indexes: [String] = []
        var step = sqlite3_step(indexQuery)
        while step == SQLITE_ROW {
            if let index = self.columnText(indexQuery, at: 0) { indexes.append(index) }
            step = sqlite3_step(indexQuery)
        }
        guard step == SQLITE_DONE, let open = sql.firstIndex(of: "("), let close = sql.lastIndex(of: ")")
        else { throw StoreError.invalidData }
        var columns = String(sql[sql.index(after: open)..<close])
        if columns.contains("day TEXT PRIMARY KEY") {
            columns = columns.replacingOccurrences(of: "day TEXT PRIMARY KEY", with: "day TEXT NOT NULL")
            columns += ", PRIMARY KEY(home, day)"
        } else {
            guard columns.contains("PRIMARY KEY(") else { throw StoreError.invalidData }
            columns = columns.replacingOccurrences(of: "PRIMARY KEY(", with: "PRIMARY KEY(home, ")
        }
        try self.execute(database, "ALTER TABLE \(table) RENAME TO legacy_\(table)")
        try self.execute(database, "CREATE TABLE \(table) (home TEXT NOT NULL, \(columns))")
        let copy = try self.prepare(database, "INSERT INTO \(table) SELECT ?, * FROM legacy_\(table)")
        defer { sqlite3_finalize(copy) }
        self.bind(home, to: copy, at: 1)
        try self.stepDone(copy, database: database)
        try self.execute(database, "DROP TABLE legacy_\(table)")
        for index in indexes {
            try self.execute(database, index)
        }
    }
}
