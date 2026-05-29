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
//   3. Dedup rule: `existing.lastUpdated >= incoming.lastUpdated` → skip.
//      Same-or-older incoming data is rejected. The wire format has no
//      per-day timestamp, so all days in a single Mac push share the
//      `ProviderUsageSnapshot.lastUpdated`. Same-Mac, same-cycle pushes
//      are therefore correctly skipped as redundant.
//   4. The writer never deletes ledger rows. Clearing is a separate
//      explicit action (P4 + P6).

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
    /// All days in one call share `provider.lastUpdated` — the wire format
    /// has no per-day timestamp.
    static func upsertFromSnapshot(
        _ provider: ProviderUsageSnapshot,
        deviceID: String,
        in context: ModelContext) throws
    {
        guard let summary = provider.costSummary else { return }
        guard !summary.daily.isEmpty else { return }

        let encoder = CloudSyncConstants.makeJSONEncoder()
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
                lastUpdated: provider.lastUpdated,
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
            // Dedup. Skip if we already have data at least as fresh for
            // this exact (deviceID, providerID, dayKey). Same `lastUpdated`
            // = same Mac, same cycle = redundant write; older = stale.
            if existing.lastUpdated >= lastUpdated {
                return
            }
            existing.costUSD = costUSD
            existing.totalTokens = totalTokens
            existing.isEstimated = isEstimated
            existing.modelBreakdownsData = modelData
            existing.serviceBreakdownsData = serviceData
            existing.lastUpdated = lastUpdated
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
                lastUpdated: lastUpdated)
            context.insert(point)
        }
    }

    // MARK: - Aggregate (reader · Round 3 / P3)

    /// Aggregate ledger rows for the trailing `windowDays`. Cross-device
    /// merge:within the window, group by `(providerID, dayKey)` and keep
    /// the row with the largest `lastUpdated` (same rule the writer uses
    /// to dedup within a device, applied across devices at read time).
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
                if row.lastUpdated > existing.lastUpdated {
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
        var perModel: [String: Double] = [:]

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
                    perModel[breakdown.label, default: 0] += breakdown.costUSD
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
            modelMix: modelMix)
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

    // MARK: - Helpers

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
