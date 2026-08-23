import Foundation
import SwiftData

// MARK: - DailyCostPoint (Cost Window Ledger · research doc 024)

//
// Per-device, per-provider, per-day cost ledger entry. Together these rows
// form the iOS-side append + dedupe ledger that lets the Cost dashboard show
// longer windows than Mac's current `historyDays`. Round 1 / P1 introduces
// only the model + schema registration; writer (P2) / reader (P3) / UI (P4)
// come in later rounds. See `Research/024-cost-window-ledger/ARCHITECTURE.md`.
//
// Uniqueness: `compositeKey = "{deviceID}|{providerID}|{dayKey}"` — same
// `@Attribute(.unique)` pattern used by `ProviderSnapshotModel`. SwiftData
// has no native composite-unique; the three source fields stay first-class
// so `@Query` filters work without parsing.
//
// Lightweight migration: adding this entity to
// `CodexBarSwiftDataSchema.models` is handled by SwiftData automatically. Old
// stores without this table will be upgraded in place on first open (verified
// by `CWLMigrationTests` / T16). No `VersionedSchema` / `SchemaMigrationPlan`
// introduced this round — current `ModelContainerFactory` policy is
// "init-failure → delete + recreate" (it's a CloudKit cache, can be
// repopulated). Revisit once a real field-change migration is needed.

@Model
final class DailyCostPoint {
    /// Composite unique key `{deviceID}|{providerID}|{dayKey}`. The three
    /// source fields below are also stored directly for query-side filtering.
    /// **Format must stay byte-identical across writer / reader / tests** —
    /// drift here silently produces duplicate rows for the same logical day.
    @Attribute(.unique) var compositeKey: String

    var deviceID: String
    var providerID: String
    /// Account email (`nil` for single-account providers). Part of the
    /// composite key so multi-account providers (two Codex accounts on one
    /// Mac, etc.) keep separate per-day rows — matching the blob path's
    /// `ProviderSnapshotModel` per-(providerID, accountEmail) granularity.
    /// Without this, the two accounts collide on `(deviceID, providerID,
    /// dayKey)` and one silently overwrites the other.
    var accountEmail: String?
    /// `YYYY-MM-DD` UTC, matches `SyncDailyPoint.dayKey` on the wire.
    var dayKey: String

    var costUSD: Double
    var totalTokens: Int
    /// Mirrors `SyncCostBreakdown.isEstimated` rolled up to the day. Preserved
    /// so the iOS estimated-badge (P5) still works under CWL.
    var isEstimated: Bool?

    /// Encoded `[SyncCostBreakdown]` — preserves `isEstimated`,
    /// `standardCostUSD` / `priorityCostUSD` / `standardTokens` /
    /// `priorityTokens` (gap A Codex standard/fast split). Decoded on read.
    var modelBreakdownsData: Data?
    /// Encoded `[SyncCostBreakdown]` for service-level breakdowns. Decoded on read.
    var serviceBreakdownsData: Data?

    /// Payload revision: newest cost-bearing input included in this row.
    /// This can advance for breakdown-only dashboard data.
    var lastUpdated: Date
    /// Freshness of the source supplying `costUSD` and `totalTokens`. Optional
    /// so existing CWL stores lightweight-migrate; nil means `lastUpdated` for
    /// rows written before the split-freshness contract.
    var totalUpdatedAt: Date?
    /// Deterministic per-source revision vector. Optional for lightweight
    /// migration from rows written before independent source revisions.
    var sourceRevisionKey: String?

    init(
        deviceID: String,
        providerID: String,
        accountEmail: String?,
        dayKey: String,
        costUSD: Double,
        totalTokens: Int,
        isEstimated: Bool? = nil,
        modelBreakdownsData: Data? = nil,
        serviceBreakdownsData: Data? = nil,
        lastUpdated: Date,
        totalUpdatedAt: Date? = nil,
        sourceRevisionKey: String? = nil)
    {
        self.compositeKey = Self.makeCompositeKey(
            deviceID: deviceID,
            providerID: providerID,
            accountEmail: accountEmail,
            dayKey: dayKey)
        self.deviceID = deviceID
        self.providerID = providerID
        self.accountEmail = accountEmail
        self.dayKey = dayKey
        self.costUSD = costUSD
        self.totalTokens = totalTokens
        self.isEstimated = isEstimated
        self.modelBreakdownsData = modelBreakdownsData
        self.serviceBreakdownsData = serviceBreakdownsData
        self.lastUpdated = lastUpdated
        self.totalUpdatedAt = totalUpdatedAt
        self.sourceRevisionKey = sourceRevisionKey
    }

    /// Compose the composite unique key. Format pinned:
    /// `{deviceID}|{providerID}|{accountEmail ?? "_"}|{dayKey}`. The `"_"`
    /// for nil `accountEmail` matches `ProviderSnapshotModel.makeCompositeKey`
    /// byte-for-byte. Writer + reader + tests must all build it via this
    /// helper so any future format change propagates uniformly.
    static func makeCompositeKey(
        deviceID: String,
        providerID: String,
        accountEmail: String?,
        dayKey: String) -> String
    {
        "\(deviceID)|\(providerID)|\(accountEmail ?? "_")|\(dayKey)"
    }
}
