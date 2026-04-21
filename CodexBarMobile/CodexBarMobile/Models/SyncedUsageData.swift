import CloudKit
import CodexBarSync
import Foundation
import Observation
import SwiftData

/// Detailed sync status for UI display.
enum SyncStatus: Sendable, Equatable {
    /// Successfully synced, showing how long ago.
    case synced(ago: TimeInterval)
    /// Currently fetching data from CloudKit.
    case syncing
    /// Sync failed with a specific error message.
    case error(message: String)
    /// No Mac data found — Mac app may not be running or sync is not configured.
    case noData
    /// CloudKit returned data but it couldn't be decoded (version mismatch).
    case incompatibleData

    var isError: Bool {
        switch self {
        case .error, .noData, .incompatibleData: true
        default: false
        }
    }
}

/// ViewModel for the iOS app. Fetches usage snapshots from CloudKit (all
/// devices), maintains an in-memory `SnapshotCache` with explicit per-zone
/// slots, and exposes the merged view to SwiftUI. Falls back to KVS for
/// older Mac app versions.
///
/// See `Research/011-mac-sync-incremental-v2.md` for the cache design + the
/// multi-device traces that fixes the v1 P6/P7 regression.
@Observable
@MainActor
final class SyncedUsageData {
    /// Merged snapshot from all devices (primary data source for views).
    var snapshot: SyncedUsageSnapshot?

    /// Per-device snapshots before merging (for debug/display).
    var deviceSnapshots: [SyncedUsageSnapshot] = []

    /// Current sync status with detailed error information.
    var syncStatus: SyncStatus = .noData

    /// True when data comes from KVS fallback (old Mac app without CloudKit).
    var usingKVSFallback: Bool = false

    /// Legacy error string (kept for backward compat with existing UI).
    var lastSyncError: String? {
        switch syncStatus {
        case .error(let message): message
        case .noData: String(localized: "No Mac data found")
        case .incompatibleData: String(localized: "Data format incompatible. Please update Mac app.")
        default: nil
        }
    }

    /// Number of Mac devices contributing data.
    var deviceCount: Int { deviceSnapshots.count }

    // MARK: - Private state

    private let reader: CloudSyncReader
    private var isObservingKVS = false
    private var isObservingSilentPush = false

    /// In-memory zone-separated cache. Mutated only on MainActor. Never
    /// persisted — cold start rehydrates via SwiftData (P3).
    private var cache = SnapshotCache()

    // MARK: - Lifecycle

    init(reader: CloudSyncReader = CloudSyncReader()) {
        self.reader = reader

        // P3: hydrate from SwiftData so the Cost tab shows something
        // immediately on cold start. We seed into legacyByDevice bucket —
        // SwiftData doesn't track zone-of-origin.
        let context = ModelContainerFactory.sharedMainContext()
        if let hydrated = Self.hydrateFromSwiftData(context: context) {
            self.cache.seedFromColdStart(hydrated.devices)
            self.republishFromCache()
            return
        }

        // KVS fallback for legacy Mac apps.
        if let kvsSnapshot = reader.latestKVSSnapshot() {
            self.cache.seedFromColdStart([kvsSnapshot])
            self.republishFromCache()
        }
    }

    /// Reads SwiftData's per-device rows + the standard merge. Returns nil
    /// when the store is empty or any decode fails.
    private static func hydrateFromSwiftData(
        context: ModelContext
    ) -> (devices: [SyncedUsageSnapshot], merged: SyncedUsageSnapshot)? {
        do {
            let devices = try SwiftDataBridge.readAllDeviceSnapshots(from: context)
            guard !devices.isEmpty, let merged = CloudSyncReader.mergeSnapshots(devices) else {
                return nil
            }
            return (devices, merged)
        } catch {
            print("[CodexBar SwiftData] hydrate on launch failed: \(error)")
            return nil
        }
    }

    /// Starts observing: runs a fresh full fetch, wires KVS + silent push.
    func startObserving() {
        // 1. Start KVS observation (backward compat with old Mac apps that
        //    only write KVS, pre-CloudKit).
        if !isObservingKVS {
            isObservingKVS = true
            reader.startKVSObserving { [weak self] result in
                guard let self else { return }
                // KVS is a last-resort fallback; only use it if we have no
                // CloudKit data at all.
                if self.cache.legacyByDevice.isEmpty, self.cache.perProviderByDevice.isEmpty {
                    switch result {
                    case .success(let kvsSnapshot):
                        self.cache.seedFromColdStart([kvsSnapshot])
                        self.republishFromCache()
                    case .empty, .initialSync:
                        break
                    case .quotaExceeded:
                        self.syncStatus = .error(message: String(localized: "iCloud storage quota exceeded"))
                    case .accountChanged:
                        if let kvsSnapshot = self.reader.latestKVSSnapshot() {
                            self.cache.seedFromColdStart([kvsSnapshot])
                            self.republishFromCache()
                        }
                    }
                }
            }
        }

        // 2. Subscribe to silent-push-triggered incremental refresh.
        //    AppDelegate posts .codexBarProviderZoneDidChange on every
        //    DeviceProvidersZone push.
        if !isObservingSilentPush {
            isObservingSilentPush = true
            NotificationCenter.default.addObserver(
                forName: .codexBarProviderZoneDidChange,
                object: nil,
                queue: .main)
            { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshIncremental()
                }
            }
        }

        // 3. Fetch from CloudKit (primary, full fetch).
        Task {
            await self.fetchFromCloudKit()
        }
    }

    // MARK: - Full fetch (CKQuery on both zones)

    /// Runs a full fetch against BOTH zones, rebuilds the cache from the
    /// result, and republishes. Called on app launch, pull-to-refresh, and
    /// as a fallback when the incremental path errors out.
    func fetchFromCloudKit() async {
        self.syncStatus = .syncing

        // Fire both zone queries in parallel (independent network I/O).
        async let perProviderResult = reader.fetchPerProviderDeviceSnapshots()
        async let legacyResult = reader.fetchLegacyDeviceSnapshots()

        let per = await perProviderResult
        let legacy = await legacyResult

        // Unpack results. Either zone may be empty (brand-new iPhone, or
        // pre-P4 Macs). Only a hard error from BOTH is fatal.
        var perProviderSnapshots: [SyncedUsageSnapshot] = []
        var legacySnapshots: [SyncedUsageSnapshot] = []
        var firstError: CloudSyncError?

        switch per {
        case .success(let snaps): perProviderSnapshots = snaps
        case .empty: break
        case .error(let e): firstError = e
        }
        switch legacy {
        case .success(let snaps): legacySnapshots = snaps
        case .empty: break
        case .error(let e): firstError = firstError ?? e
        }

        // Replace cache atomically with fresh data from both zones. The
        // single `replaceFromFullFetch` call can't interleave with a silent
        // push handler mid-mutation — @MainActor serializes, and there's no
        // `await` between building the local value and writing it.
        self.cache.replaceFromFullFetch(
            perProviderSnapshots: perProviderSnapshots,
            legacySnapshots: legacySnapshots)

        self.usingKVSFallback = false

        // Derive + publish.
        let deviceSnapshots = self.cache.buildDeviceSnapshots()
        self.deviceSnapshots = deviceSnapshots

        if deviceSnapshots.isEmpty {
            // Totally empty cloud result. Last-resort KVS fallback.
            if let kvsSnapshot = reader.latestKVSSnapshot() {
                self.cache.seedFromColdStart([kvsSnapshot])
                self.usingKVSFallback = true
                self.republishFromCache()
                return
            }
            if let firstError {
                self.syncStatus = .error(message: firstError.description)
            } else {
                self.syncStatus = .noData
            }
            self.snapshot = nil
            return
        }

        if let merged = CloudSyncReader.mergeSnapshots(deviceSnapshots) {
            self.snapshot = merged
            self.syncStatus = .synced(ago: Date().timeIntervalSince(merged.syncTimestamp))

            // Persist the merged per-device view to SwiftData for next cold
            // start (P3 hydrate). This seeds the "legacy bucket" of the
            // cache at next launch — safe because the next full fetch
            // overwrites with authoritative zone attribution.
            let context = ModelContainerFactory.sharedMainContext()
            CloudSyncReader.persistToSwiftData(
                deviceSnapshots: deviceSnapshots,
                merged: merged,
                context: context)
        } else {
            self.syncStatus = .incompatibleData
        }
    }

    // MARK: - Incremental fetch (silent push → cache update)

    /// Apply a change-token delta for `DeviceProvidersZone` to the cache,
    /// then republish. Fired from the silent-push observer. Legacy bucket
    /// is NEVER touched by this path.
    func refreshIncremental() async {
        let zoneName = CloudSyncConstants.providerZoneName
        let context = ModelContainerFactory.sharedMainContext()

        // 1. Load persisted token.
        let storedToken: CKServerChangeToken?
        do {
            if let data = try SwiftDataBridge.loadChangeToken(
                forZone: zoneName, from: context)
            {
                storedToken = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: CKServerChangeToken.self, from: data)
            } else {
                storedToken = nil
            }
        } catch {
            print("[CodexBar Sync v2] token unarchive failed: \(error)")
            storedToken = nil
        }

        // 2. Fetch delta.
        var delta = await reader.fetchPerProviderZoneChanges(since: storedToken)

        // 3. Handle token expiry: clear + retry once with nil. The server's
        //    nil-token reply replays every record currently in the zone, so
        //    we treat it as a FULL replacement of the per-provider bucket
        //    (equivalent to a full fetch of the new zone).
        if delta.tokenExpired {
            try? SwiftDataBridge.saveChangeToken(
                forZone: zoneName, tokenData: nil, context: context)
            delta = await reader.fetchPerProviderZoneChanges(since: nil)
            if !delta.tokenExpired, !delta.zoneMissing {
                self.cache.replacePerProviderFromReplay(delta.upserted)
            }
        } else if delta.zoneMissing {
            // No zone yet — nothing to apply. The priority merge will fall
            // through to the legacy bucket. This is normal before any Mac
            // has upgraded to P4.
        } else {
            // Normal incremental apply. Only touches perProviderByDevice.
            self.cache.applyDelta(
                upserted: delta.upserted,
                deletedRecordNames: delta.deletedRecordNames)
        }

        // 4. Persist the new token.
        if let newToken = delta.newToken {
            do {
                let tokenData = try NSKeyedArchiver.archivedData(
                    withRootObject: newToken, requiringSecureCoding: true)
                try SwiftDataBridge.saveChangeToken(
                    forZone: zoneName, tokenData: tokenData, context: context)
            } catch {
                print("[CodexBar Sync v2] token persist failed: \(error)")
            }
        }

        // 5. Republish merged view.
        self.republishFromCache()
    }

    // MARK: - Republish helper

    /// Derive the published state from the current cache. Called after every
    /// mutation (full fetch, incremental delta, cold-start seed).
    private func republishFromCache() {
        let deviceSnapshots = self.cache.buildDeviceSnapshots()
        self.deviceSnapshots = deviceSnapshots

        if deviceSnapshots.isEmpty {
            self.snapshot = nil
            if case .syncing = self.syncStatus {
                // don't clobber an in-flight syncing state
            } else {
                self.syncStatus = .noData
            }
            return
        }
        if let merged = CloudSyncReader.mergeSnapshots(deviceSnapshots) {
            self.snapshot = merged
            self.syncStatus = .synced(ago: Date().timeIntervalSince(merged.syncTimestamp))
        } else {
            self.syncStatus = .incompatibleData
        }
    }

    // MARK: - Public API

    /// Force-refreshes data from CloudKit (full fetch).
    func refresh() async {
        await fetchFromCloudKit()
    }

    /// Returns the age of the last sync in a human-readable format, or nil if no sync exists.
    var syncAge: String? {
        guard let timestamp = snapshot?.syncTimestamp else { return nil }
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 {
            return String(localized: "Just now")
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes.formatted()) \(String(localized: "min ago"))"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours.formatted())\(String(localized: "h ago"))"
        } else {
            let days = Int(interval / 86400)
            return "\(days.formatted())\(String(localized: "d ago"))"
        }
    }

    /// Names of all Mac devices contributing data.
    var deviceNames: [String] {
        deviceSnapshots.map(\.deviceName)
    }

    /// Stable identity for view-layer cache invalidation (Contract C3).
    /// Returns nil when there is no merged snapshot yet.
    var snapshotIdentityKey: SnapshotIdentityKey? {
        guard let snapshot else { return nil }
        let providers = snapshot.providers
        let latest = providers.map(\.lastUpdated).max() ?? snapshot.syncTimestamp
        return SnapshotIdentityKey.make(
            providerIDs: providers.map(\.providerID),
            lastUpdated: latest)
    }
}
