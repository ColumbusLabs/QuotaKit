import CodexBarSync
import Foundation
import SwiftData

// MARK: - CostLedgerService (Cost Window Ledger · research doc 024)

//
// Round 2 / P2: writer half of the ledger. Reader (`aggregate(...)`),
// diagnostics, clear, seed-from-existing-blobs come in later rounds.
// Read `Research/024-cost-window-ledger/{DESIGN,ARCHITECTURE}.md` for the
// full picture; this file implements the per-day upsert + dedup contract
// they describe.
//
// Invariants:
//   1. Default OFF. `isEnabled` reads `MobileSettingsKeys.cwlEnabled` from
//      `UserDefaults.standard`. Until a user flips it (P4 UI), nothing in
//      this file runs in production — build-140 behavior is identical.
//   2. Per-day uniqueness by `(deviceID, providerID, dayKey)`. Enforced via
//      `DailyCostPoint.compositeKey` lookup before insert.
//   3. Dedup compares both payload and displayed-total revisions. A row is
//      skipped only when both stored dimensions are at least as fresh. Cost
//      summaries carry optional split freshness timestamps; legacy payloads
//      fall back to the provider's quota/status `lastUpdated`.
//   4. Partial snapshots never delete omitted rows. A complete snapshot with
//      a known history window may remove omitted rows inside that authoritative
//      window when its total revision is newer; rows outside the window stay.
//      Clearing everything is still a separate explicit action (P4 + P6).

// MARK: - Aggregate output types (Round 3 / P3)

/// Result of `CostLedgerService.aggregate(windowDays:in:asOf:)`. Mirrors
/// the shape `CostDashboardInsights` consumes today, so P4 can swap the
/// blob-derived insights for this without changing the dashboard renderer.
/// Cross-device merge is done in the aggregator (per `(providerID, dayKey)`
/// group, take the row with the largest `lastUpdated`).
struct CostLedgerAggregation: Equatable {
    /// Window the aggregator was asked to compute, in days.
    let windowDays: Int
    /// Sum of `costUSD` across every (providerID, dayKey) survivor.
    let totalCostUSD: Double
    /// Sum of `totalTokens` across every survivor.
    let totalTokens: Int
    /// Distinct dayKeys with `costUSD > 0` across all providers within the window.
    let activeDayCount: Int
    /// Per-providerID rollup. Keys are sorted lexicographically by `providerID`
    /// inside `sortedProviderRollups` for stable rendering.
    let providerRollups: [String: CostLedgerProviderRollup]
    /// Re-aggregated daily series (one entry per dayKey, summed across
    /// providers). Sorted oldest → newest.
    let dailyPoints: [SyncDailyPoint]
    /// Re-aggregated model mix across all providers and days. Sorted by
    /// `costUSD` descending.
    let modelMix: [SyncCostBreakdown]
    /// Re-aggregated service mix (e.g. Codex Cloud services) across all
    /// providers and days. Sorted by `costUSD` descending.
    let serviceMix: [SyncCostBreakdown]

    var sortedProviderRollups: [CostLedgerProviderRollup] {
        self.providerRollups.values.sorted { $0.providerID < $1.providerID }
    }
}

struct CostLedgerProviderRollup: Equatable {
    let providerID: String
    /// Account email (nil for single-account). Together with `providerID`
    /// forms the `cardIdentityKey` the Cost dashboard renders rows by.
    let accountEmail: String?
    let totalCostUSD: Double
    let totalTokens: Int
    /// Daily points just for this provider, sorted oldest → newest.
    let dailyPoints: [SyncDailyPoint]
    /// Model mix just for this provider. Sorted by `costUSD` descending.
    let modelBreakdowns: [SyncCostBreakdown]
}

/// Lightweight ledger diagnostics for the Settings panel (P4). All fields
/// are O(rows) to compute; safe for an immediate call. `estimatedBytes` is a
/// coarse estimate (`row count × 200`), not a real on-disk measurement.
struct CostLedgerDiagnostics: Equatable {
    let deviceCount: Int
    let providerCount: Int
    let dayCount: Int
    let rowCount: Int
    let earliestDayKey: String?
    let latestWriteAt: Date?
    let estimatedBytes: Int
}

// MARK: - CostLedgerService

enum CostLedgerService {
    /// `YYYY-MM-DD` UTC formatter, matches the wire format's `SyncDailyPoint.dayKey`.
    /// Static so we don't reallocate per call; `DateFormatter` is reentrant-safe
    /// for read-only use after configuration.
    static let utcDayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Gate

    /// True iff the CWL feature flag is on. Reads `cwlEnabled` from the
    /// supplied `UserDefaults` (defaults to `.standard`). Test-friendly —
    /// pass a per-suite `UserDefaults(suiteName:)` to verify the flag
    /// logic without touching the shared store.
    static func isEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: MobileSettingsKeys.cwlEnabled)
    }

    // MARK: - Upsert: snapshot → daily rows

    /// Iterate `provider.costSummary?.daily` and upsert each day as a
    /// `DailyCostPoint` row. Called from `SwiftDataBridge.upsertProvider`
    /// **after** the existing blob write, **only when** `isEnabled()` is
    /// true. The blob path always runs, so even with CWL on the ledger and
    /// the blob stay in sync (the blob acts as a fallback / authoritative
    /// snapshot for the current Mac window).
    ///
    /// All days in one call share the summary's cost freshness timestamp.
    /// Legacy summaries without independent cost freshness fall back to
    /// `provider.lastUpdated`.
    static func upsertFromSnapshot(
        _ provider: ProviderUsageSnapshot,
        deviceID: String,
        in context: ModelContext) throws
    {
        guard let summary = provider.costSummary else { return }

        let costUpdatedAt = summary.costUpdatedAt ?? provider.lastUpdated
        let totalCostUpdatedAt = summary.totalCostUpdatedAt ?? costUpdatedAt
        let sourceRevisionKey = Self.ledgerSourceRevisionKey(
            summary,
            providerLastUpdated: provider.lastUpdated)
        let encoder = CloudSyncConstants.makeJSONEncoder()
        try Self.deleteOmittedCompleteHistoryRowsIfNeeded(
            summary: summary,
            provider: provider,
            deviceID: deviceID,
            totalUpdatedAt: totalCostUpdatedAt,
            in: context)
        for point in summary.daily {
            try Self.upsertDayPoint(
                deviceID: deviceID,
                providerID: provider.providerID,
                accountEmail: provider.accountEmail,
                dayKey: point.dayKey,
                costUSD: point.costUSD,
                totalTokens: point.totalTokens,
                isEstimated: point.isEstimated,
                modelBreakdowns: point.modelBreakdowns,
                serviceBreakdowns: point.serviceBreakdowns,
                lastUpdated: costUpdatedAt,
                totalUpdatedAt: totalCostUpdatedAt,
                sourceRevisionKey: sourceRevisionKey,
                encoder: encoder,
                in: context)
        }
    }

    /// Granular upsert for a single `(deviceID, providerID, dayKey)`.
    /// Exposed (internal) so tests can drive the dedup rule directly
    /// without constructing a full `ProviderUsageSnapshot`. Also reusable
    /// by future rounds (e.g. `seedFromExistingBlobs` in P6).
    static func upsertDayPoint(
        // `accountEmail` defaults to nil for the single-account convenience
        // case (tests, future single-account seed). The real production
        // entry `upsertFromSnapshot` always passes `provider.accountEmail`
        // explicitly — the multi-account-collision bug this key fix closes
        // lived there, not here.
        deviceID: String,
        providerID: String,
        accountEmail: String? = nil,
        dayKey: String,
        costUSD: Double,
        totalTokens: Int,
        isEstimated: Bool?,
        modelBreakdowns: [SyncCostBreakdown],
        serviceBreakdowns: [SyncCostBreakdown],
        lastUpdated: Date,
        totalUpdatedAt: Date? = nil,
        sourceRevisionKey: String? = nil,
        encoder: JSONEncoder? = nil,
        in context: ModelContext) throws
    {
        let key = DailyCostPoint.makeCompositeKey(
            deviceID: deviceID,
            providerID: providerID,
            accountEmail: accountEmail,
            dayKey: dayKey)
        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate { $0.compositeKey == key })

        let enc = encoder ?? CloudSyncConstants.makeJSONEncoder()
        let modelData: Data? = modelBreakdowns.isEmpty
            ? nil
            : try? enc.encode(modelBreakdowns)
        let serviceData: Data? = serviceBreakdowns.isEmpty
            ? nil
            : try? enc.encode(serviceBreakdowns)

        if let existing = try context.fetch(descriptor).first {
            // A partial Codex history update is allowed to add previously
            // absent days, but it must never overwrite a day established by
            // a complete (or legacy/unknown) history revision. The ledger has
            // no omission context at this per-day granularity; the wrapper's
            // complete-window deletion pass handles that separately. The
            // coverage marker keeps this writer from turning a newer partial
            // row into a lower total after the cache/blob path is bypassed.
            let incomingCoverage = Self.historyCoverage(from: sourceRevisionKey)
            let existingCoverage = Self.historyCoverage(from: existing.sourceRevisionKey)
            if incomingCoverage == false, existingCoverage != false {
                return
            }

            // A newer dashboard breakdown revision can be ahead of the local
            // scanner total. Compare the full two-dimensional revision so a
            // scanner advance cannot be hidden behind an unchanged max
            // payload timestamp.
            let incomingTotalUpdatedAt = totalUpdatedAt ?? lastUpdated
            let existingTotalUpdatedAt = existing.totalUpdatedAt ?? existing.lastUpdated
            if existing.lastUpdated >= lastUpdated,
               existingTotalUpdatedAt >= incomingTotalUpdatedAt,
               existing.lastUpdated > lastUpdated
               || existingTotalUpdatedAt > incomingTotalUpdatedAt
               || existing.sourceRevisionKey == sourceRevisionKey
            {
                return
            }
            existing.costUSD = costUSD
            existing.totalTokens = totalTokens
            existing.isEstimated = isEstimated
            existing.modelBreakdownsData = modelData
            existing.serviceBreakdownsData = serviceData
            existing.lastUpdated = max(existing.lastUpdated, lastUpdated)
            existing.totalUpdatedAt = max(existingTotalUpdatedAt, incomingTotalUpdatedAt)
            existing.sourceRevisionKey = sourceRevisionKey
        } else {
            let point = DailyCostPoint(
                deviceID: deviceID,
                providerID: providerID,
                accountEmail: accountEmail,
                dayKey: dayKey,
                costUSD: costUSD,
                totalTokens: totalTokens,
                isEstimated: isEstimated,
                modelBreakdownsData: modelData,
                serviceBreakdownsData: serviceData,
                lastUpdated: lastUpdated,
                totalUpdatedAt: totalUpdatedAt ?? lastUpdated,
                sourceRevisionKey: sourceRevisionKey)
            context.insert(point)
        }
    }

    // MARK: - Aggregate (reader · Round 3 / P3)

    /// Aggregate ledger rows for the trailing `windowDays`. Cross-device
    /// merge:within the window, group by `(providerID, dayKey)` and prefer
    /// the row with the newest displayed-total revision, breaking ties with
    /// the payload revision. This prevents a newer breakdown-only dashboard
    /// response from masking a newer total on another device.
    ///
    /// `asOf` exists for deterministic tests; production callers pass `Date()`.
    /// The "window" is `[asOf-(windowDays-1) … asOf]` in UTC dayKeys.
    ///
    /// O(n) over surviving rows after window filter. For Round 7 / P7
    /// performance work we may move this to a background actor; for now
    /// it runs on the caller's context (P4 calls from `@MainActor`).
    static func aggregate(
        windowDays: Int,
        in context: ModelContext,
        asOf: Date = Date()) throws -> CostLedgerAggregation
    {
        let windowDays = max(1, min(windowDays, 365))
        let cutoffKey = Self.cutoffDayKey(windowDays: windowDays, asOf: asOf)

        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate { $0.dayKey >= cutoffKey })
        let rows = try context.fetch(descriptor)

        // Cross-device merge: group by (providerID, accountEmail, dayKey), keep
        // latest lastUpdated. accountEmail is part of the key so multi-account
        // providers stay distinct (matching the blob path's cardIdentityKey).
        var survivors: [String: DailyCostPoint] = [:]
        for row in rows {
            let key = "\(row.providerID)|\(row.accountEmail ?? "_")|\(row.dayKey)"
            if let existing = survivors[key] {
                let rowTotalUpdatedAt = row.totalUpdatedAt ?? row.lastUpdated
                let existingTotalUpdatedAt = existing.totalUpdatedAt ?? existing.lastUpdated
                if rowTotalUpdatedAt > existingTotalUpdatedAt
                    || (rowTotalUpdatedAt == existingTotalUpdatedAt
                        && row.lastUpdated > existing.lastUpdated)
                {
                    survivors[key] = row
                }
            } else {
                survivors[key] = row
            }
        }

        let decoder = CloudSyncConstants.makeJSONDecoder()
        // Per-account-provider accumulators, keyed by cardIdentityKey
        // (providerID|accountEmail) so the dashboard can match rows per account.
        var perProvider: [String: ProviderAccumulator] = [:]
        // Per-day + per-model aggregate ACROSS all providers/accounts (these
        // intentionally collapse account distinction — they're cross-cutting).
        var perDay: [String: DayAccumulator] = [:]
        // Per-model cost, token total, and Codex standard/fast split, summed
        // across the window so the rebuilt Model Mix is at parity with the
        // blob path for both Cost and Tokens modes.
        var perModel: [String: (
            cost: Double,
            tokens: Int,
            hasTokens: Bool,
            std: Double,
            fast: Double,
            hasSplit: Bool)] = [:]
        var perService: [String: Double] = [:]

        for survivor in survivors.values {
            let rollupKey = "\(survivor.providerID)|\(survivor.accountEmail ?? "_")"
            var acc = perProvider[rollupKey] ?? ProviderAccumulator(
                providerID: survivor.providerID,
                accountEmail: survivor.accountEmail)
            acc.ingest(survivor, decoder: decoder)
            perProvider[rollupKey] = acc

            perDay[survivor.dayKey, default: .init()].ingest(survivor)
            if let data = survivor.modelBreakdownsData,
               let decoded = try? decoder.decode([SyncCostBreakdown].self, from: data)
            {
                for breakdown in decoded where breakdown.costUSD > 0 {
                    var entry = perModel[breakdown.label] ?? (0, 0, false, 0, 0, false)
                    entry.cost += breakdown.costUSD
                    if let tokens = breakdown.modelTokens {
                        entry.tokens += tokens
                        entry.hasTokens = true
                    }
                    if breakdown.standardCostUSD != nil || breakdown.priorityCostUSD != nil {
                        entry.hasSplit = true
                        entry.std += breakdown.standardCostUSD ?? 0
                        entry.fast += breakdown.priorityCostUSD ?? 0
                    }
                    perModel[breakdown.label] = entry
                }
            }
            if let data = survivor.serviceBreakdownsData,
               let decoded = try? decoder.decode([SyncCostBreakdown].self, from: data)
            {
                for breakdown in decoded where breakdown.costUSD > 0 {
                    perService[breakdown.label, default: 0] += breakdown.costUSD
                }
            }
        }

        let providerRollupsKeyed = Dictionary(
            uniqueKeysWithValues: perProvider.map { rollupKey, acc in
                (rollupKey, acc.toRollup())
            })

        let dailyPoints = perDay
            .sorted { $0.key < $1.key }
            .map { dayKey, acc in
                SyncDailyPoint(
                    dayKey: dayKey,
                    costUSD: acc.costUSD,
                    totalTokens: acc.totalTokens,
                    modelBreakdowns: [],
                    serviceBreakdowns: [],
                    isEstimated: nil)
            }

        let modelMix = perModel
            .map { label, entry in
                SyncCostBreakdown(
                    label: label,
                    costUSD: entry.cost,
                    totalTokens: entry.hasTokens ? entry.tokens : nil,
                    standardCostUSD: entry.hasSplit ? entry.std : nil,
                    priorityCostUSD: entry.hasSplit ? entry.fast : nil)
            }
            .sorted { $0.costUSD > $1.costUSD }

        let serviceMix = perService
            .map { SyncCostBreakdown(label: $0.key, costUSD: $0.value) }
            .sorted { $0.costUSD > $1.costUSD }

        let totalCostUSD = perDay.values.reduce(0) { $0 + $1.costUSD }
        let totalTokens = perDay.values.reduce(0) { $0 + $1.totalTokens }
        let activeDayCount = perDay.values.count(where: { $0.costUSD > 0 })

        return CostLedgerAggregation(
            windowDays: windowDays,
            totalCostUSD: totalCostUSD,
            totalTokens: totalTokens,
            activeDayCount: activeDayCount,
            providerRollups: providerRollupsKeyed,
            dailyPoints: dailyPoints,
            modelMix: modelMix,
            serviceMix: serviceMix)
    }

    /// Same as `aggregate(...)` but filtered to one provider. Used by
    /// `ProviderDetailView` (P4) — avoids materialising the cross-provider
    /// aggregate just to display a single provider's per-day cost section.
    static func aggregateProvider(
        providerID: String,
        accountEmail: String?,
        windowDays: Int,
        in context: ModelContext,
        asOf: Date = Date()) throws -> CostLedgerProviderRollup
    {
        let full = try Self.aggregate(
            windowDays: windowDays, in: context, asOf: asOf)
        let rollupKey = "\(providerID)|\(accountEmail ?? "_")"
        return full.providerRollups[rollupKey] ?? CostLedgerProviderRollup(
            providerID: providerID,
            accountEmail: accountEmail,
            totalCostUSD: 0,
            totalTokens: 0,
            dailyPoints: [],
            modelBreakdowns: [])
    }

    // MARK: - Diagnostics (Round 3 / P3)

    /// Coarse ledger health stats for the Settings diagnostics panel (P4).
    /// O(n) over ledger rows.
    static func diagnostics(in context: ModelContext) throws -> CostLedgerDiagnostics {
        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        let devices = Set(rows.map(\.deviceID))
        let providers = Set(rows.map(\.providerID))
        let days = Set(rows.map(\.dayKey))
        let earliestDayKey = days.min()
        let latestWriteAt = rows.map(\.lastUpdated).max()
        // Coarse estimate (200 bytes/row is a reasonable upper bound for
        // a DailyCostPoint with both encoded blobs). Real on-disk size
        // requires reading the SQLite file; deferred to P7.
        let estimatedBytes = rows.count * 200

        return CostLedgerDiagnostics(
            deviceCount: devices.count,
            providerCount: providers.count,
            dayCount: days.count,
            rowCount: rows.count,
            earliestDayKey: earliestDayKey,
            latestWriteAt: latestWriteAt,
            estimatedBytes: estimatedBytes)
    }

    // MARK: - Clear (explicit user action · Round 6 / P4b)

    /// Delete every `DailyCostPoint` row. Wired to the Settings "clear ledger"
    /// button (with a confirmation dialog). Touches ONLY the ledger — the blob
    /// path (`ProviderSnapshotModel.costSummaryData`) and all other SwiftData
    /// entities are untouched, so toggling CWL off + clearing leaves the
    /// build-140 dashboard fully intact.
    static func clearAll(in context: ModelContext) throws {
        try context.delete(model: DailyCostPoint.self)
        try context.save()
    }

    // MARK: - Seed from existing blobs (migration · Round 7 / P6)

    /// One-shot import of the existing blob-path data into the ledger. Run on
    /// the user's first CWL enable so the dashboard has history immediately
    /// (instead of waiting for the next Mac sync to rebuild it). Reads every
    /// `ProviderSnapshotModel` row, decodes its `costSummaryData`, and upserts
    /// each daily point keyed by the row's (deviceID, providerID, accountEmail).
    ///
    /// Idempotent: re-running seeds the same `(deviceID, providerID,
    /// accountEmail, dayKey)` keys with the same `lastUpdated`, so the dedup
    /// rule (`existing.lastUpdated >= incoming → skip`) makes a second run a
    /// no-op. A corrupt / undecodable blob is skipped (that provider just has
    /// no seeded history); other rows still seed. Throws only on the final
    /// `save()` — the caller (toggle-on) turns CWL back off on throw.
    static func seedFromExistingBlobs(in context: ModelContext) throws {
        let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        let decoder = CloudSyncConstants.makeJSONDecoder()
        let encoder = CloudSyncConstants.makeJSONEncoder()
        for row in providers {
            guard let blob = row.costSummaryData,
                  let summary = try? decoder.decode(SyncCostSummary.self, from: blob)
            else { continue }
            for point in summary.daily {
                try Self.upsertDayPoint(
                    deviceID: row.deviceID,
                    providerID: row.providerID,
                    accountEmail: row.accountEmail,
                    dayKey: point.dayKey,
                    costUSD: point.costUSD,
                    totalTokens: point.totalTokens,
                    isEstimated: point.isEstimated,
                    modelBreakdowns: point.modelBreakdowns,
                    serviceBreakdowns: point.serviceBreakdowns,
                    lastUpdated: summary.costUpdatedAt ?? row.lastUpdated,
                    sourceRevisionKey: Self.ledgerSourceRevisionKey(
                        summary,
                        providerLastUpdated: row.lastUpdated),
                    encoder: encoder,
                    in: context)
            }
        }
        try context.save()
    }

    // MARK: - Helpers

    /// Removes rows omitted by a newer complete history snapshot, but only
    /// inside that snapshot's known trailing window. A partial scan must not
    /// call this path: omission from a partial result is explicitly a no-op.
    private static func deleteOmittedCompleteHistoryRowsIfNeeded(
        summary: SyncCostSummary,
        provider: ProviderUsageSnapshot,
        deviceID: String,
        totalUpdatedAt: Date,
        in context: ModelContext) throws
    {
        guard summary.historyCoverageIsEstablished == true,
              let historyDays = summary.historyDays,
              historyDays > 0
        else {
            return
        }

        // Cost freshness is the closest available as-of marker. Legacy
        // callers still fall back to the provider timestamp, which is also
        // what the writer uses when materializing the row revisions.
        let asOf = summary.costUpdatedAt ?? provider.lastUpdated
        let authoritativeBounds = Self.authoritativeHistoryBounds(
            summary: summary,
            historyDays: historyDays,
            fallbackAsOf: asOf)
        let cutoffKey = authoritativeBounds.since
        let asOfKey = authoritativeBounds.until
        let providerID = provider.providerID
        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate { row in
                row.deviceID == deviceID
                    && row.providerID == providerID
                    && row.dayKey >= cutoffKey
                    && row.dayKey <= asOfKey
            })
        let existingRows = try context.fetch(descriptor).filter {
            $0.accountEmail == provider.accountEmail
        }
        guard !existingRows.isEmpty else { return }

        // Never delete from a window that has a newer or equal aggregate
        // revision already present. This keeps stale complete payloads from
        // deleting rows established by a later correction on the same key.
        let hasNewerExistingTotal = existingRows.contains {
            ($0.totalUpdatedAt ?? $0.lastUpdated) >= totalUpdatedAt
        }
        guard !hasNewerExistingTotal else { return }

        let incomingDayKeys = Set(summary.daily.map(\.dayKey))
        for row in existingRows where !incomingDayKeys.contains(row.dayKey) {
            context.delete(row)
        }
    }

    /// Adds history completeness to the revision vector stored alongside a
    /// daily row. This is intentionally kept in the existing string field so
    /// older SwiftData stores migrate without a schema change.
    private static func ledgerSourceRevisionKey(
        _ summary: SyncCostSummary,
        providerLastUpdated: Date) -> String
    {
        let coverage = switch summary.historyCoverageIsEstablished {
        case true: "established"
        case false: "partial"
        case nil: "legacy"
        }
        return "\(summary.mobileRevisionKey(providerLastUpdated: providerLastUpdated))|historyCoverage=\(coverage)"
    }

    private static func historyCoverage(from revisionKey: String?) -> Bool? {
        guard let revisionKey,
              let marker = revisionKey.split(separator: "|").last(where: {
                  $0.hasPrefix("historyCoverage=")
              })
        else {
            return nil
        }
        switch marker.dropFirst("historyCoverage=".count) {
        case "established": return true
        case "partial": return false
        default: return nil
        }
    }

    /// `[asOf - (windowDays - 1) days, asOf]` lower bound as a `YYYY-MM-DD`
    /// UTC dayKey string. Comparison against `DailyCostPoint.dayKey` works
    /// lexicographically because the format is fixed-width.
    static func cutoffDayKey(windowDays: Int, asOf: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let cutoff = calendar.date(
            byAdding: .day,
            value: -(windowDays - 1),
            to: asOf) ?? asOf
        return Self.utcDayKeyFormatter.string(from: cutoff)
    }

    /// Resolves deletion bounds from producer-authored day keys whenever
    /// available. Day keys are calendar dates, so subtracting in UTC is safe
    /// once the Mac-local end date has already been serialized as a key.
    private static func authoritativeHistoryBounds(
        summary: SyncCostSummary,
        historyDays: Int,
        fallbackAsOf: Date) -> (since: String, until: String)
    {
        if let since = summary.historySinceDayKey,
           let until = summary.historyUntilDayKey,
           since <= until
        {
            return (since, until)
        }
        if let until = summary.historyUntilDayKey
            ?? summary.daily.map(\.dayKey).max(),
            let since = Self.cutoffDayKey(windowDays: historyDays, endingAtDayKey: until)
        {
            return (since, until)
        }
        return (
            Self.cutoffDayKey(windowDays: historyDays, asOf: fallbackAsOf),
            Self.utcDayKeyFormatter.string(from: fallbackAsOf))
    }

    private static func cutoffDayKey(windowDays: Int, endingAtDayKey: String) -> String? {
        guard let end = utcDayKeyFormatter.date(from: endingAtDayKey) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let cutoff = calendar.date(
            byAdding: .day,
            value: -(windowDays - 1),
            to: end) ?? end
        return Self.utcDayKeyFormatter.string(from: cutoff)
    }

    // MARK: - Private accumulators

    private struct DayAccumulator {
        var costUSD: Double = 0
        var totalTokens: Int = 0
        mutating func ingest(_ row: DailyCostPoint) {
            self.costUSD += row.costUSD
            self.totalTokens += row.totalTokens
        }
    }

    private struct ProviderAccumulator {
        let providerID: String
        let accountEmail: String?
        var costUSD: Double = 0
        var totalTokens: Int = 0
        var perDay: [String: (cost: Double, tokens: Int)] = [:]
        var perModel: [String: Double] = [:]

        init(providerID: String, accountEmail: String?) {
            self.providerID = providerID
            self.accountEmail = accountEmail
        }

        mutating func ingest(_ row: DailyCostPoint, decoder: JSONDecoder) {
            self.costUSD += row.costUSD
            self.totalTokens += row.totalTokens
            self.perDay[row.dayKey, default: (0, 0)].cost += row.costUSD
            self.perDay[row.dayKey, default: (0, 0)].tokens += row.totalTokens
            if let data = row.modelBreakdownsData,
               let decoded = try? decoder.decode([SyncCostBreakdown].self, from: data)
            {
                for breakdown in decoded where breakdown.costUSD > 0 {
                    self.perModel[breakdown.label, default: 0] += breakdown.costUSD
                }
            }
        }

        func toRollup() -> CostLedgerProviderRollup {
            CostLedgerProviderRollup(
                providerID: self.providerID,
                accountEmail: self.accountEmail,
                totalCostUSD: self.costUSD,
                totalTokens: self.totalTokens,
                dailyPoints: self.perDay
                    .sorted { $0.key < $1.key }
                    .map { day, vals in
                        SyncDailyPoint(
                            dayKey: day,
                            costUSD: vals.cost,
                            totalTokens: vals.tokens,
                            modelBreakdowns: [],
                            serviceBreakdowns: [],
                            isEstimated: nil)
                    },
                modelBreakdowns: self.perModel
                    .map { SyncCostBreakdown(label: $0.key, costUSD: $0.value) }
                    .sorted { $0.costUSD > $1.costUSD })
        }
    }
}
