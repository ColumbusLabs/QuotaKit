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
    /// Upsert raw per-device snapshots (the unmerged array returned by
    /// `CloudSyncReader.fetchAllDeviceSnapshots`). Each snapshot becomes (or
    /// updates) its own `DeviceRecord` with its own set of providers.
    ///
    /// Note: there is intentionally no separate "merged snapshot" upsert API.
    /// A merged snapshot's `deviceName` is derived from the set of
    /// contributing devices, which changes as devices are added/removed —
    /// storing it as a row under a `"legacy:<deviceName>"` fallback key
    /// orphans the old merged row every time the set changes. P2b views
    /// instead re-derive the merged view on the fly via `@Query` against
    /// per-device rows, which are keyed by stable deviceID.
    ///
    /// Legacy snapshots from the KVS fallback path (single-device Macs that
    /// predate CloudKit sync) still arrive with `deviceID == nil` but carry
    /// a stable single `deviceName`; they land in a `"legacy:<deviceName>"`
    /// row via `deviceIDFallback` — that's fine because the name IS stable
    /// for a single device.
    static func upsert(
        deviceSnapshots: [SyncedUsageSnapshot],
        into context: ModelContext
    ) throws {
        // Build the set of deviceIDs that should exist after this upsert. Anything
        // currently in the store but NOT in this set has been removed upstream
        // (user disconnected a Mac, reset sync, etc.) and must be pruned. Without
        // this, stale DeviceRecord rows accumulate forever. Flagged in Codex review (P2).
        var incomingDeviceIDs: Set<String> = []
        for snapshot in deviceSnapshots {
            let deviceID = snapshot.deviceID ?? Self.deviceIDFallback(for: snapshot)
            incomingDeviceIDs.insert(deviceID)
            try Self.upsertSnapshot(snapshot, into: context)
        }

        // Prune DeviceRecord rows that correspond to devices that disappeared
        // from upstream. Cascades to ProviderSnapshotModel and UtilizationEntryModel
        // via @Relationship(deleteRule: .cascade).
        let allDevicesDescriptor = FetchDescriptor<DeviceRecord>()
        let existingDevices = try context.fetch(allDevicesDescriptor)
        for device in existingDevices where !incomingDeviceIDs.contains(device.deviceID) {
            context.delete(device)
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

        // Build the set of composite keys present in this snapshot. Anything on the
        // existing DeviceRecord that is NOT in this set has been removed upstream
        // (user disconnected a provider on Mac) and must be pruned locally to keep
        // the SwiftData mirror in lockstep. Without this, phantom provider rows
        // accumulate forever. Flagged in Codex review (P2).
        let incomingKeys: Set<String> = Set(snapshot.providers.map { provider in
            ProviderSnapshotModel.makeCompositeKey(
                deviceID: deviceID,
                providerID: provider.providerID,
                accountEmail: provider.accountEmail)
        })

        for provider in snapshot.providers {
            try Self.upsertProvider(provider, deviceID: deviceID, device: device, in: context)
        }

        // Prune rows that belonged to this device but disappeared from the
        // incoming snapshot. Cascade delete on the provider → utilization
        // relationship cleans up orphan entries automatically.
        let staleDescriptor = FetchDescriptor<ProviderSnapshotModel>(
            predicate: #Predicate { $0.deviceID == deviceID })
        let existingForDevice = try context.fetch(staleDescriptor)
        for existing in existingForDevice where !incomingKeys.contains(existing.compositeKey) {
            context.delete(existing)
        }

        // Flush pending inserts/deletes so @Attribute(.unique) lookups resolve
        // on the next call (e.g. when upserting multiple device snapshots in one pass).
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
        // Upstream utilization history is a rolling window on Mac (session cap 730 entries).
        // Entries that age out upstream must also be pruned locally, otherwise the mirror
        // grows forever and P2b @Query charts would show stale buckets. If the incoming
        // history is empty we clear everything on this provider. Flagged in Codex review (P2).
        guard !history.isEmpty else {
            for existing in provider.utilizationEntries {
                context.delete(existing)
            }
            return
        }

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

        // Build the set of keys present in the incoming history — the eventual "kept" set.
        var incomingKeys: Set<EntryKey> = []
        for series in history {
            for entry in series.entries {
                let key = EntryKey(series: series.name, captured: entry.capturedAt.timeIntervalSince1970)
                incomingKeys.insert(key)
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

        // Prune entries that existed locally but disappeared from the rolling-window
        // history upstream.
        for (key, existing) in existingByKey where !incomingKeys.contains(key) {
            context.delete(existing)
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
