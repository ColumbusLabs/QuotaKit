import CloudKit
import CodexBarSync
import Foundation
import SwiftData

/// iOS-side reader that fetches usage snapshots from CloudKit (all devices)
/// and falls back to legacy KVS for older Mac app versions.
final class CloudSyncReader: @unchecked Sendable {
    private let syncManager: CloudSyncManager

    init(syncManager: CloudSyncManager = .shared) {
        self.syncManager = syncManager
    }

    // MARK: - CloudKit (primary)

    /// Fetches snapshots from all devices via CloudKit.
    func fetchAllDeviceSnapshots() async -> MultiDeviceSyncResult {
        await syncManager.fetchAllDeviceSnapshots()
    }

    // MARK: - Cache-based flow (v2 — Research/011)

    /// Per-provider zone only. Caller owns the priority-merge decision.
    func fetchPerProviderDeviceSnapshots() async -> MultiDeviceSyncResult {
        await syncManager.fetchPerProviderDeviceSnapshots()
    }

    /// Legacy zones only (custom zone + default zone).
    func fetchLegacyDeviceSnapshots() async -> MultiDeviceSyncResult {
        await syncManager.fetchLegacyDeviceSnapshots()
    }

    /// Incremental change-token fetch for the per-provider zone.
    func fetchPerProviderZoneChanges(
        since token: CKServerChangeToken?
    ) async -> CloudSyncManager.PerProviderZoneChanges {
        await syncManager.fetchPerProviderZoneChanges(since: token)
    }

    // MARK: - Legacy KVS (backward compatibility)

    /// Returns the most recently synced snapshot from KVS (fallback).
    func latestKVSSnapshot() -> SyncedUsageSnapshot? {
        syncManager.fetchKVSSnapshot()
    }

    /// Starts observing KVS changes (backward compat with older Mac apps).
    func startKVSObserving(handler: @escaping @MainActor (SyncResult) -> Void) {
        syncManager.startKVSObserving(handler: handler)
    }

    @discardableResult
    func synchronizeKVS() -> Bool {
        syncManager.synchronizeKVSStore()
    }

    func stopKVSObserving() {
        syncManager.stopKVSObserving()
    }

    // MARK: - Deprecated shims (keep callers compiling during transition)

    func latestSnapshot() -> SyncedUsageSnapshot? {
        syncManager.fetchKVSSnapshot()
    }

    func startObserving(handler: @escaping @MainActor (SyncResult) -> Void) {
        syncManager.startKVSObserving(handler: handler)
    }

    @discardableResult
    func synchronize() -> Bool {
        syncManager.synchronizeKVSStore()
    }

    func stopObserving() {
        syncManager.stopKVSObserving()
    }

    // MARK: - SwiftData parallel write (P2a)

    /// Mirrors the raw per-device CloudKit snapshots into the SwiftData store.
    ///
    /// P2a is additive: the old `@Observable` path continues to drive views.
    /// This method exists so `SyncedUsageData` can call it right after
    /// `mergeSnapshots(...)` completes, keeping the two sources in lockstep.
    ///
    /// Writes ONLY per-device rows. The merged snapshot is not persisted —
    /// P2b's @Query-based views will re-derive the merged view on the fly
    /// from per-device rows, so storing a separate merged row would be
    /// redundant duplication. Codex review (P2) also flagged that the
    /// synthetic "legacy:<deviceName>" key for merged snapshots shifts
    /// whenever the set of contributing devices changes, which would
    /// orphan prior merged rows. Per-device rows are keyed by stable
    /// deviceID, so they accumulate cleanly.
    static func persistToSwiftData(
        deviceSnapshots: [SyncedUsageSnapshot],
        merged _: SyncedUsageSnapshot?,
        context: ModelContext
    ) {
        do {
            try SwiftDataBridge.upsert(deviceSnapshots: deviceSnapshots, into: context)
        } catch {
            // P2a is parallel-write; failures here must never break the
            // legacy path. Log and move on.
            print("[CodexBar SwiftData] Parallel-write upsert failed: \(error)")
        }
    }

    // MARK: - Multi-device merge

    /// Providers whose cost data comes from LOCAL files (per-machine CLI history).
    /// Cost data from these providers must be SUMMED across devices, not deduplicated.
    /// All other providers read cost from account-level web APIs → safe to deduplicate.
    private static let localCostProviders: Set<String> = ["claude", "codex", "vertexai"]

    /// Merges snapshots from multiple devices into a single unified snapshot.
    ///
    /// Merge strategy:
    /// - Same `providerID` + same `accountEmail`:
    ///   - Rate limits, identity, status → take the most recent `lastUpdated`
    ///   - Cost data for local-cost providers (Claude, Codex, VertexAI) → SUM daily costs across devices
    ///   - Cost data for account-level providers → take the most recent
    /// - Same `providerID` + different `accountEmail` → keep both (different accounts)
    /// - Providers from different devices are combined
    static func mergeSnapshots(_ snapshots: [SyncedUsageSnapshot]) -> SyncedUsageSnapshot? {
        guard !snapshots.isEmpty else { return nil }

        // Group all providers by key (providerID + accountEmail)
        var providersByKey: [String: [ProviderUsageSnapshot]] = [:]

        for snapshot in snapshots {
            for provider in snapshot.providers {
                let key = "\(provider.providerID)|\(provider.accountEmail ?? "")"
                providersByKey[key, default: []].append(provider)
            }
        }

        // Merge each group
        var mergedProviders: [ProviderUsageSnapshot] = []
        for (_, providers) in providersByKey {
            if providers.count == 1 {
                mergedProviders.append(providers[0])
            } else {
                mergedProviders.append(mergeProviderEntries(providers))
            }
        }

        // Sort providers by name for stable UI ordering
        mergedProviders.sort { $0.providerName < $1.providerName }

        // Use the most recent sync timestamp across all devices
        let latestTimestamp = snapshots.map(\.syncTimestamp).max() ?? Date()

        // Build device name list for display. Sort first so the combined string is stable
        // across fetches regardless of server iteration order — without this, SwiftDataBridge's
        // deviceID fallback (`"legacy:" + deviceName`) would see "Mac A, Mac B" at one moment
        // and "Mac B, Mac A" at another, producing duplicate merged-device rows in the local
        // store. Flagged in Codex review (P2).
        let deviceNames = snapshots.map(\.deviceName).sorted()
        let combinedDeviceName = deviceNames.count == 1
            ? deviceNames[0]
            : deviceNames.joined(separator: ", ")

        // If ANY device has push disabled, respect that (conservative approach)
        let pushEnabled: Bool? = snapshots.contains(where: { $0.notificationPushEnabled == false })
            ? false
            : snapshots.first?.notificationPushEnabled

        // Pick the *highest* app/mobile version across devices so the merged
        // "Mac App" / "Synced Mobile Version" row reflects the most up-to-date
        // client, regardless of which snapshot CloudKit happened to iterate
        // first. Prior code used `snapshots.first?.appVersion`, which flipped
        // non-deterministically for users running two Macs on different
        // CodexBar versions and showed whichever arrived first.
        let appVersion = snapshots.compactMap(\.appVersion).max(by: Self.semverLessThan)
        let mobileVersion = snapshots.compactMap(\.mobileVersion).max(by: Self.semverLessThan)

        return SyncedUsageSnapshot(
            providers: mergedProviders,
            syncTimestamp: latestTimestamp,
            deviceName: combinedDeviceName,
            deviceID: nil,
            appVersion: appVersion,
            mobileVersion: mobileVersion,
            notificationPushEnabled: pushEnabled)
    }

    /// Orders two semver-ish strings like `"0.20.3"` / `"1.2.0"` so `max(by:)`
    /// returns the highest. Falls back to string comparison for non-numeric
    /// segments (e.g. `"0.20.0-beta"`). Strictly lower; ties are `false`.
    static func semverLessThan(_ lhs: String, _ rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").map(String.init)
        let rhsParts = rhs.split(separator: ".").map(String.init)
        let count = max(lhsParts.count, rhsParts.count)
        for i in 0 ..< count {
            let l = i < lhsParts.count ? lhsParts[i] : "0"
            let r = i < rhsParts.count ? rhsParts[i] : "0"
            if let li = Int(l), let ri = Int(r) {
                if li != ri { return li < ri }
            } else if l != r {
                return l < r
            }
        }
        return false
    }

    /// For an **account-level optional field** (budget, perplexityCredits,
    /// non-local-cost `costSummary`, etc.) — returns the value from the most
    /// recent device that actually has it populated. Falls through older
    /// devices if the newer ones don't (yet) have data for this field.
    ///
    /// This is the right semantics when two Macs running different CodexBar
    /// versions sync to the same iCloud account: the older Mac may never
    /// populate a newly-added field (e.g. 0.20.2 doesn't know about
    /// `perplexityCredits`), but the newer Mac does — naive take-latest on
    /// `lastUpdated` would drop the data to `nil` every time the older Mac
    /// happened to refresh last. With `latestNonNil`, the iPhone renders
    /// the richer data as long as ANY synced device has it, regardless of
    /// refresh timing.
    ///
    /// Returns nil only when every entry has nil for the keypath.
    private static func latestNonNil<T>(
        _ entries: [ProviderUsageSnapshot],
        _ keyPath: KeyPath<ProviderUsageSnapshot, T?>
    ) -> T? {
        entries
            .sorted(by: { $0.lastUpdated > $1.lastUpdated })
            .first(where: { $0[keyPath: keyPath] != nil })?[keyPath: keyPath]
    }

    /// Merges multiple entries of the same provider+account from different devices.
    ///
    /// Field-by-field semantics:
    ///   - Identity (`providerID` / `providerName` / `accountEmail`): same
    ///     across all entries by construction — take from base.
    ///   - Status (`statusMessage` / `isError`): take from latest entry;
    ///     "most recent status" is the meaningful user-facing signal.
    ///   - Rate windows (`primary` / `secondary` / `rateWindows`): take from
    ///     latest entry — these are always populated on every provider
    ///     refresh, so the newer timestamp's data is the current quota state.
    ///   - Cost (`costSummary`): SUM across devices for local-cost providers
    ///     (claude / codex / vertexai, which read per-Mac CLI files), take
    ///     **latestNonNil** otherwise (account-level API data; old-Mac
    ///     version-drift protection).
    ///   - Utilization history: MERGE across devices and dedup by hour.
    ///   - Account-level structured data (`budget` / `perplexityCredits` /
    ///     `loginMethod`): **latestNonNil** — both Macs observe the same
    ///     account-level pool, but only Macs running the version that
    ///     knows the field will populate it. Take any non-nil from newest
    ///     down so cross-version pairs don't flicker.
    private static func mergeProviderEntries(_ entries: [ProviderUsageSnapshot]) -> ProviderUsageSnapshot {
        // Take the most recent entry as the base (for rate limits + status)
        let base = entries.max(by: { $0.lastUpdated < $1.lastUpdated })!

        // Cost: sum for local-cost providers, otherwise latestNonNil (account-level).
        let isLocalCost = localCostProviders.contains(base.providerID)
        let mergedCost: SyncCostSummary?
        if isLocalCost {
            mergedCost = mergeCostSummaries(entries.compactMap(\.costSummary))
        } else {
            mergedCost = Self.latestNonNil(entries, \.costSummary)
        }

        // Utilization history: merge across ALL devices, dedup by hour.
        let mergedUtilization = Self.mergeUtilizationHistories(
            entries.compactMap(\.utilizationHistory))

        return ProviderUsageSnapshot(
            providerID: base.providerID,
            providerName: base.providerName,
            primary: base.primary,
            secondary: base.secondary,
            accountEmail: base.accountEmail,
            loginMethod: Self.latestNonNil(entries, \.loginMethod),
            statusMessage: base.statusMessage,
            isError: base.isError,
            lastUpdated: base.lastUpdated,
            costSummary: mergedCost,
            budget: Self.latestNonNil(entries, \.budget),
            rateWindows: base.rateWindows,
            utilizationHistory: mergedUtilization,
            perplexityCredits: Self.latestNonNil(entries, \.perplexityCredits))
    }

    /// Sums cost data from multiple devices.
    /// Daily points are merged by dayKey (costs summed), then totals are recalculated.
    private static func mergeCostSummaries(_ summaries: [SyncCostSummary]) -> SyncCostSummary? {
        guard !summaries.isEmpty else { return nil }
        if summaries.count == 1 { return summaries[0] }

        // Merge daily points by dayKey, summing costs and tokens
        var dailyByKey: [String: (costUSD: Double, totalTokens: Int, modelBreakdowns: [SyncCostBreakdown])] = [:]

        for summary in summaries {
            for point in summary.daily {
                if var existing = dailyByKey[point.dayKey] {
                    existing.costUSD += point.costUSD
                    existing.totalTokens += point.totalTokens
                    // Combine model breakdowns (merge by label, sum costs)
                    var breakdownByLabel: [String: Double] = [:]
                    for b in existing.modelBreakdowns { breakdownByLabel[b.label, default: 0] += b.costUSD }
                    for b in point.modelBreakdowns { breakdownByLabel[b.label, default: 0] += b.costUSD }
                    existing.modelBreakdowns = breakdownByLabel
                        .map { SyncCostBreakdown(label: $0.key, costUSD: $0.value) }
                        .sorted { $0.costUSD > $1.costUSD }
                    dailyByKey[point.dayKey] = existing
                } else {
                    dailyByKey[point.dayKey] = (point.costUSD, point.totalTokens, point.modelBreakdowns)
                }
            }
        }

        let mergedDaily = dailyByKey.keys.sorted().map { dayKey in
            let entry = dailyByKey[dayKey]!
            return SyncDailyPoint(
                dayKey: dayKey,
                costUSD: entry.costUSD,
                totalTokens: entry.totalTokens,
                modelBreakdowns: entry.modelBreakdowns)
        }

        // Recalculate totals from merged daily data
        let totalCost = mergedDaily.reduce(0) { $0 + $1.costUSD }
        let totalTokens = mergedDaily.reduce(0) { $0 + $1.totalTokens }

        // Sum session costs across devices (each device has its own session)
        let sessionCost = summaries.compactMap(\.sessionCostUSD).reduce(0, +)
        let sessionTokens = summaries.compactMap(\.sessionTokens).reduce(0, +)

        return SyncCostSummary(
            sessionCostUSD: sessionCost > 0 ? sessionCost : nil,
            sessionTokens: sessionTokens > 0 ? sessionTokens : nil,
            last30DaysCostUSD: mergedDaily.isEmpty ? nil : totalCost,
            last30DaysTokens: mergedDaily.isEmpty ? nil : totalTokens,
            daily: mergedDaily)
    }

    // MARK: - Utilization History Merge + Hourly Dedup

    /// Merges utilization histories from multiple devices.
    /// Session quota is account-level, so entries from different Macs
    /// are observations of the SAME metric at different times.
    ///
    /// Steps:
    /// 1. Collect entries from all devices per series **name** (not per
    ///    (name, windowMinutes)). Cross-version Macs may report the same
    ///    logical series with a drifted `windowMinutes` (e.g. a fallback
    ///    classification on an older build); splitting on that leaves two
    ///    "session" series in the merged list and makes downstream pickers
    ///    like `history.first(where: { $0.name == "session" })` hit the
    ///    stale/empty variant non-deterministically. The entries describe
    ///    the same account-level pool regardless, so unioning them is safe.
    /// 2. Dedup by hour: group by floor(capturedAt / 1h), take average
    /// 3. Keep the winning series' `windowMinutes` from the entry that
    ///    captured most recently — that's the newest-Mac reading
    /// 4. Result: clean hourly data regardless of device count
    private static func mergeUtilizationHistories(
        _ histories: [[SyncUtilizationSeries]]
    ) -> [SyncUtilizationSeries]? {
        let allSeries = histories.flatMap { $0 }
        guard !allSeries.isEmpty else { return nil }

        var entriesByName: [String: [SyncUtilizationEntry]] = [:]
        // Remember the latest windowMinutes per name so we can pick the
        // freshest reading when two devices disagree.
        var freshestWindowByName: [String: (capturedAt: Date, windowMinutes: Int)] = [:]

        for series in allSeries {
            entriesByName[series.name, default: []].append(contentsOf: series.entries)
            if let latestCaptured = series.entries.map(\.capturedAt).max() {
                let current = freshestWindowByName[series.name]
                if current == nil || latestCaptured > current!.capturedAt {
                    freshestWindowByName[series.name] = (latestCaptured, series.windowMinutes)
                }
            } else if freshestWindowByName[series.name] == nil {
                // Empty series: record its windowMinutes as a fallback in case
                // no other device has entries for this name.
                freshestWindowByName[series.name] = (.distantPast, series.windowMinutes)
            }
        }

        // Dedup each series by hour
        var result: [SyncUtilizationSeries] = []

        for (name, entries) in entriesByName {
            let deduped = Self.dedupByHour(entries)
            guard !deduped.isEmpty else { continue }
            let windowMinutes = freshestWindowByName[name]?.windowMinutes ?? 0
            result.append(SyncUtilizationSeries(
                name: name,
                windowMinutes: windowMinutes,
                entries: deduped))
        }

        // Sort: session first, then weekly, then others
        result.sort { lhs, rhs in
            let order = ["session": 0, "weekly": 1, "opus": 2]
            return (order[lhs.name] ?? 99) < (order[rhs.name] ?? 99)
        }

        return result.isEmpty ? nil : result
    }

    /// Groups entries by hour + reset segment, averages within each bucket.
    /// Keeps reset boundaries separate to avoid mixing pre/post-reset samples.
    private static func dedupByHour(_ entries: [SyncUtilizationEntry]) -> [SyncUtilizationEntry] {
        guard !entries.isEmpty else { return [] }

        let hourInterval: TimeInterval = 3600

        // Key: (hourSlot, resetBoundary) — different reset windows in the same hour stay separate
        struct BucketKey: Hashable {
            let hourSlot: Int
            let resetEpoch: Int  // floor(resetsAt / hourInterval), or -1 if nil
        }

        var buckets: [BucketKey: (totalPercent: Double, count: Int, latestReset: Date?, latestCaptured: Date)] = [:]

        for entry in entries {
            let hourSlot = Int(floor(entry.capturedAt.timeIntervalSince1970 / hourInterval))
            let resetEpoch = entry.resetsAt.map { Int(floor($0.timeIntervalSince1970 / hourInterval)) } ?? -1
            let key = BucketKey(hourSlot: hourSlot, resetEpoch: resetEpoch)

            if var bucket = buckets[key] {
                bucket.totalPercent += entry.usedPercent
                bucket.count += 1
                if entry.capturedAt > bucket.latestCaptured {
                    bucket.latestCaptured = entry.capturedAt
                    bucket.latestReset = entry.resetsAt ?? bucket.latestReset
                }
                buckets[key] = bucket
            } else {
                buckets[key] = (
                    totalPercent: entry.usedPercent,
                    count: 1,
                    latestReset: entry.resetsAt,
                    latestCaptured: entry.capturedAt)
            }
        }

        // Convert back to entries, sorted by time
        return buckets.keys
            .sorted { $0.hourSlot < $1.hourSlot || ($0.hourSlot == $1.hourSlot && $0.resetEpoch < $1.resetEpoch) }
            .map { key in
                let bucket = buckets[key]!
                let avg = bucket.totalPercent / Double(bucket.count)
                return SyncUtilizationEntry(
                    capturedAt: bucket.latestCaptured,
                    usedPercent: min(100, max(0, avg)),
                    resetsAt: bucket.latestReset)
            }
    }
}
