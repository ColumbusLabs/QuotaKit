import CodexBarCore
import CodexBarSync
import Foundation
import Observation

/// Observes `UsageStore` changes and pushes usage snapshots to iCloud via `CloudSyncManager`.
///
/// This class bridges the existing Mac app data to the shared iCloud layer without
/// modifying any existing source files. It uses Swift Observation to track `UsageStore.snapshots`.
@MainActor
@Observable
final class SyncCoordinator {
    private let store: UsageStore
    private let settings: SettingsStore
    private let syncManager: any SyncPushing
    private var isObserving = false

    // Observable sync status for UI
    private(set) var lastSyncTime: Date?
    private(set) var lastSyncSucceeded: Bool = true
    private(set) var lastSyncMessage: String?
    private(set) var isSyncing: Bool = false

    /// Stable device UUID for this Mac, persisted across app launches.
    private let deviceID: String

    /// Per-provider content-hash cache (P4). Keyed by composite
    /// `providerID|accountEmail`, value is a stable hash of the provider's
    /// encoded JSON. Used to diff incoming pushes so `pushPerProviderRecords`
    /// only uploads providers whose data actually changed.
    ///
    /// In-memory only — rebuilt on every process launch. The cost of
    /// rebuilding is one extra full upload on Mac startup, which is fine; the
    /// alternative (persisting to UserDefaults) risks the cache drifting out of
    /// sync with what's actually on CloudKit.
    private var lastProviderHashes: [String: Int] = [:]

    /// Composite recordNames pushed to `DeviceProvidersZone` last cycle.
    /// Used to detect provider-disable transitions and account-identity
    /// drift: anything in `lastPushedRecordNames` that is NOT in this
    /// cycle's set of pushed composites must be deleted from CloudKit so
    /// stale records don't accumulate.
    ///
    /// L1 ghost-records cleanup — closes the user-reported iOS-1.3.0 bug
    /// at the data layer. iOS 1.3.1's `dropOrphansAndStale` filter (Build
    /// 94) is the L2 backup that hides any ghost that does slip through.
    ///
    /// In-memory only, like `lastProviderHashes`. On Mac process restart,
    /// this set is empty: the first push cycle re-establishes the
    /// "current" composites without producing spurious deletes (we don't
    /// emit deletes on the first cycle because we don't know yet what
    /// was previously there). Subsequent cycles compare reliably.
    private var lastPushedRecordNames: Set<String> = []

    /// Tracks whether `lastPushedRecordNames` has been seeded by at least
    /// one successful push. Until that's true, we don't emit deletes —
    /// otherwise the first cycle after Mac restart would interpret the
    /// empty set as "nothing was previously enabled" and skip deletion.
    /// After the first successful push, real disabled-or-drifted
    /// composites can be detected.
    private var pushHistorySeeded: Bool = false

    /// Stable encoder used for the per-provider diff. Sorted keys so byte-level
    /// hashing is insensitive to encoding key order. Built on top of the
    /// project-wide factory so date strategy stays consistent.
    private let providerDiffEncoder: JSONEncoder = {
        let e = CloudSyncConstants.makeJSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    init(store: UsageStore, settings: SettingsStore, syncManager: any SyncPushing = CloudSyncManager.shared) {
        self.store = store
        self.settings = settings
        self.syncManager = syncManager
        self.deviceID = Self.stableDeviceID()
    }

    /// Starts observing `UsageStore` snapshot changes.
    /// Each time the snapshots dictionary changes, a new `SyncedUsageSnapshot` is pushed to iCloud.
    func startObserving() {
        guard !self.isObserving else { return }
        self.isObserving = true
        self.observeLoop()
    }

    private func observeLoop() {
        withObservationTracking {
            _ = self.store.snapshots
            _ = self.store.errors
            _ = self.store.tokenSnapshots
            _ = self.settings.iCloudSyncEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isObserving else { return }
                await self.pushCurrentSnapshot()
                self.observeLoop()
            }
        }
    }

    /// Builds and pushes the current state to iCloud.
    func pushCurrentSnapshot() async {
        guard self.settings.iCloudSyncEnabled else { return }

        let enabledProviders = self.store.enabledProviders()
        guard !enabledProviders.isEmpty else { return }

        self.isSyncing = true
        defer { self.isSyncing = false }

        var providerSnapshots: [ProviderUsageSnapshot] = []

        for provider in enabledProviders {
            let snapshot = self.store.snapshots[provider]
            let error = self.store.errors[provider]
            let meta = self.store.providerMetadata[provider]

            // Build dynamic rate windows array with labels from metadata
            var rateWindows: [SyncRateWindow] = []
            if let p = snapshot?.primary {
                rateWindows.append(SyncRateWindow(
                    label: meta?.sessionLabel,
                    usedPercent: p.usedPercent,
                    windowMinutes: p.windowMinutes,
                    resetsAt: p.resetsAt,
                    resetDescription: p.resetDescription))
            }
            if let s = snapshot?.secondary {
                rateWindows.append(SyncRateWindow(
                    label: meta?.weeklyLabel,
                    usedPercent: s.usedPercent,
                    windowMinutes: s.windowMinutes,
                    resetsAt: s.resetsAt,
                    resetDescription: s.resetDescription))
            }
            if let meta, meta.supportsOpus, let t = snapshot?.tertiary {
                rateWindows.append(SyncRateWindow(
                    label: meta.opusLabel ?? "Sonnet",
                    usedPercent: t.usedPercent,
                    windowMinutes: t.windowMinutes,
                    resetsAt: t.resetsAt,
                    resetDescription: t.resetDescription))
            }
            // Extra (named) rate windows from upstream — Claude exposes
            // Designs / Daily Routines / Web Sonnet here in v0.23, Cursor
            // exposes its on-demand "Extra usage" metric. Append after
            // primary/secondary/tertiary so iOS rendering preserves
            // semantic ordering. iOS 1.3.x reads `rateWindows: [SyncRateWindow]`
            // unchanged; clients that haven't been updated to render the
            // extras still see primary/secondary/tertiary as the first
            // 3 entries.
            for extra in snapshot?.extraRateWindows ?? [] {
                rateWindows.append(SyncRateWindow(
                    label: extra.title,
                    usedPercent: extra.window.usedPercent,
                    windowMinutes: extra.window.windowMinutes,
                    resetsAt: extra.window.resetsAt,
                    resetDescription: extra.window.resetDescription))
            }

            // Legacy primary/secondary for backward compat with older iOS builds
            let primaryWindow = rateWindows.first
            let secondaryWindow = rateWindows.count > 1 ? rateWindows[1] : nil

            // Map token/cost snapshot
            let costSummary = self.makeCostSummary(for: provider)

            // Map provider budget/spend
            let providerCost = snapshot?.providerCost
            let budgetSnap: SyncBudgetSnapshot? = providerCost.map { pc in
                SyncBudgetSnapshot(
                    usedAmount: pc.used,
                    limitAmount: pc.limit,
                    currencyCode: pc.currencyCode,
                    period: pc.period,
                    resetsAt: pc.resetsAt)
            }

            // Map utilization history
            let utilizationHistory = self.makeUtilizationHistory(for: provider)
            if let uh = utilizationHistory {
                let totalEntries = uh.reduce(0) { $0 + $1.entries.count }
                print("[CodexBar Sync] \(provider.rawValue): \(uh.count) utilization series, \(totalEntries) entries")
            } else {
                print("[CodexBar Sync] \(provider.rawValue): no utilization history")
            }

            // Map Perplexity's rich structured credit breakdown (recurring /
            // promo / purchased pools, Pro/Max plan, renewal date) into
            // `SyncPerplexityCreditSummary` so iOS 1.3.0 can render the
            // stacked 3-segment card. Only populated for Perplexity —
            // stays nil for every other provider. Upstream publishes zero
            // values for empty pools; we map those to nil so iOS can
            // distinguish "no pool" from "empty pool" and hide the
            // no-pool segment entirely.
            let perplexityCredits: SyncPerplexityCreditSummary? = {
                guard provider == .perplexity,
                      let p = snapshot?.perplexityUsage
                else { return nil }
                return SyncPerplexityCreditSummary(
                    recurringTotalCents: p.recurringTotal > 0 ? p.recurringTotal : nil,
                    recurringUsedCents: p.recurringTotal > 0 ? p.recurringUsed : nil,
                    promoTotalCents: p.promoTotal > 0 ? p.promoTotal : nil,
                    promoUsedCents: p.promoTotal > 0 ? p.promoUsed : nil,
                    promoExpiresAt: p.promoExpiration,
                    purchasedTotalCents: p.purchasedTotal > 0 ? p.purchasedTotal : nil,
                    purchasedUsedCents: p.purchasedTotal > 0 ? p.purchasedUsed : nil,
                    renewalAt: p.renewalDate,
                    planName: p.planName,
                    balanceCents: p.balanceCents)
            }()

            let providerSnapshot = ProviderUsageSnapshot(
                providerID: provider.rawValue,
                providerName: meta?.displayName ?? provider.rawValue.capitalized,
                primary: primaryWindow,
                secondary: secondaryWindow,
                accountEmail: snapshot?.identity?.accountEmail,
                loginMethod: snapshot?.identity?.loginMethod,
                statusMessage: error,
                isError: error != nil,
                lastUpdated: snapshot?.updatedAt ?? Date(),
                costSummary: costSummary,
                budget: budgetSnap,
                rateWindows: rateWindows,
                utilizationHistory: utilizationHistory,
                perplexityCredits: perplexityCredits)

            providerSnapshots.append(providerSnapshot)
        }

        let deviceName = Host.current().localizedName ?? "Mac"
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let mobileVersion = Bundle.main.object(forInfoDictionaryKey: "CodexMobileVersion") as? String
        let synced = SyncedUsageSnapshot(
            providers: providerSnapshots,
            syncTimestamp: Date(),
            deviceName: deviceName,
            deviceID: self.deviceID,
            appVersion: appVersion,
            mobileVersion: mobileVersion)

        let result = await self.syncManager.pushSnapshot(synced)
        self.lastSyncTime = Date()
        self.lastSyncSucceeded = result.succeeded
        self.lastSyncMessage = result.message

        // P4: additive per-provider write to DeviceProvidersZone. Diff against
        // the in-memory hash cache so unchanged providers are skipped. Failure
        // here is logged but does NOT override `lastSyncSucceeded` — the
        // legacy-zone write is still authoritative while iOS readers haven't
        // migrated yet (see Research/010).
        let (envelopes, hashUpdates) = self.buildPerProviderDelta(
            from: providerSnapshots, synced: synced)
        if !envelopes.isEmpty {
            let perProviderResult =
                await self.syncManager.pushPerProviderRecords(envelopes)
            if perProviderResult.succeeded {
                for (key, hash) in hashUpdates {
                    self.lastProviderHashes[key] = hash
                }
            } else {
                print(
                    "[CodexBar Sync] per-provider write failed: " +
                        (perProviderResult.message ?? "unknown"))
            }
        }

        // L1 ghost-records cleanup. Compute the composites we just pushed
        // (i.e. all currently-enabled, non-ghost providers regardless of
        // whether their hash changed this cycle) vs the composites we
        // pushed last cycle. The difference represents:
        //   (a) providers the user disabled — Mac stopped including them
        //   (b) accounts whose identity drifted (composite key changed)
        // We emit deletes for those CKRecords so iOS sees a clean zone.
        // First-cycle-after-restart guard: don't emit deletes until
        // `pushHistorySeeded == true`; otherwise we'd interpret the empty
        // initial set as "nothing was enabled" and miss real disable events
        // that happened before this Mac session started — but more
        // importantly we'd issue spurious deletes for anything iOS already
        // sees from previous Mac sessions, since we don't yet know what
        // composites are truly current.
        let currentRecordNames = self.computeCurrentRecordNames(
            from: providerSnapshots)
        if self.pushHistorySeeded {
            let staleRecordNames = self.lastPushedRecordNames
                .subtracting(currentRecordNames)
            if !staleRecordNames.isEmpty {
                let deleteResult = await self.syncManager
                    .deletePerProviderRecords(recordNames: Array(staleRecordNames))
                if deleteResult.succeeded {
                    print(
                        "[CodexBar Sync] cleaned up \(staleRecordNames.count)" +
                            " stale per-provider record(s) from CloudKit")
                } else {
                    print(
                        "[CodexBar Sync] per-provider delete failed: " +
                            (deleteResult.message ?? "unknown"))
                    // Don't update lastPushedRecordNames if delete failed —
                    // retry next cycle.
                    return
                }
            }
        }
        self.lastPushedRecordNames = currentRecordNames
        self.pushHistorySeeded = true
    }

    /// All composite recordNames the current snapshot list will push. Used
    /// to compute the disabled/identity-drifted set against
    /// `lastPushedRecordNames`.
    private func computeCurrentRecordNames(
        from providerSnapshots: [ProviderUsageSnapshot]) -> Set<String>
    {
        var result: Set<String> = []
        for provider in providerSnapshots where !Self.isGhostProvider(provider) {
            result.insert(CloudSyncManager.perProviderRecordName(
                deviceID: self.deviceID,
                providerID: provider.providerID,
                accountEmail: provider.accountEmail))
        }
        return result
    }

    /// Produces the envelopes that should be uploaded this cycle plus the
    /// hash-cache updates to apply on success. Pure function over
    /// `providerSnapshots` and the in-memory hash state.
    ///
    /// Ghost providers (no rate / cost / budget / error / status and no
    /// accountEmail) are filtered here — Mac may build them during early
    /// startup before OAuth / cookies have loaded. Writing them to
    /// `DeviceProvidersZone` would produce a CKRecord keyed by
    /// `{deviceID}|{providerID}|_` which is NEVER overwritten by the later
    /// real push (that one goes to `...|user@...` — different recordName),
    /// leaving stale empty records on the server. iOS 1.3.0 has a defensive
    /// filter too, but skipping here is the root-cause fix.
    private func buildPerProviderDelta(
        from providerSnapshots: [ProviderUsageSnapshot],
        synced: SyncedUsageSnapshot) -> (envelopes: [ProviderUsageEnvelope], hashUpdates: [String: Int])
    {
        var envelopes: [ProviderUsageEnvelope] = []
        var updates: [String: Int] = [:]

        for provider in providerSnapshots {
            // Skip "ghost" providers — see doc comment.
            if Self.isGhostProvider(provider) {
                continue
            }
            let key = Self.perProviderHashKey(
                providerID: provider.providerID,
                accountEmail: provider.accountEmail)
            guard let data = try? providerDiffEncoder.encode(provider) else {
                // Encode fallback: include anyway so we don't silently drop a
                // provider just because its JSON encoding briefly failed.
                envelopes.append(ProviderUsageEnvelope(
                    deviceID: self.deviceID,
                    deviceName: synced.deviceName,
                    appVersion: synced.appVersion,
                    mobileVersion: synced.mobileVersion,
                    syncTimestamp: synced.syncTimestamp,
                    notificationPushEnabled: synced.notificationPushEnabled,
                    provider: provider))
                continue
            }
            let hash = Self.stableHash(for: data)
            if self.lastProviderHashes[key] == hash {
                continue // unchanged — skip
            }
            envelopes.append(ProviderUsageEnvelope(
                deviceID: self.deviceID,
                deviceName: synced.deviceName,
                appVersion: synced.appVersion,
                mobileVersion: synced.mobileVersion,
                syncTimestamp: synced.syncTimestamp,
                notificationPushEnabled: synced.notificationPushEnabled,
                provider: provider))
            updates[key] = hash
        }
        return (envelopes, updates)
    }

    /// Matches `SnapshotCache.isGhost` on the iOS side: a provider with NO
    /// usable signal in any field. Mac filter prevents ghost records from
    /// being created in `DeviceProvidersZone` in the first place.
    private static func isGhostProvider(_ provider: ProviderUsageSnapshot) -> Bool {
        provider.primary == nil
            && provider.secondary == nil
            && provider.rateWindows.isEmpty
            && provider.costSummary == nil
            && provider.budget == nil
            && !provider.isError
            && provider.statusMessage == nil
    }

    /// Key used by the in-memory diff cache — same (providerID, accountEmail)
    /// composite as `CloudSyncManager.perProviderRecordName`, but local-only
    /// (never serialized to CloudKit). The `"_"` sentinel for nil
    /// `accountEmail` **must match 4 peer sites byte-for-byte**:
    /// `CloudSyncManager.perProviderRecordName` (record name on CloudKit),
    /// iOS `SnapshotCache.compositeKey`, iOS
    /// `ProviderSnapshotModel.makeCompositeKey`, and any delete-by-
    /// recordName parser. Build 67 drift discovery: an earlier build
    /// used `""` at one of those four sites, silently breaking delete
    /// cascades. If you change the sentinel, change **all four sites**
    /// in the same commit.
    private static func perProviderHashKey(providerID: String, accountEmail: String?) -> String {
        "\(providerID)|\(accountEmail ?? "_")"
    }

    /// Deterministic hash of a provider's encoded JSON. Uses FNV-1a (64-bit)
    /// so it's cheap, stable across process launches, and collision-free in
    /// the range we care about (≤100 providers × app lifetime).
    ///
    /// `0xCBF2_9CE4_8422_2325` is the canonical FNV-1a **64-bit offset
    /// basis**; `0x100_0000_01B3` is the canonical **64-bit FNV prime**.
    /// These two values are the FNV-1a standard and must not be changed —
    /// altering them would invalidate every cached provider hash and force
    /// a full re-upload from every user's Mac on next startup (the diff
    /// cache would see every provider as "changed" because the new hash
    /// wouldn't match the cached old one).
    private static func stableHash(for data: Data) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }

    func stopObserving() {
        self.isObserving = false
    }

    private func makeCostSummary(for provider: UsageProvider) -> SyncCostSummary? {
        let tokenSnapshot = self.store.tokenSnapshots[provider]
        let serviceBreakdownsByDay = self.dashboardServiceBreakdowns(for: provider)

        guard tokenSnapshot != nil || !serviceBreakdownsByDay.isEmpty else { return nil }

        let tokenEntriesByDay = Dictionary(
            uniqueKeysWithValues: (tokenSnapshot?.daily ?? []).map { ($0.date, $0) })
        let allDayKeys = Set(tokenEntriesByDay.keys).union(serviceBreakdownsByDay.keys).sorted()
        let daily = allDayKeys.map { dayKey -> SyncDailyPoint in
            let entry = tokenEntriesByDay[dayKey]
            let modelBreakdowns = self.modelBreakdowns(from: entry, provider: provider)
            let serviceBreakdowns = serviceBreakdownsByDay[dayKey] ?? []

            let fallbackCost =
                entry?.costUSD
                    ?? self.breakdownTotal(modelBreakdowns)
                    ?? self.breakdownTotal(serviceBreakdowns)
                    ?? 0

            // Day is estimated iff any of its model breakdowns is. Service
            // breakdowns never go through the fallback resolver (they come
            // from the upstream API directly), so they're excluded from the
            // OR aggregation.
            let dayIsEstimated = modelBreakdowns.contains(where: { $0.isEstimated == true })
            return SyncDailyPoint(
                dayKey: dayKey,
                costUSD: fallbackCost,
                totalTokens: entry?.totalTokens ?? 0,
                modelBreakdowns: modelBreakdowns,
                serviceBreakdowns: serviceBreakdowns,
                isEstimated: dayIsEstimated ? true : nil)
        }

        let totalDailyCost = daily.reduce(0) { $0 + $1.costUSD }
        let summaryIsEstimated = daily.contains(where: { $0.isEstimated == true })

        return SyncCostSummary(
            sessionCostUSD: tokenSnapshot?.sessionCostUSD,
            sessionTokens: tokenSnapshot?.sessionTokens,
            last30DaysCostUSD: tokenSnapshot?.last30DaysCostUSD ?? (daily.isEmpty ? nil : totalDailyCost),
            last30DaysTokens: tokenSnapshot?.last30DaysTokens,
            daily: daily,
            isEstimated: summaryIsEstimated ? true : nil)
    }

    private func modelBreakdowns(
        from entry: CostUsageDailyReport.Entry?,
        provider: UsageProvider) -> [SyncCostBreakdown]
    {
        guard let breakdowns = entry?.modelBreakdowns else { return [] }
        return breakdowns
            .compactMap { breakdown in
                guard let cost = breakdown.costUSD, cost > 0 else { return nil }
                let estimated = Self.isModelEstimated(modelName: breakdown.modelName, provider: provider)
                return SyncCostBreakdown(
                    label: breakdown.modelName,
                    costUSD: cost,
                    isEstimated: estimated ? true : nil)
            }
            .sorted { lhs, rhs in
                if lhs.costUSD == rhs.costUSD {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.costUSD > rhs.costUSD
            }
    }

    /// `true` when `modelName` is NOT in the local pricing table for its
    /// provider — meaning the cost was computed via a fallback resolver
    /// row. Used to flag `isEstimated` on the outbound `SyncCostBreakdown`
    /// so iOS can render the estimated badge (P5).
    private static func isModelEstimated(modelName: String, provider: UsageProvider) -> Bool {
        switch provider {
        case .claude, .vertexai:
            !ModelFallbackPricing.isClaudeModelKnown(modelName)
        case .codex:
            !ModelFallbackPricing.isCodexModelKnown(modelName)
        case .zai, .gemini, .antigravity, .cursor, .opencode, .opencodego, .alibaba, .factory, .copilot,
             .minimax, .kilo, .kiro, .kimi, .kimik2, .augment, .jetbrains, .amp, .ollama, .synthetic,
             .openrouter, .warp, .perplexity, .abacus, .mistral:
            // These providers never reach the local pricing table — their
            // costs come pre-computed from upstream APIs (or don't exist).
            // No fallback applies, so they are never "estimated".
            false
        }
    }

    private func dashboardServiceBreakdowns(for provider: UsageProvider) -> [String: [SyncCostBreakdown]] {
        guard provider == .codex else { return [:] }
        guard let usageBreakdown = self.store.openAIDashboard?.usageBreakdown else { return [:] }

        return Dictionary(uniqueKeysWithValues: usageBreakdown.map { daily in
            let services = daily.services
                .filter { $0.creditsUsed > 0 }
                .map { service in
                    SyncCostBreakdown(
                        label: Self.displayServiceName(service.service),
                        costUSD: service.creditsUsed)
                }
                .sorted { lhs, rhs in
                    if lhs.costUSD == rhs.costUSD {
                        return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                    }
                    return lhs.costUSD > rhs.costUSD
                }
            return (daily.day, services)
        })
    }

    private func makeUtilizationHistory(for provider: UsageProvider) -> [SyncUtilizationSeries]? {
        let buckets = self.store.planUtilizationHistory[provider]
        guard let buckets, !buckets.isEmpty else { return nil }

        // Use preferred account or unscoped history
        let histories: [PlanUtilizationSeriesHistory]
        if let key = buckets.preferredAccountKey, let accountHistories = buckets.accounts[key],
           !accountHistories.isEmpty
        {
            histories = accountHistories
        } else if !buckets.unscoped.isEmpty {
            histories = buckets.unscoped
        } else if let mostRecent = buckets.accounts.values
            .filter({ !$0.isEmpty })
            .max(by: {
                ($0.compactMap(\.latestCapturedAt).max() ?? .distantPast) <
                    ($1.compactMap(\.latestCapturedAt).max() ?? .distantPast)
            })
        {
            histories = mostRecent
        } else {
            return nil
        }

        // Cap entries per series to keep CloudKit payload within CKRecord limits.
        // 730 hourly samples ≈ 1 month of data, ~70KB per series.
        let maxEntriesPerSeries = 730

        return histories.map { series in
            let capped = series.entries.suffix(maxEntriesPerSeries)
            return SyncUtilizationSeries(
                name: series.name.rawValue,
                windowMinutes: series.windowMinutes,
                entries: capped.map { entry in
                    SyncUtilizationEntry(
                        capturedAt: entry.capturedAt,
                        usedPercent: entry.usedPercent,
                        resetsAt: entry.resetsAt)
                })
        }
    }

    private func breakdownTotal(_ breakdowns: [SyncCostBreakdown]) -> Double? {
        guard !breakdowns.isEmpty else { return nil }
        return breakdowns.reduce(0) { $0 + $1.costUSD }
    }

    private static func displayServiceName(_ rawName: String) -> String {
        switch rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cli":
            "Codex Run"
        default:
            rawName
        }
    }

    /// Returns a stable UUID for this Mac, creating and persisting one if needed.
    private static func stableDeviceID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: CloudSyncConstants.deviceIDKey) {
            return existing
        }
        let newID = UUID().uuidString
        defaults.set(newID, forKey: CloudSyncConstants.deviceIDKey)
        return newID
    }
}
