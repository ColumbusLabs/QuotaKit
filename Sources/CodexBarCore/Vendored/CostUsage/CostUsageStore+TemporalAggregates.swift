import Foundation

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

struct CostUsageStoreTemporalAggregate: Equatable, Sendable {
    var path: String?
    var kind: Int
    var timestampUnixMs: Int64
    var day: String
    var totalTokens: Int?
    var costUSD: Double?
    var tokensAreComplete: Bool
    var costIsComplete: Bool
}

extension CostUsageStore {
    /// Additive tables: old stores keep their raw ledger and rebuild these rows through the
    /// parser-revision migration's bounded file queue.
    static func ensureTemporalAggregateTables(_ database: OpaquePointer) throws {
        try execute(database, """
        CREATE TABLE IF NOT EXISTS file_temporal_aggregates (
            file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
            kind INTEGER NOT NULL,
            timestamp_ms INTEGER NOT NULL,
            day TEXT NOT NULL,
            total_tokens INTEGER,
            cost_usd REAL,
            tokens_complete INTEGER NOT NULL,
            cost_complete INTEGER NOT NULL,
            PRIMARY KEY(file_id, kind, timestamp_ms)
        )
        """)
        try execute(database, """
        CREATE INDEX IF NOT EXISTS file_temporal_day_idx
        ON file_temporal_aggregates(day, kind, timestamp_ms)
        """)
        try execute(database, """
        CREATE TABLE IF NOT EXISTS file_temporal_status (
            file_id INTEGER PRIMARY KEY REFERENCES files(id) ON DELETE CASCADE
        )
        """)
        try execute(database, """
        CREATE TABLE IF NOT EXISTS verified_temporal_aggregates (
            home TEXT NOT NULL,
            kind INTEGER NOT NULL,
            timestamp_ms INTEGER NOT NULL,
            day TEXT NOT NULL,
            total_tokens INTEGER,
            cost_usd REAL,
            tokens_complete INTEGER NOT NULL,
            cost_complete INTEGER NOT NULL,
            PRIMARY KEY(home, kind, timestamp_ms)
        )
        """)
        try execute(database, """
        CREATE INDEX IF NOT EXISTS verified_temporal_day_idx
        ON verified_temporal_aggregates(home, day, kind, timestamp_ms)
        """)
        try execute(database, """
        CREATE TABLE IF NOT EXISTS verified_day_status (
            home TEXT NOT NULL,
            day TEXT NOT NULL,
            PRIMARY KEY(home, day)
        )
        """)
        try execute(database, """
        CREATE TABLE IF NOT EXISTS verified_day_evidence (
            home TEXT NOT NULL,
            day TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            scope_id TEXT NOT NULL,
            lineage_id TEXT NOT NULL,
            revision INTEGER NOT NULL CHECK(revision > 0),
            verified_at_ms INTEGER NOT NULL,
            PRIMARY KEY(home, day)
        )
        """)
    }

    @discardableResult
    func replaceFileTemporalAggregates(
        path: String,
        aggregates: [CostUsageStoreTemporalAggregate]) -> Bool
    {
        self.withDatabase(default: false) { database in
            try Self.inTransaction(database) {
                let deletion = try Self.prepare(database, """
                DELETE FROM file_temporal_aggregates
                WHERE file_id = (SELECT id FROM files WHERE path = ?1 AND home = ?2)
                """)
                defer { sqlite3_finalize(deletion) }
                Self.bind(path, to: deletion, at: 1)
                Self.bind(self.home, to: deletion, at: 2)
                try Self.stepDone(deletion, database: database)

                let insertion = try Self.prepare(database, """
                INSERT INTO file_temporal_aggregates (
                    file_id, kind, timestamp_ms, day, total_tokens, cost_usd,
                    tokens_complete, cost_complete
                ) VALUES ((SELECT id FROM files WHERE path = ?1 AND home = ?9), ?2, ?3, ?4, ?5, ?6, ?7, ?8)
                """)
                defer { sqlite3_finalize(insertion) }
                for aggregate in aggregates {
                    sqlite3_reset(insertion)
                    sqlite3_clear_bindings(insertion)
                    Self.bind(path, to: insertion, at: 1)
                    Self.bind(self.home, to: insertion, at: 9)
                    sqlite3_bind_int64(insertion, 2, Int64(aggregate.kind))
                    sqlite3_bind_int64(insertion, 3, aggregate.timestampUnixMs)
                    Self.bind(aggregate.day, to: insertion, at: 4)
                    Self.bind(aggregate.totalTokens.map(Int64.init), to: insertion, at: 5)
                    if let cost = aggregate.costUSD {
                        sqlite3_bind_double(insertion, 6, cost)
                    }
                    sqlite3_bind_int(insertion, 7, aggregate.tokensAreComplete ? 1 : 0)
                    sqlite3_bind_int(insertion, 8, aggregate.costIsComplete ? 1 : 0)
                    try Self.stepDone(insertion, database: database)
                }
                let status = try Self.prepare(database, """
                INSERT OR IGNORE INTO file_temporal_status(file_id)
                SELECT id FROM files WHERE path = ?1 AND home = ?2
                """)
                defer { sqlite3_finalize(status) }
                Self.bind(path, to: status, at: 1)
                Self.bind(self.home, to: status, at: 2)
                try Self.stepDone(status, database: database)
                try Self.invalidateVerifiedTemporalCoverage(database, home: self.home)
            }
            return true
        }
    }

    static func readTemporalAggregates(
        _ database: OpaquePointer,
        home: String,
        verified: Bool,
        sinceDay: String,
        untilDay: String) throws -> [CostUsageStoreTemporalAggregate]
    {
        let sql = verified ? """
        SELECT NULL, kind, timestamp_ms, day, total_tokens, cost_usd,
               tokens_complete, cost_complete
        FROM verified_temporal_aggregates
        WHERE home = ?3 AND day >= ?1 AND day <= ?2
        ORDER BY kind, timestamp_ms
        """ : """
        SELECT files.path, temporal.kind, temporal.timestamp_ms, temporal.day,
               temporal.total_tokens, temporal.cost_usd,
               temporal.tokens_complete, temporal.cost_complete
        FROM file_temporal_aggregates AS temporal
        JOIN files ON files.id = temporal.file_id
        WHERE files.home = ?3 AND temporal.day >= ?1 AND temporal.day <= ?2
        ORDER BY temporal.kind, temporal.timestamp_ms
        """
        let statement = try Self.prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        Self.bind(sinceDay, to: statement, at: 1)
        Self.bind(untilDay, to: statement, at: 2)
        Self.bind(home, to: statement, at: 3)
        var aggregates: [CostUsageStoreTemporalAggregate] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let day = Self.columnText(statement, at: 3) else { throw StoreError.invalidData }
            aggregates.append(CostUsageStoreTemporalAggregate(
                path: Self.columnText(statement, at: 0),
                kind: Int(sqlite3_column_int(statement, 1)),
                timestampUnixMs: sqlite3_column_int64(statement, 2),
                day: day,
                totalTokens: sqlite3_column_type(statement, 4) == SQLITE_NULL
                    ? nil : Int(sqlite3_column_int64(statement, 4)),
                costUSD: sqlite3_column_type(statement, 5) == SQLITE_NULL
                    ? nil : sqlite3_column_double(statement, 5),
                tokensAreComplete: sqlite3_column_int(statement, 6) != 0,
                costIsComplete: sqlite3_column_int(statement, 7) != 0))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return aggregates
    }

    static func temporalFileCoverageIsComplete(_ database: OpaquePointer, home: String) throws -> Bool {
        let statement = try Self.prepare(database, """
        SELECT COUNT(*) FROM files
        WHERE home = ? AND EXISTS (SELECT 1 FROM usage_rows WHERE usage_rows.file_id = files.id)
          AND NOT EXISTS (SELECT 1 FROM file_temporal_status WHERE file_temporal_status.file_id = files.id)
        """)
        defer { sqlite3_finalize(statement) }
        Self.bind(home, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw StoreError.invalidData }
        return sqlite3_column_int64(statement, 0) == 0
    }

    static func verifiedMetaKey(_ key: String, home: String) -> String {
        "\(key):home:" + Data(home.utf8).base64EncodedString()
    }

    static func verifiedTemporalCoverageIsComplete(_ database: OpaquePointer, home: String) throws -> Bool {
        try optionalMetaValue(database, key: self.verifiedMetaKey("verified_temporal_version", home: home)) == "1"
    }

    static func markVerifiedTemporalCoverageComplete(_ database: OpaquePointer, home: String) throws {
        let statement = try Self.prepare(database, """
        INSERT INTO meta(key, value) VALUES (?, '1')
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """)
        defer { sqlite3_finalize(statement) }
        Self.bind(Self.verifiedMetaKey("verified_temporal_version", home: home), to: statement, at: 1)
        try Self.stepDone(statement, database: database)
    }

    static func invalidateVerifiedTemporalCoverage(_ database: OpaquePointer, home: String) throws {
        let statement = try Self.prepare(database, "DELETE FROM meta WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        Self.bind(Self.verifiedMetaKey("verified_temporal_version", home: home), to: statement, at: 1)
        try Self.stepDone(statement, database: database)
    }

    static func clearVerifiedTemporalAggregates(
        _ database: OpaquePointer,
        home: String,
        sinceDay: String? = nil,
        untilDay: String? = nil) throws
    {
        if let sinceDay, let untilDay {
            let statement = try Self.prepare(database, """
            DELETE FROM verified_temporal_aggregates WHERE home = ?3 AND day >= ?1 AND day <= ?2
            """)
            defer { sqlite3_finalize(statement) }
            Self.bind(sinceDay, to: statement, at: 1)
            Self.bind(untilDay, to: statement, at: 2)
            Self.bind(home, to: statement, at: 3)
            try Self.stepDone(statement, database: database)
        } else {
            let statement = try Self.prepare(database, "DELETE FROM verified_temporal_aggregates WHERE home = ?")
            defer { sqlite3_finalize(statement) }
            Self.bind(home, to: statement, at: 1)
            try Self.stepDone(statement, database: database)
        }
    }

    static func replaceVerifiedTemporalAggregates(
        _ database: OpaquePointer,
        home: String,
        sinceDay: String,
        untilDay: String) throws
    {
        try self.clearVerifiedTemporalAggregates(database, home: home, sinceDay: sinceDay, untilDay: untilDay)
        let statement = try Self.prepare(database, """
        INSERT INTO verified_temporal_aggregates (
            home, kind, timestamp_ms, day, total_tokens, cost_usd, tokens_complete, cost_complete
        )
        SELECT ?3, temporal.kind, temporal.timestamp_ms, MIN(temporal.day), SUM(temporal.total_tokens),
               SUM(temporal.cost_usd), MIN(temporal.tokens_complete), MIN(temporal.cost_complete)
        FROM file_temporal_aggregates AS temporal
        JOIN files ON files.id = temporal.file_id
        WHERE temporal.day >= ?1 AND temporal.day <= ?2 AND files.home = ?3
        GROUP BY temporal.kind, temporal.timestamp_ms
        """)
        defer { sqlite3_finalize(statement) }
        Self.bind(sinceDay, to: statement, at: 1)
        Self.bind(untilDay, to: statement, at: 2)
        Self.bind(home, to: statement, at: 3)
        try Self.stepDone(statement, database: database)
    }
}
