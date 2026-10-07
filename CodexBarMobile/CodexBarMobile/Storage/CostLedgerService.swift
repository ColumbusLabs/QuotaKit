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
/// Cross-device merge is done in the aggregator: local history rows from
/// distinct devices are summed; account-level rows use the newest revision.
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
    /// Days whose local contributor set is known to be incomplete or whose
    /// per-device proof is missing. Consumers must not replace this with a
    /// fresh aggregate or quota timestamp.
    let incompleteDayEvidenceDayKeys: Set<String>
    /// Conservative daily verification freshness for this provider/account.
    /// A date is present only when every retained device contribution for
    /// that day carried evidence; it is the oldest verification among them.
    /// This is display freshness, not a synthesized proof for the aggregate.
    let dayEvidenceVerifiedAt: [String: Date]
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
    /// These providers read per-machine local histories. Their ledger rows
    /// are independent contributions and must all survive aggregation; API
    /// backed providers instead represent one account-level total and use
    /// newest-row deduplication below.
    private static let localCostProviders: Set<String> = ["claude", "codex", "vertexai", "pi"]

    /// Builds the current per-provider/account Mac inventory from the live
    /// device snapshots. A live source can contribute to a local history
    /// even before its first ledger row arrives, so ledger rows alone cannot
    /// certify a multi-Mac daily total.
    static func expectedLocalContributorDeviceIDsByProviderKey(
        from devices: [SyncedUsageSnapshot]) -> [String: Set<String>]
    {
        var contributors: [String: Set<String>] = [:]
        for device in devices {
            let deviceID = device.deviceID ?? SnapshotCache.syntheticDeviceID(from: device)
            for provider in device.providers where Self.localCostProviders.contains(provider.providerID)
                && provider.costSummary != nil
            {
                let key = "\(provider.providerID)|\(provider.accountEmail ?? "_")"
                contributors[key, default: []].insert(deviceID)
            }
        }
        return contributors
    }

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
        try Self.migrateNilEmailRowsIfNeeded(
            provider: provider,
            deviceID: deviceID,
            in: context)
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
                // A point-level flag wins because the summary can be false
                // for a different day. Older points without their own flag
                // inherit the summary-level unknown marker.
                costIsKnown: point.costIsKnown ?? summary.costIsKnown,
                isEstimated: point.isEstimated,
                modelBreakdowns: point.modelBreakdowns,
                serviceBreakdowns: point.serviceBreakdowns,
                lastUpdated: costUpdatedAt,
                totalUpdatedAt: totalCostUpdatedAt,
                sourceRevisionKey: sourceRevisionKey,
                historyCoverageIsEstablished: summary.historyCoverageIsEstablished,
                historySinceDayKey: summary.historySinceDayKey,
                historyUntilDayKey: summary.historyUntilDayKey,
                dayEvidence: point.dayEvidence,
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
        costIsKnown: Bool? = nil,
        isEstimated: Bool?,
        modelBreakdowns: [SyncCostBreakdown],
        serviceBreakdowns: [SyncCostBreakdown],
        lastUpdated: Date,
        totalUpdatedAt: Date? = nil,
        sourceRevisionKey: String? = nil,
        historyCoverageIsEstablished: Bool? = nil,
        historySinceDayKey: String? = nil,
        historyUntilDayKey: String? = nil,
        dayEvidence: SyncDayEvidence? = nil,
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
        let acceptedDayEvidence = dayEvidence.flatMap { $0.isValid ? $0 : nil }
        let normalizedSourceRevisionKey = Self.withDayEvidence(
            Self.withCostKnown(sourceRevisionKey, known: costIsKnown != false),
            evidence: acceptedDayEvidence)

        if let existing = try context.fetch(descriptor).first {
            let existingEvidence = Self.dayEvidence(from: existing.sourceRevisionKey)
            if let dayEvidence = acceptedDayEvidence {
                let incomingTotalRevision = totalUpdatedAt ?? lastUpdated
                let existingTotalRevision = existing.totalUpdatedAt ?? existing.lastUpdated
                let decision = Self.dayEvidenceUpdateDecision(
                    dayEvidence,
                    existing: existingEvidence,
                    dayKey: dayKey,
                    historyCoverageIsEstablished: historyCoverageIsEstablished,
                    historySinceDayKey: historySinceDayKey,
                    historyUntilDayKey: historyUntilDayKey,
                    incomingTotalRevision: incomingTotalRevision,
                    existingTotalRevision: existingTotalRevision)
                switch decision {
                case .reject:
                    return
                case .refreshFreshness:
                    // An idle verified source can advance its proof clock
                    // without changing the source revision or payload.
                    existing.totalUpdatedAt = max(existingTotalRevision, dayEvidence.verifiedAt)
                    // Keep pricing certainty and history-coverage markers
                    // from the retained revision. Equal source counters do
                    // not authorize a payload or knownness transition.
                    existing.sourceRevisionKey = Self.withDayEvidence(
                        existing.sourceRevisionKey,
                        evidence: dayEvidence)
                    return
                case .replaceValues:
                    break
                }

                let resolvedCostIsKnown = costIsKnown != false
                let existingCostIsKnown = Self.costIsKnown(from: existing.sourceRevisionKey) != false
                let preserveKnownCost = !resolvedCostIsKnown && existingCostIsKnown

                // A newer verified point can establish an unproven row or
                // correct a comparable proofed day even when its enclosing
                // summary is partial. If the source now has unpriced activity,
                // preserve previously known dollars and their breakdowns while
                // accepting the newer tokens, unknown-cost marker, and proof.
                Self.replaceDay(
                    existing,
                    costUSD: preserveKnownCost ? existing.costUSD : costUSD,
                    totalTokens: totalTokens,
                    isEstimated: preserveKnownCost ? (existing.isEstimated ?? isEstimated) : isEstimated,
                    modelData: preserveKnownCost ? existing.modelBreakdownsData : modelData,
                    serviceData: preserveKnownCost ? existing.serviceBreakdownsData : serviceData,
                    lastUpdated: lastUpdated,
                    totalUpdatedAt: max(
                        totalUpdatedAt ?? lastUpdated,
                        dayEvidence.verifiedAt),
                    sourceRevisionKey: Self.withCostKnown(
                        normalizedSourceRevisionKey,
                        known: resolvedCostIsKnown))
                return
            }

            // An older payload cannot order itself against an independently
            // versioned day. Keep the proofed value and its pricing marker.
            if existingEvidence != nil { return }

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
                // A lower-coverage update may advance token counts, but it
                // cannot replace or re-certify the established cost. Once a
                // partial update exposes unpriced activity, only a complete
                // revision can restore knownness.
                let existingCostIsKnown = Self.costIsKnown(
                    from: existing.sourceRevisionKey) != false
                existing.totalTokens = max(existing.totalTokens, totalTokens)
                existing.lastUpdated = max(existing.lastUpdated, lastUpdated)
                // Keep the established row's coverage identity. Replacing it
                // with the incoming partial revision would make the next
                // partial update look eligible to overwrite the protected
                // cost. Cost-known state may advance independently.
                existing.sourceRevisionKey = Self.withCostKnown(
                    existing.sourceRevisionKey,
                    known: existingCostIsKnown && costIsKnown != false)
                return
            }

            let incomingCostIsKnown = costIsKnown != false
            let existingCostIsKnown = Self.costIsKnown(from: existing.sourceRevisionKey) != false

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
               || existing.sourceRevisionKey == normalizedSourceRevisionKey
            {
                return
            }
            if incomingCostIsKnown || !existingCostIsKnown {
                existing.costUSD = costUSD
            }
            existing.totalTokens = totalTokens
            if incomingCostIsKnown || !existingCostIsKnown {
                existing.isEstimated = isEstimated
                existing.modelBreakdownsData = modelData
                existing.serviceBreakdownsData = serviceData
            }
            existing.lastUpdated = max(existing.lastUpdated, lastUpdated)
            existing.totalUpdatedAt = max(existingTotalUpdatedAt, incomingTotalUpdatedAt)
            existing.sourceRevisionKey = Self.withCostKnown(
                normalizedSourceRevisionKey,
                known: incomingCostIsKnown || existingCostIsKnown)
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
                sourceRevisionKey: normalizedSourceRevisionKey)
            context.insert(point)
        }
    }

    // MARK: - Aggregate (reader · Round 3 / P3)

    /// Aggregate ledger rows for the trailing `windowDays`. Cross-device
    /// merge: within the window, local history providers retain each device's
    /// rows; account-level providers keep the row with the newest displayed-
    /// total revision, breaking ties with the payload revision. This prevents
    /// a newer breakdown-only dashboard response from masking a newer total.
    ///
    /// `asOf` exists for deterministic tests; production callers pass `Date()`.
    /// The "window" is `[asOf-(windowDays-1) … asOf]` in UTC dayKeys.
    ///
    /// O(n) over surviving rows after window filter. For Round 7 / P7
    /// performance work we may move this to a background actor; for now
    /// it runs on the caller's context (P4 calls from `@MainActor`).
    static func aggregate(
        windowDays: Int,
        expectedLocalContributorDeviceIDsByProviderKey: [String: Set<String>] = [:],
        in context: ModelContext,
        asOf: Date = Date()) throws -> CostLedgerAggregation
    {
        let windowDays = max(1, min(windowDays, 365))
        let cutoffKey = Self.cutoffDayKey(windowDays: windowDays, asOf: asOf)

        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate { $0.dayKey >= cutoffKey })
        let rows = try context.fetch(descriptor)

        // Cross-device merge: account-level providers group by
        // (providerID, accountEmail, dayKey) and keep the newest row. Local
        // history providers retain device identity in the survivor key so
        // distinct Macs are summed rather than one newest Mac masking the
        // other's spend.
        var survivors: [String: DailyCostPoint] = [:]
        for row in rows {
            let accountKey = "\(row.providerID)|\(row.accountEmail ?? "_")|\(row.dayKey)"
            let key = Self.localCostProviders.contains(row.providerID)
                ? "\(row.deviceID)|\(accountKey)"
                : accountKey
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
            let costIsKnown = Self.costIsKnown(from: survivor.sourceRevisionKey) != false
            let dayEvidence = Self.dayEvidence(from: survivor.sourceRevisionKey)
            let rollupKey = "\(survivor.providerID)|\(survivor.accountEmail ?? "_")"
            var acc = perProvider[rollupKey] ?? ProviderAccumulator(
                providerID: survivor.providerID,
                accountEmail: survivor.accountEmail,
                isLocalCostProvider: Self.localCostProviders.contains(survivor.providerID),
                expectedContributorDeviceIDs: expectedLocalContributorDeviceIDsByProviderKey[rollupKey] ?? [])
            acc.ingest(
                survivor,
                costIsKnown: costIsKnown,
                dayEvidence: dayEvidence,
                decoder: decoder)
            perProvider[rollupKey] = acc

            perDay[survivor.dayKey, default: .init()].ingest(
                survivor,
                costIsKnown: costIsKnown)
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
                    isEstimated: nil,
                    costIsKnown: acc.costIsKnown)
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
            modelBreakdowns: [],
            incompleteDayEvidenceDayKeys: [],
            dayEvidenceVerifiedAt: [:])
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
                    // Preserve the same point-first fallback used by live
                    // snapshots when seeding previously synced summaries.
                    costIsKnown: point.costIsKnown ?? summary.costIsKnown,
                    isEstimated: point.isEstimated,
                    modelBreakdowns: point.modelBreakdowns,
                    serviceBreakdowns: point.serviceBreakdowns,
                    lastUpdated: summary.costUpdatedAt ?? row.lastUpdated,
                    totalUpdatedAt: summary.totalCostUpdatedAt,
                    sourceRevisionKey: Self.ledgerSourceRevisionKey(
                        summary,
                        providerLastUpdated: row.lastUpdated),
                    historyCoverageIsEstablished: summary.historyCoverageIsEstablished,
                    historySinceDayKey: summary.historySinceDayKey,
                    historyUntilDayKey: summary.historyUntilDayKey,
                    dayEvidence: point.dayEvidence,
                    encoder: encoder,
                    in: context)
            }
        }
        try context.save()
    }

    // MARK: - Helpers

    /// Carries ledger rows written before the Mac knew the provider email
    /// into the email-keyed row used by newer snapshots. SnapshotCache does
    /// the same reconciliation for the live view; doing the lightweight
    /// identity migration here keeps the persisted Cost Window Ledger from
    /// retaining a second, hidden copy of the established history.
    private static func migrateNilEmailRowsIfNeeded(
        provider: ProviderUsageSnapshot,
        deviceID: String,
        in context: ModelContext) throws
    {
        guard let email = provider.accountEmail,
              !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let providerID = provider.providerID
        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate { row in
                row.deviceID == deviceID && row.providerID == providerID
            })
        let legacyRows = try context.fetch(descriptor).filter {
            $0.accountEmail == nil
                || $0.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        }
        guard !legacyRows.isEmpty else { return }

        for legacy in legacyRows {
            let targetKey = DailyCostPoint.makeCompositeKey(
                deviceID: deviceID,
                providerID: providerID,
                accountEmail: email,
                dayKey: legacy.dayKey)
            let targetDescriptor = FetchDescriptor<DailyCostPoint>(
                predicate: #Predicate { $0.compositeKey == targetKey })
            if let target = try context.fetch(targetDescriptor).first {
                let legacyEvidence = Self.dayEvidence(from: legacy.sourceRevisionKey)
                let targetEvidence = Self.dayEvidence(from: target.sourceRevisionKey)
                let hasDayEvidence = legacyEvidence != nil || targetEvidence != nil
                if Self.ledgerRow(legacy, isStrongerThan: target) {
                    target.costUSD = legacy.costUSD
                    target.totalTokens = legacy.totalTokens
                    target.isEstimated = legacy.isEstimated
                    target.modelBreakdownsData = legacy.modelBreakdownsData
                    target.serviceBreakdownsData = legacy.serviceBreakdownsData
                    target.totalUpdatedAt = legacy.totalUpdatedAt
                    target.lastUpdated = legacy.lastUpdated
                    target.sourceRevisionKey = legacy.sourceRevisionKey
                }
                if !hasDayEvidence {
                    target.totalTokens = max(target.totalTokens, legacy.totalTokens)
                    target.lastUpdated = max(target.lastUpdated, legacy.lastUpdated)
                }
                context.delete(legacy)
            } else {
                legacy.accountEmail = email
                legacy.compositeKey = targetKey
            }
        }
    }

    /// Selects the row with the strongest proof, not merely the newest
    /// identity spelling. Established history outranks legacy history, which
    /// outranks partial history; known pricing then outranks unknown pricing.
    /// Revision timestamps break ties within the same proof class.
    private static func ledgerRow(
        _ candidate: DailyCostPoint,
        isStrongerThan existing: DailyCostPoint) -> Bool
    {
        let candidateEvidence = Self.dayEvidence(from: candidate.sourceRevisionKey)
        let existingEvidence = Self.dayEvidence(from: existing.sourceRevisionKey)
        if candidateEvidence != nil || existingEvidence != nil {
            guard let candidateEvidence else { return false }
            guard let existingEvidence else { return true }
            // Identity migration cannot establish a changed source lineage:
            // it has no enclosing fresh-complete window to bound that change.
            // Comparable proof revisions remain directly orderable.
            return Self.hasSameEvidenceContext(candidateEvidence, existingEvidence)
                && candidateEvidence.revision > existingEvidence.revision
        }

        func coverageRank(_ row: DailyCostPoint) -> Int {
            switch Self.historyCoverage(from: row.sourceRevisionKey) {
            case true: 2
            case nil: 1
            case false: 0
            }
        }

        let candidateCoverage = coverageRank(candidate)
        let existingCoverage = coverageRank(existing)
        if candidateCoverage != existingCoverage {
            return candidateCoverage > existingCoverage
        }

        let candidateKnown = Self.costIsKnown(from: candidate.sourceRevisionKey) != false
        let existingKnown = Self.costIsKnown(from: existing.sourceRevisionKey) != false
        if candidateKnown != existingKnown {
            return candidateKnown
        }

        let candidateTotalRevision = candidate.totalUpdatedAt ?? candidate.lastUpdated
        let existingTotalRevision = existing.totalUpdatedAt ?? existing.lastUpdated
        if candidateTotalRevision != existingTotalRevision {
            return candidateTotalRevision > existingTotalRevision
        }
        return candidate.lastUpdated > existing.lastUpdated
    }

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
        for row in existingRows where !incomingDayKeys.contains(row.dayKey)
            && Self.dayEvidence(from: row.sourceRevisionKey) == nil
        {
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
        let revisionKey = summary.mobileRevisionKey(
            providerLastUpdated: providerLastUpdated,
            includeDayEvidence: false)
        return "\(revisionKey)|historyCoverage=\(coverage)"
    }

    private static let dayEvidenceMarkerPrefix = "dayEvidence=v1:"

    /// Replaces a day proof in the existing optional revision string. The
    /// marker is versioned and Base64URL-encoded canonical JSON, so arbitrary
    /// source IDs cannot collide with its `|`-delimited siblings.
    private static func withDayEvidence(
        _ revisionKey: String?,
        evidence: SyncDayEvidence?) -> String?
    {
        let existing = revisionKey?
            .split(separator: "|", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("dayEvidence=v") }
            .joined(separator: "|")
        guard let evidence, evidence.isValid else { return existing }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(evidence) else { return existing }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(existing ?? "")|\(Self.dayEvidenceMarkerPrefix)\(encoded)"
    }

    private static func dayEvidence(from revisionKey: String?) -> SyncDayEvidence? {
        guard let marker = revisionKey?
            .split(separator: "|", omittingEmptySubsequences: false)
            .last(where: { $0.hasPrefix(Self.dayEvidenceMarkerPrefix) })
        else { return nil }
        let encoded = marker.dropFirst(Self.dayEvidenceMarkerPrefix.count)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = String(encoded) + String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: padded) else { return nil }
        guard let evidence = try? JSONDecoder().decode(SyncDayEvidence.self, from: data),
              evidence.isValid
        else {
            return nil
        }
        return evidence
    }

    private static func hasSameEvidenceContext(
        _ lhs: SyncDayEvidence,
        _ rhs: SyncDayEvidence) -> Bool
    {
        lhs.sourceKind == rhs.sourceKind
            && lhs.scopeID == rhs.scopeID
            && lhs.lineageID == rhs.lineageID
    }

    /// Mirrors SyncCostSummary's daily adoption rules for a persisted row.
    /// Matching proofs use their monotonic revision. A different source
    /// context requires a fresh complete baseline whose explicit bounds
    /// include this day and whose aggregate revision is current.
    private enum DayEvidenceUpdateDecision {
        case reject
        case refreshFreshness
        case replaceValues
    }

    private static func dayEvidenceUpdateDecision(
        _ incoming: SyncDayEvidence,
        existing: SyncDayEvidence?,
        dayKey: String,
        historyCoverageIsEstablished: Bool?,
        historySinceDayKey: String?,
        historyUntilDayKey: String?,
        incomingTotalRevision: Date,
        existingTotalRevision: Date) -> DayEvidenceUpdateDecision
    {
        guard incoming.isValid else { return .reject }
        guard let existing else {
            // First proof must be at least as fresh as the retained spend
            // row. A fresh quota refresh cannot make old day evidence current.
            return incoming.verifiedAt >= existingTotalRevision ? .replaceValues : .reject
        }
        guard existing.isValid else { return .reject }
        if Self.hasSameEvidenceContext(incoming, existing) {
            if incoming.revision > existing.revision {
                return .replaceValues
            }
            if incoming.revision == existing.revision, incoming.verifiedAt > existing.verifiedAt {
                return .refreshFreshness
            }
            return .reject
        }
        let canAdoptContext = historyCoverageIsEstablished == true
            && incomingTotalRevision >= existingTotalRevision
            && incoming.verifiedAt >= existing.verifiedAt
            && Self.isWithinBounds(
                dayKey,
                since: historySinceDayKey,
                until: historyUntilDayKey)
        return canAdoptContext ? .replaceValues : .reject
    }

    private static func isWithinBounds(
        _ dayKey: String,
        since: String?,
        until: String?) -> Bool
    {
        guard let since, let until, since <= until else { return false }
        return since <= dayKey && dayKey <= until
    }

    private static func replaceDay(
        _ row: DailyCostPoint,
        costUSD: Double,
        totalTokens: Int,
        isEstimated: Bool?,
        modelData: Data?,
        serviceData: Data?,
        lastUpdated: Date,
        totalUpdatedAt: Date,
        sourceRevisionKey: String?)
    {
        row.costUSD = costUSD
        row.totalTokens = totalTokens
        row.isEstimated = isEstimated
        row.modelBreakdownsData = modelData
        row.serviceBreakdownsData = serviceData
        row.lastUpdated = max(row.lastUpdated, lastUpdated)
        row.totalUpdatedAt = max(row.totalUpdatedAt ?? row.lastUpdated, totalUpdatedAt)
        row.sourceRevisionKey = sourceRevisionKey
    }

    private static func withCostKnown(_ revisionKey: String?, known: Bool) -> String? {
        guard let revisionKey else {
            return known ? "costKnown=known" : "costKnown=unknown"
        }
        let withoutMarker = revisionKey
            .split(separator: "|", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("costKnown=") }
            .joined(separator: "|")
        return "\(withoutMarker)|costKnown=\(known ? "known" : "unknown")"
    }

    private static func costIsKnown(from revisionKey: String?) -> Bool? {
        guard let revisionKey,
              let marker = revisionKey.split(separator: "|").last(where: {
                  $0.hasPrefix("costKnown=")
              })
        else {
            // Rows written before the marker was introduced contain numeric
            // cost and are therefore treated as known for compatibility.
            return nil
        }
        return marker.dropFirst("costKnown=".count) == "known"
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
        var costIsKnown = true
        mutating func ingest(_ row: DailyCostPoint, costIsKnown: Bool) {
            self.costUSD += row.costUSD
            if !costIsKnown {
                self.costIsKnown = false
            }
            self.totalTokens += row.totalTokens
        }
    }

    private struct ProviderAccumulator {
        let providerID: String
        let accountEmail: String?
        var costUSD: Double = 0
        var totalTokens: Int = 0
        var perDay: [String: (cost: Double, tokens: Int, costIsKnown: Bool)] = [:]
        var perModel: [String: Double] = [:]
        private var dayContributorCount: [String: Int] = [:]
        private var proofedContributorCount: [String: Int] = [:]
        private var earliestVerifiedAt: [String: Date] = [:]
        private var singleContributorEvidence: [String: SyncDayEvidence] = [:]
        private var dayProofedDeviceIDs: [String: Set<String>] = [:]
        private let isLocalCostProvider: Bool
        private var contributingDeviceIDs: Set<String> = []
        private var dayContributorDeviceIDs: [String: Set<String>] = [:]
        private let expectedContributorDeviceIDs: Set<String>

        init(
            providerID: String,
            accountEmail: String?,
            isLocalCostProvider: Bool,
            expectedContributorDeviceIDs: Set<String>)
        {
            self.providerID = providerID
            self.accountEmail = accountEmail
            self.isLocalCostProvider = isLocalCostProvider
            self.expectedContributorDeviceIDs = expectedContributorDeviceIDs
        }

        mutating func ingest(
            _ row: DailyCostPoint,
            costIsKnown: Bool,
            dayEvidence: SyncDayEvidence?,
            decoder: JSONDecoder)
        {
            self.costUSD += row.costUSD
            self.totalTokens += row.totalTokens
            self.contributingDeviceIDs.insert(row.deviceID)
            self.dayContributorDeviceIDs[row.dayKey, default: []].insert(row.deviceID)
            if self.perDay[row.dayKey] == nil {
                self.perDay[row.dayKey] = (0, 0, true)
            }
            self.perDay[row.dayKey]?.cost += row.costUSD
            if !costIsKnown {
                self.perDay[row.dayKey]?.costIsKnown = false
            }
            self.perDay[row.dayKey, default: (0, 0, true)].tokens += row.totalTokens
            let contributorCount = self.dayContributorCount[row.dayKey, default: 0] + 1
            self.dayContributorCount[row.dayKey] = contributorCount
            if let dayEvidence {
                self.proofedContributorCount[row.dayKey, default: 0] += 1
                self.dayProofedDeviceIDs[row.dayKey, default: []].insert(row.deviceID)
                self.earliestVerifiedAt[row.dayKey] = min(
                    self.earliestVerifiedAt[row.dayKey] ?? dayEvidence.verifiedAt,
                    dayEvidence.verifiedAt)
                if contributorCount == 1 {
                    self.singleContributorEvidence[row.dayKey] = dayEvidence
                } else {
                    self.singleContributorEvidence.removeValue(forKey: row.dayKey)
                }
            } else {
                self.singleContributorEvidence.removeValue(forKey: row.dayKey)
            }
            if let data = row.modelBreakdownsData,
               let decoded = try? decoder.decode([SyncCostBreakdown].self, from: data)
            {
                for breakdown in decoded where breakdown.costUSD > 0 {
                    self.perModel[breakdown.label, default: 0] += breakdown.costUSD
                }
            }
        }

        func toRollup() -> CostLedgerProviderRollup {
            let allContributorDeviceIDs = self.isLocalCostProvider
                ? self.contributingDeviceIDs.union(self.expectedContributorDeviceIDs)
                : self.contributingDeviceIDs
            let requiresDayProof = self.dayProofedDeviceIDs.values.contains { !$0.isEmpty }
            let incompleteDayEvidenceDayKeys = Set(self.dayContributorCount.compactMap { day, count -> String? in
                guard self.isLocalCostProvider, requiresDayProof else { return nil }
                let proofedIDs = self.dayProofedDeviceIDs[day] ?? []
                let rowIDs = self.dayContributorDeviceIDs[day] ?? []
                guard proofedIDs == allContributorDeviceIDs, rowIDs == allContributorDeviceIDs,
                      self.proofedContributorCount[day] == count
                else { return day }
                return nil
            })
            return CostLedgerProviderRollup(
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
                            isEstimated: nil,
                            costIsKnown: vals.costIsKnown,
                            dayEvidence: self.isLocalCostProvider && allContributorDeviceIDs.count > 1
                                ? nil
                                : self.singleContributorEvidence[day])
                    },
                modelBreakdowns: self.perModel
                    .map { SyncCostBreakdown(label: $0.key, costUSD: $0.value) }
                    .sorted { $0.costUSD > $1.costUSD },
                incompleteDayEvidenceDayKeys: incompleteDayEvidenceDayKeys,
                dayEvidenceVerifiedAt: Dictionary(
                    uniqueKeysWithValues: self.dayContributorCount.compactMap { day, count in
                        guard self.proofedContributorCount[day] == count,
                              let verifiedAt = self.earliestVerifiedAt[day]
                        else { return nil }
                        if self.isLocalCostProvider,
                           self.dayProofedDeviceIDs[day] != allContributorDeviceIDs
                        {
                            // A missing per-device day is an unknown contribution,
                            // not a verified zero. Keep aggregate Today stale until
                            // every local contributor has proof for the day.
                            return nil
                        }
                        return (day, verifiedAt)
                    }))
        }
    }
}
