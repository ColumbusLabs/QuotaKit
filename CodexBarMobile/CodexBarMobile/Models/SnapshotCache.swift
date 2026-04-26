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

    // MARK: - Helpers (ghost filter)

    /// A provider envelope is a "ghost" if it carries NO usable signal —
    /// no rate windows, no cost, no budget, no error, no status message.
    /// These records leak into CloudKit from Mac-side early pushes that run
    /// before a provider's OAuth/cookie/etc. has loaded: `accountEmail` ends
    /// up `nil` and every data field empty. The Mac later pushes a real
    /// record with `accountEmail="user@..."` — a DIFFERENT CloudKit
    /// recordName — so the ghost persists indefinitely.
    ///
    /// iOS drops ghosts at reconstruction time so they never reach SwiftData
    /// or the merge layer. Long-term fix belongs on the Mac side (skip push
    /// when no data is ready), but this defense eliminates the ghost on
    /// existing installs without a Mac rebuild.
    private static func isGhost(_ provider: ProviderUsageSnapshot) -> Bool {
        provider.primary == nil
            && provider.secondary == nil
            && provider.rateWindows.isEmpty
            && provider.costSummary == nil
            && provider.budget == nil
            && !provider.isError
            && provider.statusMessage == nil
    }

    // MARK: - Mutations

    /// Replace the cache contents from a full CKQuery round-trip.
    ///
    /// Each argument is **optional**: pass `nil` to leave that bucket
    /// untouched (used when its zone fetch errored transiently — a network
    /// blip shouldn't wipe valid cached state; Codex review P1 on Build 66).
    /// Pass `[]` to authoritatively clear that bucket (its zone returned
    /// legitimate empty / zoneNotFound, distinct from error).
    ///
    /// `perProviderSnapshots` = reconstructed-from-envelopes snapshots whose
    /// `deviceID` is authoritative (they came from the new zone).
    /// `legacySnapshots` = monolithic snapshots from the legacy zones.
    mutating func replaceFromFullFetch(
        perProviderSnapshots: [SyncedUsageSnapshot]?,
        legacySnapshots: [SyncedUsageSnapshot]?
    ) {
        if let perProviderSnapshots {
            self.perProviderByDevice.removeAll(keepingCapacity: true)

            // Populate per-provider bucket. Each snapshot represents one device's
            // worth of envelopes. Composite key groups providers within the device.
            // Ghost records (no rate / cost / budget / error / status) are
            // dropped — see `isGhost` for rationale.
            for snapshot in perProviderSnapshots {
                guard let deviceID = snapshot.deviceID else { continue }
                var byComposite: [String: ProviderUsageSnapshot] = [:]
                for provider in snapshot.providers where !Self.isGhost(provider) {
                    byComposite[Self.compositeKey(for: provider)] = provider
                }
                guard !byComposite.isEmpty else { continue }
                self.perProviderByDevice[deviceID] = byComposite
                self.deviceMetadata[deviceID] = Metadata(
                    deviceName: snapshot.deviceName,
                    appVersion: snapshot.appVersion,
                    mobileVersion: snapshot.mobileVersion,
                    syncTimestamp: snapshot.syncTimestamp,
                    notificationPushEnabled: snapshot.notificationPushEnabled)
            }
        }

        if let legacySnapshots {
            self.legacyByDevice.removeAll(keepingCapacity: true)

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
    }

    /// Apply a change-token delta from the per-provider zone. Legacy bucket
    /// is NOT touched — silent push only fires on the new zone, so legacy
    /// data is still as-of-last-full-fetch.
    mutating func applyDelta(
        upserted: [ProviderUsageEnvelope],
        deletedRecordNames: [String]
    ) {
        for envelope in upserted where !Self.isGhost(envelope.provider) {
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
        for envelope in envelopes where !Self.isGhost(envelope.provider) {
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
    ///
    /// Applies `dropOrphansAndStale` to each device's per-provider bucket
    /// before reconstruction — see that function for the two filter rules.
    func buildDeviceSnapshots() -> [SyncedUsageSnapshot] {
        var result: [SyncedUsageSnapshot] = []
        let allDeviceIDs = Set(self.perProviderByDevice.keys)
            .union(self.legacyByDevice.keys)

        for deviceID in allDeviceIDs {
            if let rawByComposite = self.perProviderByDevice[deviceID],
               !rawByComposite.isEmpty
            {
                let byComposite = Self.dropOrphansAndStale(rawByComposite)
                if byComposite.isEmpty {
                    // All per-provider entries filtered as orphan/stale —
                    // fall back to legacy if available so the device doesn't
                    // disappear entirely.
                    if let legacy = self.legacyByDevice[deviceID] {
                        result.append(legacy)
                    }
                    continue
                }
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

    /// Drop per-provider entries that are almost certainly orphan / stale
    /// records left behind by Mac state transitions:
    ///
    /// **Rule 1 · nil-email-when-real-email-exists.** If two entries share
    /// `providerID` but one has `accountEmail == nil` and the other has a
    /// non-empty email, the nil-email one is dropped. The nil-email record
    /// originates from Mac's pre-OAuth-load early push, or from an upgrade
    /// migration where Codex's account-identity-derivation logic changed
    /// between versions — the new Mac wrote a record under a new composite
    /// key, the old record persists in CloudKit indefinitely. Build 66's
    /// `isGhost` filter only catches all-nil-data envelopes; this catches
    /// records that have data but the wrong identity.
    ///
    /// **Rule 2 · stale relative to device freshness, applied only to
    /// nil-email entries.** Drop entries whose `accountEmail` is nil/empty
    /// AND whose `lastUpdated` lags more than 30 minutes behind the freshest
    /// entry on the same device. Mac refreshes a device's providers in a
    /// coordinated cycle (seconds apart at most); a record stuck >30 min
    /// behind hasn't been touched by Mac in at least one full refresh cycle.
    /// This catches records of providers the user disabled — Mac stops
    /// writing, the CloudKit record persists with its last-known timestamp
    /// until the 0.23 Mac release adds a delete-on-disable hook.
    ///
    /// Real-email entries are always exempt from Rule 2: legit multi-account
    /// providers (e.g. two Codex accounts on the same Mac) can refresh on
    /// independent cadences when one account is hot and the other idle, so
    /// "lagging behind sibling" is normal. Mac always assigns an email to
    /// such accounts (that's what makes them legit-multi-account), so the
    /// real-email gate is the right discriminator.
    ///
    /// Both rules apply at read time, not write time, so:
    /// - Incremental delta updates cannot accidentally trim freshly-arrived
    ///   peer records that briefly look "stale" before the cycle completes.
    /// - The cache holds the raw zone state; only the displayed view is
    ///   filtered.
    /// - Toggling Mac on/off clears stale records as soon as Mac resumes
    ///   writing (deviceFreshest moves forward, stale cutoff slides up).
    static func dropOrphansAndStale(
        _ byComposite: [String: ProviderUsageSnapshot]
    ) -> [String: ProviderUsageSnapshot] {
        guard !byComposite.isEmpty else { return [:] }

        // Rule 1: group by providerID; drop nil-email when sibling has email.
        var byProviderID: [String: [String]] = [:]
        for (key, provider) in byComposite {
            byProviderID[provider.providerID, default: []].append(key)
        }
        var keptKeys = Set<String>()
        for (_, keys) in byProviderID {
            let hasRealEmail = keys.contains { key in
                guard let email = byComposite[key]?.accountEmail else { return false }
                return !email.isEmpty
            }
            for key in keys {
                guard let provider = byComposite[key] else { continue }
                let hasEmail = !(provider.accountEmail ?? "").isEmpty
                // Keep if either: there's no sibling with email (so this is
                // a legitimately accountless provider, e.g. Claude/Cursor),
                // OR this entry itself has the email.
                if !hasRealEmail || hasEmail {
                    keptKeys.insert(key)
                }
            }
        }
        let afterOrphanDrop = byComposite.filter { keptKeys.contains($0.key) }

        // Rule 2: TTL on nil-email entries only, relative to device freshest.
        guard let deviceFreshest = afterOrphanDrop.values
            .map({ $0.lastUpdated }).max()
        else { return afterOrphanDrop }
        // 30 minutes: a Mac refresh cycle typically completes within seconds
        // for an active provider, and the slowest known cadence (idle
        // browser-cookie providers) is well under 30 min. Anything older is
        // a stuck record. Don't tighten without checking the slowest cadence
        // a real provider can hit in production.
        let staleCutoff = deviceFreshest.addingTimeInterval(-30 * 60)
        return afterOrphanDrop.filter { _, provider in
            let hasEmail = !(provider.accountEmail ?? "").isEmpty
            // Real-email entries are immune from TTL — they represent legit
            // distinct accounts that may refresh on independent cadences.
            return hasEmail || provider.lastUpdated >= staleCutoff
        }
    }

    // MARK: - Helpers

    /// Composite bucket key for per-provider entries within a single device.
    ///
    /// **WIRE CONTRACT · must match 3 peer sites byte-for-byte:**
    /// - `CloudSyncManager.perProviderRecordName` (CloudKit record-name)
    /// - `ProviderSnapshotModel.makeCompositeKey` (SwiftData composite)
    /// - `SnapshotCache.splitRecordName` (the inverse parser below)
    ///
    /// The `"_"` sentinel for nil `accountEmail` is the same at every site.
    /// Build 67 hardening: an earlier version used `""` in one of these,
    /// causing `deleteByRecordName` to miss SwiftData rows and per-provider
    /// CloudKit records to diverge silently. If you change the sentinel
    /// byte, change **all four sites** in the same commit.
    ///
    /// (Aside: `CloudSyncReader.mergeSnapshots` uses `""` for its own
    /// in-function grouping key — that key never leaves the function and
    /// doesn't participate in this cross-layer contract.)
    static func compositeKey(for provider: ProviderUsageSnapshot) -> String {
        "\(provider.providerID)|\(provider.accountEmail ?? "_")"
    }

    /// Parses a CloudKit recordName of the form
    /// `"deviceID|providerID|accountEmail"` back into `(deviceID, composite)`.
    /// Returns nil on malformed input — caller should skip such records.
    ///
    /// **Inverse of `CloudSyncManager.perProviderRecordName`.** Both must
    /// use `|` as separator and expect exactly 3 components. Any layout
    /// change on one side requires the symmetric change here.
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
    ///
    /// The `"legacy:"` prefix is a deliberate UUID-collision guard — real
    /// `deviceID`s are UUIDs (e.g. `"F4E7A42B-…"`); no legitimate UUID
    /// starts with `"legacy:"`. This lets both stores distinguish
    /// KVS-originated (pre-Build-42) rows from CloudKit-originated rows
    /// without an extra flag, and the next authoritative full-fetch
    /// overwrites them with real zone-backed `deviceID`s.
    static func syntheticDeviceID(from snapshot: SyncedUsageSnapshot) -> String {
        "legacy:" + snapshot.deviceName
    }
}
