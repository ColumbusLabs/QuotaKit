import CodexBarSync
import Foundation

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

    /// Sets up CloudKit subscription for push notifications on record changes.
    func setupSubscription() async throws {
        try await syncManager.setupSubscription()
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

        // Build device name list for display
        let deviceNames = snapshots.map(\.deviceName)
        let combinedDeviceName = deviceNames.count == 1
            ? deviceNames[0]
            : deviceNames.joined(separator: ", ")

        return SyncedUsageSnapshot(
            providers: mergedProviders,
            syncTimestamp: latestTimestamp,
            deviceName: combinedDeviceName,
            deviceID: nil,
            appVersion: snapshots.first?.appVersion,
            mobileVersion: snapshots.first?.mobileVersion)
    }

    /// Merges multiple entries of the same provider+account from different devices.
    private static func mergeProviderEntries(_ entries: [ProviderUsageSnapshot]) -> ProviderUsageSnapshot {
        // Take the most recent entry as the base (for rate limits, identity, status)
        let base = entries.max(by: { $0.lastUpdated < $1.lastUpdated })!

        // For local-cost providers, aggregate cost data across devices
        let isLocalCost = localCostProviders.contains(base.providerID)
        let mergedCost: SyncCostSummary?

        if isLocalCost {
            mergedCost = mergeCostSummaries(entries.compactMap(\.costSummary))
        } else {
            mergedCost = base.costSummary
        }

        return ProviderUsageSnapshot(
            providerID: base.providerID,
            providerName: base.providerName,
            primary: base.primary,
            secondary: base.secondary,
            accountEmail: base.accountEmail,
            loginMethod: base.loginMethod,
            statusMessage: base.statusMessage,
            isError: base.isError,
            lastUpdated: base.lastUpdated,
            costSummary: mergedCost,
            budget: base.budget,
            rateWindows: base.rateWindows)
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
}
