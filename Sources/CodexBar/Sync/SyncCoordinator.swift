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
                utilizationHistory: utilizationHistory)

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

    private static func perProviderHashKey(providerID: String, accountEmail: String?) -> String {
        "\(providerID)|\(accountEmail ?? "_")"
    }

    /// Deterministic hash of a provider's encoded JSON. Uses FNV-1a (64-bit)
    /// so it's cheap, stable across process launches, and collision-free in
    /// the range we care about (≤100 providers × app lifetime).
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
        let daily = allDayKeys.map { dayKey in
            let entry = tokenEntriesByDay[dayKey]
            let modelBreakdowns = self.modelBreakdowns(from: entry)
            let serviceBreakdowns = serviceBreakdownsByDay[dayKey] ?? []

            let fallbackCost =
                entry?.costUSD
                    ?? self.breakdownTotal(modelBreakdowns)
                    ?? self.breakdownTotal(serviceBreakdowns)
                    ?? 0

            return SyncDailyPoint(
                dayKey: dayKey,
                costUSD: fallbackCost,
                totalTokens: entry?.totalTokens ?? 0,
                modelBreakdowns: modelBreakdowns,
                serviceBreakdowns: serviceBreakdowns)
        }

        let totalDailyCost = daily.reduce(0) { $0 + $1.costUSD }

        return SyncCostSummary(
            sessionCostUSD: tokenSnapshot?.sessionCostUSD,
            sessionTokens: tokenSnapshot?.sessionTokens,
            last30DaysCostUSD: tokenSnapshot?.last30DaysCostUSD ?? (daily.isEmpty ? nil : totalDailyCost),
            last30DaysTokens: tokenSnapshot?.last30DaysTokens,
            daily: daily)
    }

    private func modelBreakdowns(from entry: CostUsageDailyReport.Entry?) -> [SyncCostBreakdown] {
        guard let breakdowns = entry?.modelBreakdowns else { return [] }
        return breakdowns
            .compactMap { breakdown in
                guard let cost = breakdown.costUSD, cost > 0 else { return nil }
                return SyncCostBreakdown(label: breakdown.modelName, costUSD: cost)
            }
            .sorted { lhs, rhs in
                if lhs.costUSD == rhs.costUSD {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.costUSD > rhs.costUSD
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
