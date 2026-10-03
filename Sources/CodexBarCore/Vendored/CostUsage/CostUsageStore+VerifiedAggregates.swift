import Foundation

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

/// Persistence and compatibility helpers for the last complete Codex aggregate view.
///
/// `day_aggregates` is intentionally allowed to move while a bounded scan replaces files. The
/// verified table is the publication baseline: complete scans replace it atomically, while a
/// pending pass may update only independently verified day rows. Coverage markers distinguish
/// the complete baseline from that sparse evidence, so a pending 365-day pass cannot invalidate
/// an established 30-day (or vice versa) consumer projection.
extension CostUsageStore {
    private static let verifiedLedgerMarkerKey = "verified_ledger_version"
    static let verifiedDayLineageKey = "verified_day_lineage_id"
    private static let verifiedDayRevisionKey = "verified_day_revision"
    private static let verifiedDayEvidenceRefreshIntervalMs: Int64 = 5 * 60 * 1000

    static func verifiedLedgerMigrationNeeded(_ database: OpaquePointer) throws -> Bool {
        let hasTable = try Self.scalarInt(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_aggregates'") > 0
        guard hasTable else { return true }
        guard try Self.readSingleton(
            CostUsageStoreMetadata.self,
            database: database,
            table: "scan_metadata") != nil
        else {
            // A newly-created store has no scan metadata yet and therefore needs no migration.
            return false
        }
        let marker = try Self.scalarText(
            database,
            "SELECT COALESCE((SELECT value FROM meta WHERE key = '\(Self.verifiedLedgerMarkerKey)'), '')")
        guard let marker, !marker.isEmpty else {
            // Older stores have the table but no marker. They need one additive migration;
            // newly-created stores have no metadata and took the fast path above.
            return true
        }
        return marker != String(Self.verifiedLedgerVersion)
    }

    static func clearVerifiedDayAggregates(_ database: OpaquePointer) throws {
        guard try scalarInt(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_aggregates'") > 0
        else { return }
        try execute(database, "DELETE FROM verified_day_aggregates")
        try clearVerifiedTemporalAggregates(database)
        try execute(database, "DELETE FROM verified_day_status")
        if try scalarInt(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_evidence'") > 0
        {
            try execute(database, "DELETE FROM verified_day_evidence")
        }
        try invalidateVerifiedTemporalCoverage(database)
    }

    static func readVerifiedDayStatus(
        _ database: OpaquePointer,
        sinceDay: String? = nil,
        untilDay: String? = nil) throws -> [String]
    {
        var sql = "SELECT day FROM verified_day_status"
        if sinceDay != nil, untilDay != nil {
            sql += " WHERE day >= ? AND day <= ?"
        }
        sql += " ORDER BY day"
        let statement = try Self.prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        if let sinceDay, let untilDay {
            Self.bind(sinceDay, to: statement, at: 1)
            Self.bind(untilDay, to: statement, at: 2)
        }
        var days: [String] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let day = Self.columnText(statement, at: 0) else { throw StoreError.invalidData }
            days.append(day)
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return days
    }

    static func markVerifiedDayStatus(_ database: OpaquePointer, day: String) throws {
        let statement = try Self.prepare(database, "INSERT OR IGNORE INTO verified_day_status(day) VALUES (?)")
        defer { sqlite3_finalize(statement) }
        Self.bind(day, to: statement, at: 1)
        try Self.stepDone(statement, database: database)
    }

    /// Reads only positive-revision proof rows. Legacy status membership deliberately does not
    /// become evidence during the additive table migration.
    static func readVerifiedDayEvidence(
        _ database: OpaquePointer,
        sinceDay: String? = nil,
        untilDay: String? = nil) throws -> [String: CostUsageDayEvidence]
    {
        guard try scalarInt(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_evidence'") > 0
        else { return [:] }

        var sql = """
        SELECT day, source_kind, scope_id, lineage_id, revision, verified_at_ms
        FROM verified_day_evidence
        WHERE revision > 0
        """
        if sinceDay != nil, untilDay != nil {
            sql += " AND day >= ? AND day <= ?"
        }
        sql += " ORDER BY day"
        let statement = try Self.prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        if let sinceDay, let untilDay {
            Self.bind(sinceDay, to: statement, at: 1)
            Self.bind(untilDay, to: statement, at: 2)
        }
        var values: [String: CostUsageDayEvidence] = [:]
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let day = Self.columnText(statement, at: 0),
                  let sourceKind = Self.columnText(statement, at: 1),
                  let scopeID = Self.columnText(statement, at: 2),
                  let lineageID = Self.columnText(statement, at: 3)
            else { throw StoreError.invalidData }
            let revision = sqlite3_column_int64(statement, 4)
            guard revision > 0 else {
                result = sqlite3_step(statement)
                continue
            }
            let verifiedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 5)) / 1000)
            values[day] = CostUsageDayEvidence(
                sourceKind: sourceKind,
                scopeID: scopeID,
                lineageID: lineageID,
                revision: revision,
                verifiedAt: verifiedAt)
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw StoreError.sqlite(result) }
        return values
    }

    /// Writes changed proof rows with one transaction-wide monotonic counter value. The caller
    /// includes aggregate/status changes in the same SQLite transaction.
    @discardableResult
    static func persistVerifiedDayEvidence(
        _ database: OpaquePointer,
        days: [String],
        scopeID: String,
        verifiedAt: Date = Date(),
        forceUpdateDays: Set<String> = []) throws -> Bool
    {
        let uniqueDays = Array(Set(days)).sorted()
        guard !uniqueDays.isEmpty else { return false }
        let existing = try Self.readVerifiedDayEvidence(
            database,
            sinceDay: uniqueDays[0],
            untilDay: uniqueDays[uniqueDays.count - 1])
        let lineageID = try Self.optionalMetaValue(database, key: Self.verifiedDayLineageKey)
        let changedDays = uniqueDays.filter { day in
            guard !forceUpdateDays.contains(day),
                  let lineageID,
                  let proof = existing[day]
            else { return true }
            return proof.sourceKind != "codexLocalLedger"
                || proof.scopeID != scopeID
                || proof.lineageID != lineageID
                || proof.revision <= 0
        }
        guard !changedDays.isEmpty else { return false }

        let stableLineageID: String
        if let lineageID, !lineageID.isEmpty {
            stableLineageID = lineageID
        } else {
            stableLineageID = UUID().uuidString.lowercased()
            try Self.writeMetaValue(stableLineageID, key: Self.verifiedDayLineageKey, database: database)
        }

        let previousRevisionText = try Self.optionalMetaValue(database, key: Self.verifiedDayRevisionKey)
        let previousRevision: Int64
        if let previousRevisionText {
            guard let parsed = Int64(previousRevisionText), parsed >= 0 else {
                throw StoreError.invalidData
            }
            previousRevision = parsed
        } else {
            previousRevision = 0
        }
        guard previousRevision < Int64.max else { throw StoreError.invalidData }
        let revision = previousRevision + 1
        try Self.writeMetaValue(String(revision), key: Self.verifiedDayRevisionKey, database: database)

        let timestamp = verifiedAt.timeIntervalSince1970 * 1000
        guard timestamp.isFinite,
              timestamp >= Double(Int64.min),
              timestamp <= Double(Int64.max)
        else { throw StoreError.invalidData }
        let verifiedAtMs = Int64(timestamp.rounded())
        let statement = try Self.prepare(database, """
        INSERT INTO verified_day_evidence(
            day, source_kind, scope_id, lineage_id, revision, verified_at_ms
        ) VALUES (?, 'codexLocalLedger', ?, ?, ?, ?)
        ON CONFLICT(day) DO UPDATE SET
            source_kind = excluded.source_kind,
            scope_id = excluded.scope_id,
            lineage_id = excluded.lineage_id,
            revision = excluded.revision,
            verified_at_ms = excluded.verified_at_ms
        """)
        defer { sqlite3_finalize(statement) }
        for day in changedDays {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            Self.bind(day, to: statement, at: 1)
            Self.bind(scopeID, to: statement, at: 2)
            Self.bind(stableLineageID, to: statement, at: 3)
            sqlite3_bind_int64(statement, 4, revision)
            sqlite3_bind_int64(statement, 5, verifiedAtMs)
            try Self.stepDone(statement, database: database)
        }
        return true
    }

    private static func writeMetaValue(
        _ value: String,
        key: String,
        database: OpaquePointer) throws
    {
        let statement = try Self.prepare(database, """
        INSERT INTO meta(key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """)
        defer { sqlite3_finalize(statement) }
        Self.bind(key, to: statement, at: 1)
        Self.bind(value, to: statement, at: 2)
        try Self.stepDone(statement, database: database)
    }

    static func clearVerifiedDayEvidence(_ database: OpaquePointer, day: String) throws {
        guard try scalarInt(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_evidence'") > 0
        else { return }
        let statement = try Self.prepare(database, "DELETE FROM verified_day_evidence WHERE day = ?")
        defer { sqlite3_finalize(statement) }
        Self.bind(day, to: statement, at: 1)
        try Self.stepDone(statement, database: database)
    }

    static func clearVerifiedDayEvidence(
        _ database: OpaquePointer,
        sinceDay: String,
        untilDay: String) throws
    {
        guard try scalarInt(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_evidence'") > 0
        else { return }
        let statement = try Self.prepare(
            database,
            "DELETE FROM verified_day_evidence WHERE day >= ? AND day <= ?")
        defer { sqlite3_finalize(statement) }
        Self.bind(sinceDay, to: statement, at: 1)
        Self.bind(untilDay, to: statement, at: 2)
        try Self.stepDone(statement, database: database)
    }

    static func clearVerifiedDayEvidence(_ database: OpaquePointer, days: Set<String>) throws {
        guard !days.isEmpty,
              try scalarInt(
                  database,
                  "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_evidence'") > 0
        else { return }
        let sortedDays = days.sorted()
        let placeholders = sortedDays.map { _ in "?" }.joined(separator: ",")
        let statement = try Self.prepare(
            database,
            "DELETE FROM verified_day_evidence WHERE day IN (\(placeholders))")
        defer { sqlite3_finalize(statement) }
        for (index, day) in sortedDays.enumerated() {
            Self.bind(day, to: statement, at: Int32(index + 1))
        }
        try Self.stepDone(statement, database: database)
    }

    /// Refreshes proof freshness after a successful source gate without changing the content
    /// revision. Repeated polling writes at most once per five minutes per day.
    @discardableResult
    static func refreshVerifiedDayEvidenceTimestamps(
        _ database: OpaquePointer,
        days: [String],
        scopeID: String,
        lineageID: String,
        verifiedAt: Date = Date()) throws -> Bool
    {
        let uniqueDays = Array(Set(days)).sorted()
        guard !uniqueDays.isEmpty else { return false }
        let timestamp = verifiedAt.timeIntervalSince1970 * 1000
        guard timestamp.isFinite,
              timestamp >= Double(Int64.min),
              timestamp <= Double(Int64.max)
        else { throw StoreError.invalidData }
        let verifiedAtMs = Int64(timestamp.rounded())
        let cutoff = verifiedAtMs.subtractingReportingOverflow(Self.verifiedDayEvidenceRefreshIntervalMs)
        let cutoffMs = cutoff.overflow ? Int64.min : cutoff.partialValue
        let statement = try Self.prepare(database, """
        UPDATE verified_day_evidence
        SET verified_at_ms = ?
        WHERE day = ?
          AND source_kind = 'codexLocalLedger'
          AND scope_id = ?
          AND lineage_id = ?
          AND revision > 0
          AND verified_at_ms <= ?
          AND verified_at_ms < ?
        """)
        defer { sqlite3_finalize(statement) }
        var changed = false
        for day in uniqueDays {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, verifiedAtMs)
            Self.bind(day, to: statement, at: 2)
            Self.bind(scopeID, to: statement, at: 3)
            Self.bind(lineageID, to: statement, at: 4)
            sqlite3_bind_int64(statement, 5, cutoffMs)
            sqlite3_bind_int64(statement, 6, verifiedAtMs)
            try Self.stepDone(statement, database: database)
            changed = changed || sqlite3_changes(database) > 0
        }
        return changed
    }

    private static func matchesCodexScanCommit(
        _ expectation: CostUsageStoreCodexScanCommit?,
        metadata: CostUsageStoreMetadata) -> Bool
    {
        guard let expectation else { return true }
        let rootPaths = Array(Set((metadata.rootMtimes.map { Array($0.keys) } ?? []).map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })).sorted()
        return metadata.lastScanUnixMs == expectation.lastScanUnixMs
            && rootPaths == expectation.rootPaths
            && metadata.timeZoneIdentifier == expectation.timeZoneIdentifier
    }

    static func markVerifiedDayStatus(
        _ database: OpaquePointer,
        sinceDay: String,
        untilDay: String,
        calendar: Calendar) throws
    {
        let dayCalendar = CostUsageScanner.CostUsageDayRange.localGregorianCalendar(matching: calendar)
        guard let since = CostUsageScanner.parseDayKey(sinceDay, calendar: dayCalendar),
              let until = CostUsageScanner.parseDayKey(untilDay, calendar: dayCalendar),
              since <= until
        else { throw StoreError.invalidData }
        var date = since
        while date <= until {
            try Self.markVerifiedDayStatus(
                database,
                day: CostUsageScanner.CostUsageDayRange.dayKey(from: date, calendar: dayCalendar))
            guard let next = dayCalendar.date(byAdding: .day, value: 1, to: date), next > date else {
                throw StoreError.invalidData
            }
            date = next
        }
    }

    static func readVerifiedDayAggregates(
        _ database: OpaquePointer,
        sinceDay: String? = nil,
        untilDay: String? = nil) throws -> [CostUsageStoreDayAggregate]
    {
        guard try scalarInt(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_aggregates'") > 0
        else { return [] }

        var sql = """
        SELECT day, model, input_tokens, cached_tokens, output_tokens, reasoning_tokens,
               request_count, unpriced_request_count, authoritative_cost_nanos,
               standard_authoritative_cost_nanos, priority_authoritative_cost_nanos,
               standard_input_tokens, standard_cached_tokens, standard_output_tokens,
               priority_input_tokens, priority_cached_tokens, priority_output_tokens,
               standard_tokens, priority_tokens, standard_resolved_cost_nanos,
               priority_resolved_cost_nanos, standard_unresolved_pricing_count,
               priority_unresolved_pricing_count
        FROM verified_day_aggregates
        """
        if sinceDay != nil, untilDay != nil {
            sql += " WHERE day >= ? AND day <= ?"
        }
        sql += " ORDER BY day, model"
        let statement = try Self.prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        if let sinceDay, let untilDay {
            Self.bind(sinceDay, to: statement, at: 1)
            Self.bind(untilDay, to: statement, at: 2)
        }
        var values: [CostUsageStoreDayAggregate] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let day = Self.columnText(statement, at: 0),
                  let model = Self.columnText(statement, at: 1)
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

    static func insertVerifiedDayAggregates(
        _ database: OpaquePointer,
        aggregates: [CostUsageStoreDayAggregate]) throws
    {
        guard !aggregates.isEmpty else { return }
        let statement = try Self.prepare(database, """
        INSERT INTO verified_day_aggregates (
            day, model, input_tokens, cached_tokens, output_tokens, reasoning_tokens,
            request_count, unpriced_request_count, authoritative_cost_nanos,
            standard_authoritative_cost_nanos, priority_authoritative_cost_nanos,
            standard_input_tokens, standard_cached_tokens, standard_output_tokens,
            priority_input_tokens, priority_cached_tokens, priority_output_tokens,
            standard_tokens, priority_tokens, standard_resolved_cost_nanos,
            priority_resolved_cost_nanos, standard_unresolved_pricing_count,
            priority_unresolved_pricing_count
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(day, model) DO UPDATE SET
            input_tokens = excluded.input_tokens,
            cached_tokens = excluded.cached_tokens,
            output_tokens = excluded.output_tokens,
            reasoning_tokens = excluded.reasoning_tokens,
            request_count = excluded.request_count,
            unpriced_request_count = excluded.unpriced_request_count,
            authoritative_cost_nanos = excluded.authoritative_cost_nanos,
            standard_authoritative_cost_nanos = excluded.standard_authoritative_cost_nanos,
            priority_authoritative_cost_nanos = excluded.priority_authoritative_cost_nanos,
            standard_input_tokens = excluded.standard_input_tokens,
            standard_cached_tokens = excluded.standard_cached_tokens,
            standard_output_tokens = excluded.standard_output_tokens,
            priority_input_tokens = excluded.priority_input_tokens,
            priority_cached_tokens = excluded.priority_cached_tokens,
            priority_output_tokens = excluded.priority_output_tokens,
            standard_tokens = excluded.standard_tokens,
            priority_tokens = excluded.priority_tokens,
            standard_resolved_cost_nanos = excluded.standard_resolved_cost_nanos,
            priority_resolved_cost_nanos = excluded.priority_resolved_cost_nanos,
            standard_unresolved_pricing_count = excluded.standard_unresolved_pricing_count,
            priority_unresolved_pricing_count = excluded.priority_unresolved_pricing_count
        """)
        defer { sqlite3_finalize(statement) }
        for aggregate in aggregates {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            Self.bind(aggregate.day, to: statement, at: 1)
            Self.bind(aggregate.model, to: statement, at: 2)
            Self.bindAggregateValues(aggregate, to: statement, startingAt: 3)
            try Self.stepDone(statement, database: database)
        }
    }

    static func replaceVerifiedDayAggregates(
        _ database: OpaquePointer,
        aggregates: [CostUsageStoreDayAggregate]) throws
    {
        guard try scalarInt(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_aggregates'") > 0
        else { throw CostUsageStore.StoreError.migration(CostUsageStore.StoreError.invalidData) }
        try execute(database, "DELETE FROM verified_day_aggregates")
        try self.insertVerifiedDayAggregates(database, aggregates: aggregates)
    }

    /// Replaces the independently verified evidence for one local day without changing the
    /// complete-history coverage markers. A bounded catch-up pass can therefore retain a sparse
    /// set of safe day rows while its full inventory proof is still pending.
    static func replaceVerifiedDayAggregates(
        _ database: OpaquePointer,
        day: String,
        aggregates: [CostUsageStoreDayAggregate]) throws
    {
        guard try scalarInt(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_aggregates'") > 0
        else { throw CostUsageStore.StoreError.migration(CostUsageStore.StoreError.invalidData) }
        let delete = try Self.prepare(database, "DELETE FROM verified_day_aggregates WHERE day = ?")
        defer { sqlite3_finalize(delete) }
        Self.bind(day, to: delete, at: 1)
        try Self.stepDone(delete, database: database)
        try self.insertVerifiedDayAggregates(database, aggregates: aggregates)
    }

    /// Persists one independently verified day from the compact aggregate table. This method
    /// deliberately never reads token snapshots, usage rows, or session payloads.
    @discardableResult
    func recordVerifiedCodexDay(
        day: String,
        calendar: Calendar,
        expectedCommit: CostUsageStoreCodexScanCommit? = nil,
        verifiedAt: Date = Date()) -> Bool
    {
        self.withDatabase(default: false) { database in
            do {
                try Self.inTransaction(database) {
                    var metadata = try Self.readSingleton(
                        CostUsageStoreMetadata.self,
                        database: database,
                        table: "scan_metadata") ?? .empty
                    guard Self.matchesCodexScanCommit(expectedCommit, metadata: metadata) else {
                        throw StoreError.invalidData
                    }
                    guard metadata.timeZoneIdentifier == nil
                        || metadata.timeZoneIdentifier == calendar.timeZone.identifier
                    else { throw StoreError.invalidData }
                    let rootPaths = metadata.rootMtimes?.keys.sorted() ?? []
                    let scopeID = CostUsageScanner.codexDayEvidenceScopeID(
                        rootPaths: rootPaths,
                        calendar: calendar)
                    let aggregates = try Self.readDayAggregates(
                        database,
                        sinceDay: day,
                        untilDay: day)
                    let priorAggregates = try Self.readVerifiedDayAggregates(
                        database,
                        sinceDay: day,
                        untilDay: day)
                    let hasStatus = try Self.readVerifiedDayStatus(
                        database,
                        sinceDay: day,
                        untilDay: day).contains(day)
                    let lineageID = try Self.optionalMetaValue(database, key: Self.verifiedDayLineageKey)
                    let proof = try Self.readVerifiedDayEvidence(
                        database,
                        sinceDay: day,
                        untilDay: day)[day]
                    let proofMatches = proof.map {
                        $0.sourceKind == "codexLocalLedger"
                            && $0.scopeID == scopeID
                            && $0.lineageID == lineageID
                            && $0.revision > 0
                    } ?? false
                    let aggregatesChanged = priorAggregates != aggregates
                    let statusChanged = !hasStatus
                    let proofChanged = !proofMatches
                    guard aggregatesChanged || statusChanged || proofChanged else {
                        guard let lineageID else { throw StoreError.invalidData }
                        _ = try Self.refreshVerifiedDayEvidenceTimestamps(
                            database,
                            days: [day],
                            scopeID: scopeID,
                            lineageID: lineageID,
                            verifiedAt: verifiedAt)
                        return
                    }

                    if aggregatesChanged {
                        try Self.replaceVerifiedDayAggregates(
                            database,
                            day: day,
                            aggregates: aggregates)
                    }
                    try Self.replaceVerifiedTemporalAggregates(
                        database,
                        sinceDay: day,
                        untilDay: day)
                    if statusChanged {
                        try Self.markVerifiedDayStatus(database, day: day)
                    }
                    _ = try Self.persistVerifiedDayEvidence(
                        database,
                        days: [day],
                        scopeID: scopeID,
                        verifiedAt: verifiedAt,
                        forceUpdateDays: aggregatesChanged || statusChanged ? Set([day]) : [])
                    metadata.verifiedUpdatedAtUnixMs = max(
                        metadata.verifiedUpdatedAtUnixMs ?? 0,
                        metadata.lastScanUnixMs > 0 ? metadata.lastScanUnixMs : 0)
                    metadata.verifiedTimeZoneIdentifier = metadata.timeZoneIdentifier
                        ?? calendar.timeZone.identifier
                    metadata.verifiedRootPaths = rootPaths
                    guard self.setMetadata(metadata) else { throw StoreError.invalidData }
                    try Self.writeVerifiedLedgerMarker(database)
                }
                return true
            } catch {
                return false
            }
        }
    }

    /// Persists a sparse, independently verified report window while another wider cache
    /// migration remains pending. The coverage markers are intentionally unchanged: callers
    /// must treat these rows as overlays, not as proof that the complete retained history is
    /// current.
    @discardableResult
    func recordVerifiedCodexWindow(
        sinceDay: String,
        untilDay: String,
        calendar: Calendar,
        expectedCommit: CostUsageStoreCodexScanCommit? = nil,
        verifiedAt: Date = Date()) -> Bool
    {
        self.withDatabase(default: false) { database in
            do {
                try Self.inTransaction(database) {
                    var metadata = try Self.readSingleton(
                        CostUsageStoreMetadata.self,
                        database: database,
                        table: "scan_metadata") ?? .empty
                    guard Self.matchesCodexScanCommit(expectedCommit, metadata: metadata) else {
                        throw StoreError.invalidData
                    }
                    let dayCalendar = CostUsageScanner.CostUsageDayRange
                        .localGregorianCalendar(matching: calendar)
                    guard sinceDay <= untilDay,
                          let since = CostUsageScanner.parseDayKey(sinceDay, calendar: dayCalendar),
                          let until = CostUsageScanner.parseDayKey(untilDay, calendar: dayCalendar),
                          CostUsageScanner.CostUsageDayRange.dayKey(
                              from: since,
                              calendar: dayCalendar) == sinceDay,
                          CostUsageScanner.CostUsageDayRange.dayKey(
                              from: until,
                              calendar: dayCalendar) == untilDay,
                          since <= until,
                          metadata.timeZoneIdentifier == nil
                          || metadata.timeZoneIdentifier == calendar.timeZone.identifier,
                          metadata.verifiedTimeZoneIdentifier == nil
                          || metadata.verifiedTimeZoneIdentifier == calendar.timeZone.identifier
                    else { throw StoreError.invalidData }
                    let days = try Self.verifiedDayKeys(
                        sinceDay: sinceDay,
                        untilDay: untilDay,
                        calendar: dayCalendar)
                    let rootPaths = metadata.rootMtimes?.keys.sorted() ?? []
                    let scopeID = CostUsageScanner.codexDayEvidenceScopeID(
                        rootPaths: rootPaths,
                        calendar: calendar)
                    let aggregates = try Self.readDayAggregates(
                        database,
                        sinceDay: sinceDay,
                        untilDay: untilDay)
                    let priorAggregates = try Self.readVerifiedDayAggregates(
                        database,
                        sinceDay: sinceDay,
                        untilDay: untilDay)
                    let currentByDay = Dictionary(grouping: aggregates, by: \.day)
                    let priorByDay = Dictionary(grouping: priorAggregates, by: \.day)
                    let aggregateChangedDays = Set(days.filter {
                        currentByDay[$0, default: []] != priorByDay[$0, default: []]
                    })
                    let existingStatuses = try Set(Self.readVerifiedDayStatus(
                        database,
                        sinceDay: sinceDay,
                        untilDay: untilDay))
                    let statusChangedDays = Set(days.filter { !existingStatuses.contains($0) })
                    let existingEvidence = try Self.readVerifiedDayEvidence(
                        database,
                        sinceDay: sinceDay,
                        untilDay: untilDay)
                    let lineageID = try Self.optionalMetaValue(database, key: Self.verifiedDayLineageKey)
                    let evidenceChangedDays = Set(days.filter { day in
                        guard let proof = existingEvidence[day],
                              let lineageID
                        else { return true }
                        return proof.sourceKind != "codexLocalLedger"
                            || proof.scopeID != scopeID
                            || proof.lineageID != lineageID
                            || proof.revision <= 0
                    })
                    let changedDays = aggregateChangedDays
                        .union(statusChangedDays)
                        .union(evidenceChangedDays)
                    guard !changedDays.isEmpty else {
                        guard let lineageID else { throw StoreError.invalidData }
                        _ = try Self.refreshVerifiedDayEvidenceTimestamps(
                            database,
                            days: days,
                            scopeID: scopeID,
                            lineageID: lineageID,
                            verifiedAt: verifiedAt)
                        return
                    }

                    for day in aggregateChangedDays.sorted() {
                        try Self.replaceVerifiedDayAggregates(
                            database,
                            day: day,
                            aggregates: currentByDay[day, default: []])
                    }
                    metadata.verifiedUpdatedAtUnixMs = max(
                        metadata.verifiedUpdatedAtUnixMs ?? 0,
                        metadata.lastScanUnixMs > 0 ? metadata.lastScanUnixMs : 0)
                    metadata.verifiedTimeZoneIdentifier = metadata.verifiedTimeZoneIdentifier
                        ?? calendar.timeZone.identifier
                    metadata.verifiedRootPaths = metadata.verifiedRootPaths
                        ?? rootPaths
                    for day in statusChangedDays {
                        try Self.markVerifiedDayStatus(database, day: day)
                    }
                    try Self.replaceVerifiedTemporalAggregates(
                        database,
                        sinceDay: sinceDay,
                        untilDay: untilDay)
                    _ = try Self.persistVerifiedDayEvidence(
                        database,
                        days: Array(changedDays),
                        scopeID: scopeID,
                        verifiedAt: verifiedAt,
                        forceUpdateDays: aggregateChangedDays.union(statusChangedDays))
                    guard self.setMetadata(metadata) else { throw StoreError.invalidData }
                    try Self.writeVerifiedLedgerMarker(database)
                }
                return true
            } catch {
                return false
            }
        }
    }

    static func verifiedDayKeys(
        sinceDay: String,
        untilDay: String,
        calendar: Calendar) throws -> [String]
    {
        guard sinceDay <= untilDay,
              let since = CostUsageScanner.parseDayKey(sinceDay, calendar: calendar),
              let until = CostUsageScanner.parseDayKey(untilDay, calendar: calendar),
              CostUsageScanner.CostUsageDayRange.dayKey(from: since, calendar: calendar) == sinceDay,
              CostUsageScanner.CostUsageDayRange.dayKey(from: until, calendar: calendar) == untilDay,
              since <= until
        else { throw StoreError.invalidData }
        var days: [String] = []
        var date = since
        while date <= until {
            days.append(CostUsageScanner.CostUsageDayRange.dayKey(from: date, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else {
                throw StoreError.invalidData
            }
            date = next
        }
        return days
    }

    /// Removes sparse verification rows for days whose hydrated source files changed. Complete
    /// coverage markers are left to the caller because a complete baseline may still be valid.
    static func clearVerifiedDayAggregates(
        _ database: OpaquePointer,
        days: Set<String>) throws
    {
        guard !days.isEmpty,
              try scalarInt(
                  database,
                  "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_aggregates'") > 0
        else { return }
        let sortedDays = days.sorted()
        let placeholders = sortedDays.map { _ in "?" }.joined(separator: ",")
        let statement = try Self.prepare(
            database,
            "DELETE FROM verified_day_aggregates WHERE day IN (\(placeholders))")
        defer { sqlite3_finalize(statement) }
        for (index, day) in sortedDays.enumerated() {
            Self.bind(day, to: statement, at: Int32(index + 1))
        }
        try Self.stepDone(statement, database: database)
        let status = try Self.prepare(
            database,
            "DELETE FROM verified_day_status WHERE day IN (\(placeholders))")
        defer { sqlite3_finalize(status) }
        for (index, day) in sortedDays.enumerated() {
            Self.bind(day, to: status, at: Int32(index + 1))
        }
        try Self.stepDone(status, database: database)
        try Self.clearVerifiedDayEvidence(database, days: Set(sortedDays))
        for day in sortedDays {
            try Self.clearVerifiedTemporalAggregates(
                database,
                sinceDay: day,
                untilDay: day)
        }
        try Self.invalidateVerifiedTemporalCoverage(database)
    }

    static func clearVerifiedDayAggregates(
        _ database: OpaquePointer,
        sinceDay: String,
        untilDay: String,
        preserveTemporalCoverage: Bool = false) throws
    {
        guard sinceDay <= untilDay,
              try scalarInt(
                  database,
                  "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'verified_day_aggregates'") > 0
        else { return }
        let statement = try Self.prepare(
            database,
            "DELETE FROM verified_day_aggregates WHERE day >= ? AND day <= ?")
        defer { sqlite3_finalize(statement) }
        Self.bind(sinceDay, to: statement, at: 1)
        Self.bind(untilDay, to: statement, at: 2)
        try Self.stepDone(statement, database: database)
        let status = try Self.prepare(
            database,
            "DELETE FROM verified_day_status WHERE day >= ? AND day <= ?")
        defer { sqlite3_finalize(status) }
        Self.bind(sinceDay, to: status, at: 1)
        Self.bind(untilDay, to: status, at: 2)
        try Self.stepDone(status, database: database)
        try Self.clearVerifiedDayEvidence(database, sinceDay: sinceDay, untilDay: untilDay)
        try Self.clearVerifiedTemporalAggregates(
            database,
            sinceDay: sinceDay,
            untilDay: untilDay)
        if !preserveTemporalCoverage {
            try Self.invalidateVerifiedTemporalCoverage(database)
        }
    }

    /// Creates the additive table and imports the last old JSON report when that is the only
    /// established state available. The caller deliberately catches this operation's failure
    /// and leaves the original database/payload untouched for a later retry.
    func migrateVerifiedDayAggregates(_ database: OpaquePointer) throws {
        #if DEBUG
        CostUsageStoreTestHooks.current.verifiedLedgerMigrationAttempt?(self.databaseURL)
        #endif
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            #if DEBUG
            try CostUsageStoreTestHooks.current.verifiedLedgerMigrationFailure?(self.databaseURL)
            #endif
            try Self.execute(database, """
            CREATE TABLE IF NOT EXISTS verified_day_aggregates (
                day TEXT NOT NULL,
                model TEXT NOT NULL,
                input_tokens INTEGER NOT NULL,
                cached_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                reasoning_tokens INTEGER NOT NULL,
                request_count INTEGER NOT NULL,
                unpriced_request_count INTEGER NOT NULL,
                authoritative_cost_nanos INTEGER NOT NULL,
                standard_authoritative_cost_nanos INTEGER NOT NULL,
                priority_authoritative_cost_nanos INTEGER NOT NULL,
                standard_input_tokens INTEGER NOT NULL,
                standard_cached_tokens INTEGER NOT NULL,
                standard_output_tokens INTEGER NOT NULL,
                priority_input_tokens INTEGER NOT NULL,
                priority_cached_tokens INTEGER NOT NULL,
                priority_output_tokens INTEGER NOT NULL,
                standard_tokens INTEGER NOT NULL,
                priority_tokens INTEGER NOT NULL,
                standard_resolved_cost_nanos INTEGER NOT NULL,
                priority_resolved_cost_nanos INTEGER NOT NULL,
                standard_unresolved_pricing_count INTEGER NOT NULL,
                priority_unresolved_pricing_count INTEGER NOT NULL,
                PRIMARY KEY(day, model)
            )
            """)
            try Self.execute(database, """
            CREATE INDEX IF NOT EXISTS verified_day_aggregates_day_idx
            ON verified_day_aggregates(day)
            """)
            try Self.execute(database, """
            CREATE INDEX IF NOT EXISTS verified_day_aggregates_model_day_idx
            ON verified_day_aggregates(model, day)
            """)

            var metadata = try Self.readSingleton(
                CostUsageStoreMetadata.self,
                database: database,
                table: "scan_metadata") ?? .empty
            let count = try Self.scalarInt(database, "SELECT COUNT(*) FROM verified_day_aggregates")
            if count == 0 {
                if !metadata.catchUpPending, try !Self.hasUnresolvedCodexForkBaseline(database) {
                    try Self.execute(database, """
                    INSERT INTO verified_day_aggregates
                    SELECT day, model, input_tokens, cached_tokens, output_tokens, reasoning_tokens,
                           request_count, unpriced_request_count, authoritative_cost_nanos,
                           standard_authoritative_cost_nanos, priority_authoritative_cost_nanos,
                           standard_input_tokens, standard_cached_tokens, standard_output_tokens,
                           priority_input_tokens, priority_cached_tokens, priority_output_tokens,
                           standard_tokens, priority_tokens, standard_resolved_cost_nanos,
                           priority_resolved_cost_nanos, standard_unresolved_pricing_count,
                           priority_unresolved_pricing_count
                    FROM day_aggregates
                    """)
                    metadata.verifiedScanSinceDay = metadata.scanSinceDay
                    metadata.verifiedScanUntilDay = metadata.scanUntilDay
                    metadata.verifiedUpdatedAtUnixMs = metadata.lastScanUnixMs > 0
                        ? metadata.lastScanUnixMs : nil
                    metadata.verifiedTimeZoneIdentifier = metadata.timeZoneIdentifier
                    metadata.verifiedRootPaths = metadata.rootMtimes?.keys.sorted()
                } else if let payload = metadata.previousReportPayload {
                    let aggregates = Self.verifiedAggregates(from: payload)
                    try Self.insertVerifiedDayAggregates(database, aggregates: aggregates)
                    if let previous = try? JSONDecoder().decode(
                        CostUsageCodexPreviousReport.self,
                        from: payload)
                    {
                        metadata.verifiedScanSinceDay = previous.scanSinceKey
                        metadata.verifiedScanUntilDay = previous.scanUntilKey
                        metadata.verifiedUpdatedAtUnixMs = previous.updatedAtUnixMs > 0
                            ? previous.updatedAtUnixMs : nil
                        metadata.verifiedTimeZoneIdentifier = metadata.timeZoneIdentifier
                        metadata.verifiedRootPaths = metadata.rootMtimes?.keys.sorted()
                    }
                }
            }
            let metadataPayload = try JSONEncoder().encode(metadata)
            let statement = try Self.prepare(database, """
            INSERT INTO scan_metadata(id, payload) VALUES (1, ?)
            ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
            """)
            defer { sqlite3_finalize(statement) }
            Self.bind(metadataPayload, to: statement, at: 1)
            try Self.stepDone(statement, database: database)
            try Self.writeVerifiedLedgerMarker(database)
            try Self.execute(database, "COMMIT")
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw StoreError.migration(error)
        }
    }

    static func writeVerifiedLedgerMarker(_ database: OpaquePointer) throws {
        let statement = try Self.prepare(database, """
        INSERT INTO meta(key, value) VALUES ('\(Self.verifiedLedgerMarkerKey)', ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """)
        defer { sqlite3_finalize(statement) }
        Self.bind(String(Self.verifiedLedgerVersion), to: statement, at: 1)
        try Self.stepDone(statement, database: database)
    }

    private static func verifiedAggregates(from payload: Data) -> [CostUsageStoreDayAggregate] {
        guard let previous = try? JSONDecoder().decode(
            CostUsageCodexPreviousReport.self,
            from: payload)
        else { return [] }
        var values: [String: CostUsageStoreDayAggregate] = [:]
        for entry in previous.data {
            let breakdowns = entry.modelBreakdowns ?? []
            if breakdowns.isEmpty {
                self.mergeVerified(
                    self.aggregate(entry: entry, model: CostUsagePricing.codexUnattributedModel),
                    into: &values)
            } else {
                for breakdown in breakdowns {
                    self.mergeVerified(
                        self.aggregate(entry: entry, breakdown: breakdown),
                        into: &values)
                }
            }
        }
        return values.values.sorted {
            $0.day == $1.day ? $0.model < $1.model : $0.day < $1.day
        }
    }

    private static func aggregate(
        entry: CostUsageCodexPreviousReport.Entry,
        model: String) -> CostUsageStoreDayAggregate
    {
        var aggregate = CostUsageStoreDayAggregate.zero(day: entry.date, model: model)
        aggregate.inputTokens = Int64(entry.inputTokens ?? 0)
        aggregate.cachedTokens = Int64(entry.cacheReadTokens ?? 0)
        aggregate.outputTokens = Int64(entry.outputTokens ?? 0)
        aggregate.reasoningTokens = Int64(entry.reasoningTokens ?? 0)
        aggregate.requestCount = Int64(entry.requestCount ?? 0)
        aggregate.standardInputTokens = aggregate.inputTokens
        aggregate.standardCachedTokens = aggregate.cachedTokens
        aggregate.standardOutputTokens = aggregate.outputTokens
        aggregate.standardTokens = aggregate.inputTokens + aggregate.outputTokens
        aggregate.authoritativeCostNanos = self.nanos(entry.costUSD)
        aggregate.standardAuthoritativeCostNanos = aggregate.authoritativeCostNanos
        if entry.costUSD == nil {
            aggregate.unpricedRequestCount = aggregate.requestCount
            aggregate.standardUnresolvedPricingCount = aggregate.requestCount
        }
        return aggregate
    }

    private static func aggregate(
        entry: CostUsageCodexPreviousReport.Entry,
        breakdown: CostUsageCodexPreviousReport.ModelBreakdown) -> CostUsageStoreDayAggregate
    {
        var aggregate = CostUsageStoreDayAggregate.zero(day: entry.date, model: breakdown.modelName)
        aggregate.inputTokens = Int64(breakdown.inputTokens ?? 0)
        aggregate.cachedTokens = Int64(breakdown.cacheReadTokens ?? 0)
        aggregate.outputTokens = Int64(breakdown.outputTokens ?? 0)
        aggregate.reasoningTokens = Int64(breakdown.reasoningTokens ?? 0)
        aggregate.requestCount = Int64(breakdown.requestCount ?? 0)
        aggregate.authoritativeCostNanos = self.nanos(breakdown.costUSD)
        let hasPriority = breakdown.priorityTokens != nil || breakdown.priorityCostUSD != nil
        if hasPriority {
            aggregate.priorityTokens = Int64(breakdown.priorityTokens ?? 0)
            aggregate.priorityAuthoritativeCostNanos = self.nanos(breakdown.priorityCostUSD)
            aggregate.priorityOutputTokens = aggregate.outputTokens
            aggregate.priorityCachedTokens = aggregate.cachedTokens
            aggregate.standardTokens = Int64(breakdown.standardTokens ?? 0)
            aggregate.standardAuthoritativeCostNanos = self.nanos(breakdown.standardCostUSD)
            aggregate.standardInputTokens = aggregate.inputTokens
            aggregate.standardCachedTokens = aggregate.cachedTokens
            aggregate.standardOutputTokens = aggregate.outputTokens
        } else {
            aggregate.standardTokens = aggregate.inputTokens + aggregate.outputTokens
            aggregate.standardInputTokens = aggregate.inputTokens
            aggregate.standardCachedTokens = aggregate.cachedTokens
            aggregate.standardOutputTokens = aggregate.outputTokens
            aggregate.standardAuthoritativeCostNanos = aggregate.authoritativeCostNanos
        }
        if breakdown.costUSD == nil {
            aggregate.unpricedRequestCount = aggregate.requestCount
            aggregate.standardUnresolvedPricingCount = aggregate.requestCount
        }
        return aggregate
    }

    private static func mergeVerified(
        _ incoming: CostUsageStoreDayAggregate,
        into values: inout [String: CostUsageStoreDayAggregate])
    {
        let key = "\(incoming.day)\u{001F}\(incoming.model)"
        guard var current = values[key] else {
            values[key] = incoming
            return
        }
        current.inputTokens += incoming.inputTokens
        current.cachedTokens += incoming.cachedTokens
        current.outputTokens += incoming.outputTokens
        current.reasoningTokens += incoming.reasoningTokens
        current.requestCount += incoming.requestCount
        current.unpricedRequestCount += incoming.unpricedRequestCount
        current.authoritativeCostNanos += incoming.authoritativeCostNanos
        current.standardAuthoritativeCostNanos += incoming.standardAuthoritativeCostNanos
        current.priorityAuthoritativeCostNanos += incoming.priorityAuthoritativeCostNanos
        current.standardInputTokens += incoming.standardInputTokens
        current.standardCachedTokens += incoming.standardCachedTokens
        current.standardOutputTokens += incoming.standardOutputTokens
        current.priorityInputTokens += incoming.priorityInputTokens
        current.priorityCachedTokens += incoming.priorityCachedTokens
        current.priorityOutputTokens += incoming.priorityOutputTokens
        current.standardTokens += incoming.standardTokens
        current.priorityTokens += incoming.priorityTokens
        current.standardResolvedCostNanos += incoming.standardResolvedCostNanos
        current.priorityResolvedCostNanos += incoming.priorityResolvedCostNanos
        current.standardUnresolvedPricingCount += incoming.standardUnresolvedPricingCount
        current.priorityUnresolvedPricingCount += incoming.priorityUnresolvedPricingCount
        values[key] = current
    }

    private static func nanos(_ value: Double?) -> Int64 {
        guard let value, value.isFinite else { return 0 }
        let scaled = value * 1_000_000_000
        guard scaled >= Double(Int64.min), scaled <= Double(Int64.max) else {
            return scaled < 0 ? Int64.min : Int64.max
        }
        return Int64(scaled.rounded())
    }
}
