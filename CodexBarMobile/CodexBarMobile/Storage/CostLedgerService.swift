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

enum CostLedgerService {

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
        deviceID: String,
        providerID: String,
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
}
