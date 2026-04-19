import CodexBarSync
import Foundation
import SwiftData

/// Writes CloudKit-sourced snapshots into the local SwiftData store.
///
/// P2a: parallel-write only. `CloudSyncReader` calls `upsert` *after* the
/// legacy in-memory merge path has completed, so views keep reading the old
/// `@Observable SyncedUsageData`. P2b will flip views to `@Query` against
/// these @Model types.
///
/// Idempotency guarantees:
/// - `ProviderSnapshotModel` is keyed by `compositeKey = deviceID|providerID|accountEmail`.
///   Re-upserting the same snapshot updates fields in place, never duplicates.
/// - `UtilizationEntryModel` has no schema-level unique key. This bridge dedups
///   by `(provider, seriesName, capturedAt)` when inserting.
/// - `DeviceRecord` is keyed by `deviceID`. Legacy snapshots without a
///   deviceID use the fallback synthesised from the device name (see
///   `deviceIDFallback`) so multiple anonymous devices with different names
///   don't collide into one row.
enum SwiftDataBridge {
    // MARK: - Public entry points

    /// Upsert the *merged* snapshot that the legacy path currently produces.
    /// The merged snapshot has a synthetic deviceID of `nil` (it represents
    /// the merged view across devices), so we derive a stable fallback from
    /// `deviceName` to keep it as a distinct row from the individual devices.
    ///
    /// Prefer `upsert(deviceSnapshots:)` when raw per-device data is available
    /// — that gives SwiftData per-device granularity.
    static func upsert(
        mergedSnapshot snapshot: SyncedUsageSnapshot,
        into context: ModelContext
    ) throws {
        try Self.upsertSnapshot(snapshot, into: context)
    }

    /// Upsert raw per-device snapshots (the unmerged array returned by
    /// `CloudSyncReader.fetchAllDeviceSnapshots`). Each snapshot becomes (or
    /// updates) its own `DeviceRecord` with its own set of providers.
    static func upsert(
        deviceSnapshots: [SyncedUsageSnapshot],
        into context: ModelContext
    ) throws {
        for snapshot in deviceSnapshots {
            try Self.upsertSnapshot(snapshot, into: context)
        }
    }

    // MARK: - Core upsert

    private static func upsertSnapshot(
        _ snapshot: SyncedUsageSnapshot,
        into context: ModelContext
    ) throws {
        let deviceID = snapshot.deviceID ?? Self.deviceIDFallback(for: snapshot)
        let device = try Self.fetchOrCreateDevice(
            deviceID: deviceID,
            deviceName: snapshot.deviceName,
            appVersion: snapshot.appVersion,
            lastSyncAt: snapshot.syncTimestamp,
            in: context)

        for provider in snapshot.providers {
            try Self.upsertProvider(provider, deviceID: deviceID, device: device, in: context)
        }

        // Flush pending inserts so @Attribute(.unique) lookups resolve on the
        // next call (e.g. when upserting multiple device snapshots in one pass).
        try context.save()
    }

    private static func fetchOrCreateDevice(
        deviceID: String,
        deviceName: String,
        appVersion: String?,
        lastSyncAt: Date,
        in context: ModelContext
    ) throws -> DeviceRecord {
        let descriptor = FetchDescriptor<DeviceRecord>(
            predicate: #Predicate { $0.deviceID == deviceID })
        if let existing = try context.fetch(descriptor).first {
            existing.deviceName = deviceName
            existing.appVersion = appVersion
            existing.lastSyncAt = lastSyncAt
            return existing
        }
        let record = DeviceRecord(
            deviceID: deviceID,
            deviceName: deviceName,
            appVersion: appVersion,
            lastSyncAt: lastSyncAt)
        context.insert(record)
        return record
    }

    private static func upsertProvider(
        _ provider: ProviderUsageSnapshot,
        deviceID: String,
        device: DeviceRecord,
        in context: ModelContext
    ) throws {
        let compositeKey = ProviderSnapshotModel.makeCompositeKey(
            deviceID: deviceID,
            providerID: provider.providerID,
            accountEmail: provider.accountEmail)
        let descriptor = FetchDescriptor<ProviderSnapshotModel>(
            predicate: #Predicate { $0.compositeKey == compositeKey })

        // Encode opaque blobs once, reuse for both insert and update paths.
        let encoder = JSONEncoder()
        let rateWindowsData = (try? encoder.encode(provider.allRateWindows)) ?? Data("[]".utf8)
        let costSummaryData = provider.costSummary.flatMap { try? encoder.encode($0) }
        let budgetData = provider.budget.flatMap { try? encoder.encode($0) }

        let model: ProviderSnapshotModel
        if let existing = try context.fetch(descriptor).first {
            existing.providerName = provider.providerName
            existing.loginMethod = provider.loginMethod
            existing.statusMessage = provider.statusMessage
            existing.isError = provider.isError
            existing.lastUpdated = provider.lastUpdated
            existing.rateWindowsData = rateWindowsData
            existing.costSummaryData = costSummaryData
            existing.budgetData = budgetData
            existing.device = device
            model = existing
        } else {
            let created = ProviderSnapshotModel(
                deviceID: deviceID,
                providerID: provider.providerID,
                providerName: provider.providerName,
                accountEmail: provider.accountEmail,
                loginMethod: provider.loginMethod,
                statusMessage: provider.statusMessage,
                isError: provider.isError,
                lastUpdated: provider.lastUpdated,
                rateWindowsData: rateWindowsData,
                costSummaryData: costSummaryData,
                budgetData: budgetData,
                device: device)
            context.insert(created)
            model = created
        }

        try Self.upsertUtilization(
            history: provider.utilizationHistory ?? [],
            into: model,
            context: context)
    }

    private static func upsertUtilization(
        history: [SyncUtilizationSeries],
        into provider: ProviderSnapshotModel,
        context: ModelContext
    ) throws {
        guard !history.isEmpty else { return }

        // Index existing entries by (seriesName, capturedAt.timeIntervalSince1970)
        // for O(1) dedup. Using the Unix timestamp as the key avoids the
        // Date equality pitfalls around sub-microsecond rounding in SQLite.
        struct EntryKey: Hashable {
            let series: String
            let captured: TimeInterval
        }
        var existingByKey: [EntryKey: UtilizationEntryModel] = [:]
        for entry in provider.utilizationEntries {
            let key = EntryKey(series: entry.seriesName, captured: entry.capturedAt.timeIntervalSince1970)
            existingByKey[key] = entry
        }

        for series in history {
            for entry in series.entries {
                let key = EntryKey(series: series.name, captured: entry.capturedAt.timeIntervalSince1970)
                if let existing = existingByKey[key] {
                    existing.usedPercent = entry.usedPercent
                    existing.resetsAt = entry.resetsAt
                    existing.windowMinutes = series.windowMinutes
                } else {
                    let model = UtilizationEntryModel(
                        seriesName: series.name,
                        capturedAt: entry.capturedAt,
                        usedPercent: entry.usedPercent,
                        resetsAt: entry.resetsAt,
                        windowMinutes: series.windowMinutes,
                        provider: provider)
                    context.insert(model)
                    existingByKey[key] = model
                }
            }
        }
    }

    // MARK: - Fallbacks

    /// Deterministic synthetic deviceID for snapshots that arrive without one
    /// (KVS fallback path, or merged snapshots where the source IDs were
    /// collapsed). Using `deviceName` as the seed keeps per-name rows stable
    /// across relaunches while still distinguishing between devices.
    static func deviceIDFallback(for snapshot: SyncedUsageSnapshot) -> String {
        "legacy:" + snapshot.deviceName
    }
}
