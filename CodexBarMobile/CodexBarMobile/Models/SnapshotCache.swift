import CodexBarSync
import Foundation

/// In-memory snapshot cache with explicit zone-of-origin separation.
///
/// The v1 P6/P7 (reverted in Build 60) conflated "per-provider zone data"
/// with "SwiftData rows", which led to a multi-device regression: stale
/// legacy rows written to SwiftData by past full-fetches leaked into the
/// per-provider priority bucket when a silent push arrived.
///
/// v2 keeps the two zones in separate slots here, in memory. Priority merge
/// reads this struct; SwiftData is used ONLY for cold-start hydrate.
///
/// See `Research/011-mac-sync-incremental-v2.md` for the design + multi-device
/// traces.
struct SnapshotCache: Sendable {
    /// Device metadata common to both zones. Populated whenever either zone
    /// contributes a snapshot for that deviceID.
    struct Metadata: Sendable, Equatable {
        let deviceName: String
        let appVersion: String?
        let mobileVersion: String?
        let syncTimestamp: Date
        let notificationPushEnabled: Bool?
    }

    /// Per-provider zone data. Keyed `deviceID → compositeKey → provider`.
    /// Populated ONLY by:
    /// - Full CKQuery on `DeviceProvidersZone` (via `replaceFromFullFetch`)
    /// - Change-token delta from `DeviceProvidersZone` (via `applyDelta`)
    /// NEVER populated from legacy-zone data.
    var perProviderByDevice: [String: [String: ProviderUsageSnapshot]] = [:]

    /// Legacy-zone monolithic snapshots. Keyed `deviceID → snapshot`.
    /// Populated ONLY by full CKQuery on `DeviceSnapshotsZone`/default zone.
    /// Untouched by silent-push-driven incremental refreshes (since silent
    /// push is only subscribed on the new zone).
    var legacyByDevice: [String: SyncedUsageSnapshot] = [:]

    /// Device metadata (deviceName, appVersion, push flag, etc). Keyed
    /// deviceID. Not zone-specific — the device IS the device regardless of
    /// which zone is currently authoritative for its providers.
    var deviceMetadata: [String: Metadata] = [:]

    // MARK: - Mutations

    /// Replace the cache contents from a full CKQuery round-trip.
    ///
    /// `perProviderSnapshots` = reconstructed-from-envelopes snapshots whose
    /// `deviceID` is authoritative (they came from the new zone).
    /// `legacySnapshots` = monolithic snapshots from the legacy zones.
    mutating func replaceFromFullFetch(
        perProviderSnapshots: [SyncedUsageSnapshot],
        legacySnapshots: [SyncedUsageSnapshot]
    ) {
        self.perProviderByDevice.removeAll(keepingCapacity: true)
        self.legacyByDevice.removeAll(keepingCapacity: true)

        // Populate per-provider bucket. Each snapshot represents one device's
        // worth of envelopes. Composite key groups providers within the device.
        for snapshot in perProviderSnapshots {
            guard let deviceID = snapshot.deviceID else { continue }
            var byComposite: [String: ProviderUsageSnapshot] = [:]
            for provider in snapshot.providers {
                byComposite[Self.compositeKey(for: provider)] = provider
            }
            self.perProviderByDevice[deviceID] = byComposite
            self.deviceMetadata[deviceID] = Metadata(
                deviceName: snapshot.deviceName,
                appVersion: snapshot.appVersion,
                mobileVersion: snapshot.mobileVersion,
                syncTimestamp: snapshot.syncTimestamp,
                notificationPushEnabled: snapshot.notificationPushEnabled)
        }

        // Populate legacy bucket. If a device only appears here (not in
        // per-provider bucket) its metadata comes from here instead.
        for snapshot in legacySnapshots {
            let deviceID = snapshot.deviceID ?? Self.syntheticDeviceID(from: snapshot)
            self.legacyByDevice[deviceID] = snapshot
            if self.deviceMetadata[deviceID] == nil {
                self.deviceMetadata[deviceID] = Metadata(
                    deviceName: snapshot.deviceName,
                    appVersion: snapshot.appVersion,
                    mobileVersion: snapshot.mobileVersion,
                    syncTimestamp: snapshot.syncTimestamp,
                    notificationPushEnabled: snapshot.notificationPushEnabled)
            }
        }
    }

    /// Apply a change-token delta from the per-provider zone. Legacy bucket
    /// is NOT touched — silent push only fires on the new zone, so legacy
    /// data is still as-of-last-full-fetch.
    mutating func applyDelta(
        upserted: [ProviderUsageEnvelope],
        deletedRecordNames: [String]
    ) {
        for envelope in upserted {
            var byComposite = self.perProviderByDevice[envelope.deviceID] ?? [:]
            byComposite[Self.compositeKey(for: envelope.provider)] = envelope.provider
            self.perProviderByDevice[envelope.deviceID] = byComposite

            self.deviceMetadata[envelope.deviceID] = Metadata(
                deviceName: envelope.deviceName,
                appVersion: envelope.appVersion,
                mobileVersion: envelope.mobileVersion,
                syncTimestamp: envelope.syncTimestamp,
                notificationPushEnabled: envelope.notificationPushEnabled)
        }

        for recordName in deletedRecordNames {
            // CloudKit record name format is "deviceID|providerID|accountEmail".
            // Same format as compositeKey so we can look up directly once we
            // strip the deviceID prefix.
            guard let (deviceID, composite) = Self.splitRecordName(recordName) else {
                continue
            }
            var byComposite = self.perProviderByDevice[deviceID] ?? [:]
            byComposite.removeValue(forKey: composite)
            if byComposite.isEmpty {
                self.perProviderByDevice.removeValue(forKey: deviceID)
            } else {
                self.perProviderByDevice[deviceID] = byComposite
            }
            // deviceMetadata stays — legacy might still have data for this device.
        }
    }

    /// Replace per-provider bucket entirely — called after a token-expired
    /// full replay where the server returns every record from the zone. We
    /// can't incrementally apply such a replay because we don't know which
    /// records it SHOULD cover; safest to rebuild from scratch using the
    /// replay's envelopes.
    mutating func replacePerProviderFromReplay(_ envelopes: [ProviderUsageEnvelope]) {
        self.perProviderByDevice.removeAll(keepingCapacity: true)
        for envelope in envelopes {
            var byComposite = self.perProviderByDevice[envelope.deviceID] ?? [:]
            byComposite[Self.compositeKey(for: envelope.provider)] = envelope.provider
            self.perProviderByDevice[envelope.deviceID] = byComposite

            self.deviceMetadata[envelope.deviceID] = Metadata(
                deviceName: envelope.deviceName,
                appVersion: envelope.appVersion,
                mobileVersion: envelope.mobileVersion,
                syncTimestamp: envelope.syncTimestamp,
                notificationPushEnabled: envelope.notificationPushEnabled)
        }
    }

    /// Seed the cache from SwiftData-hydrated snapshots at cold start. Goes
    /// into `legacyByDevice` regardless of origin — SwiftData doesn't track
    /// zone-of-origin so we treat this as "best-effort visible" data. The
    /// next full fetch will overwrite with authoritative zone attribution.
    mutating func seedFromColdStart(_ snapshots: [SyncedUsageSnapshot]) {
        for snapshot in snapshots {
            let deviceID = snapshot.deviceID ?? Self.syntheticDeviceID(from: snapshot)
            self.legacyByDevice[deviceID] = snapshot
            self.deviceMetadata[deviceID] = Metadata(
                deviceName: snapshot.deviceName,
                appVersion: snapshot.appVersion,
                mobileVersion: snapshot.mobileVersion,
                syncTimestamp: snapshot.syncTimestamp,
                notificationPushEnabled: snapshot.notificationPushEnabled)
        }
    }

    // MARK: - Read (priority merge)

    /// Build the list of per-device snapshots with per-provider winning over
    /// legacy for any device that has per-provider entries. Pure — the caller
    /// typically feeds this through `CloudSyncReader.mergeSnapshots` for the
    /// final cross-device merge.
    func buildDeviceSnapshots() -> [SyncedUsageSnapshot] {
        var result: [SyncedUsageSnapshot] = []
        let allDeviceIDs = Set(self.perProviderByDevice.keys)
            .union(self.legacyByDevice.keys)

        for deviceID in allDeviceIDs {
            if let byComposite = self.perProviderByDevice[deviceID],
               !byComposite.isEmpty
            {
                // Per-provider wins. Reconstruct a SyncedUsageSnapshot.
                let providers = byComposite.values
                    .sorted { $0.lastUpdated > $1.lastUpdated }
                let meta = self.deviceMetadata[deviceID]
                result.append(SyncedUsageSnapshot(
                    providers: Array(providers),
                    syncTimestamp: meta?.syncTimestamp ?? Date(),
                    deviceName: meta?.deviceName ?? deviceID,
                    deviceID: deviceID,
                    appVersion: meta?.appVersion,
                    mobileVersion: meta?.mobileVersion,
                    notificationPushEnabled: meta?.notificationPushEnabled))
            } else if let legacy = self.legacyByDevice[deviceID] {
                result.append(legacy)
            }
        }

        result.sort { $0.syncTimestamp > $1.syncTimestamp }
        return result
    }

    // MARK: - Helpers

    static func compositeKey(for provider: ProviderUsageSnapshot) -> String {
        "\(provider.providerID)|\(provider.accountEmail ?? "_")"
    }

    /// Parses a CloudKit recordName of the form
    /// `"deviceID|providerID|accountEmail"` back into `(deviceID, composite)`.
    /// Returns nil on malformed input — caller should skip such records.
    static func splitRecordName(_ recordName: String) -> (deviceID: String, composite: String)? {
        let parts = recordName.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let deviceID = String(parts[0])
        let composite = "\(parts[1])|\(parts[2])"
        return (deviceID, composite)
    }

    /// Fallback deviceID for legacy snapshots that lack one (old KVS path).
    /// Matches `SwiftDataBridge.deviceIDFallback` so SwiftData and the cache
    /// agree on the same synthetic key.
    static func syntheticDeviceID(from snapshot: SyncedUsageSnapshot) -> String {
        "legacy:" + snapshot.deviceName
    }
}
