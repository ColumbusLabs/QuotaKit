import CodexBarSync
import Foundation
import Observation

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

/// ViewModel for the iOS app. Fetches usage snapshots from CloudKit (all devices),
/// merges them, and exposes the result to SwiftUI views. Falls back to KVS for
/// backward compatibility with older Mac app versions.
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

    private let reader: CloudSyncReader
    private var isObservingKVS = false

    init(reader: CloudSyncReader = CloudSyncReader()) {
        self.reader = reader
        // Load any existing KVS snapshot immediately (fast, synchronous)
        if let kvsSnapshot = reader.latestKVSSnapshot() {
            self.snapshot = kvsSnapshot
            self.deviceSnapshots = [kvsSnapshot]
            self.syncStatus = .synced(ago: Date().timeIntervalSince(kvsSnapshot.syncTimestamp))
        }
    }

    /// Starts observing: fetches from CloudKit, sets up KVS fallback, and configures subscription.
    func startObserving() {
        // 1. Start KVS observation (backward compat with old Mac apps)
        if !isObservingKVS {
            isObservingKVS = true
            reader.startKVSObserving { [weak self] result in
                guard let self else { return }
                // Only use KVS data if we have no CloudKit data yet
                if self.deviceSnapshots.isEmpty {
                    switch result {
                    case .success(let kvsSnapshot):
                        self.snapshot = kvsSnapshot
                        self.deviceSnapshots = [kvsSnapshot]
                        self.syncStatus = .synced(ago: 0)
                    case .empty:
                        break
                    case .quotaExceeded:
                        self.syncStatus = .error(message: String(localized: "iCloud storage quota exceeded"))
                    case .accountChanged:
                        self.snapshot = self.reader.latestKVSSnapshot()
                    case .initialSync:
                        break
                    }
                }
            }
        }

        // 2. Fetch from CloudKit (primary)
        Task {
            await self.fetchFromCloudKit()
        }

        // 3. Set up CloudKit subscription for push notifications
        Task {
            let result = await self.reader.setupSubscriptionWithDiagnostics()
            await MainActor.run {
                switch result {
                case .created:
                    PushDiagnosticStore.shared.recordSubscriptionCreated()
                case .alreadyExists:
                    PushDiagnosticStore.shared.recordSubscriptionAlreadyExists()
                case .failed(let message):
                    PushDiagnosticStore.shared.recordSubscriptionFailure(
                        NSError(
                            domain: "CodexBar.PushDiagnostic",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: message]))
                }
            }
        }
    }

    /// Forces a fresh CloudKit subscription setup. For the Push Diagnostic view.
    func forceResubscribe() async {
        let result = await self.reader.setupSubscriptionWithDiagnostics()
        switch result {
        case .created:
            PushDiagnosticStore.shared.recordSubscriptionCreated()
        case .alreadyExists:
            PushDiagnosticStore.shared.recordSubscriptionAlreadyExists()
        case .failed(let message):
            PushDiagnosticStore.shared.recordSubscriptionFailure(
                NSError(
                    domain: "CodexBar.PushDiagnostic",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }

    /// Fetches latest data from CloudKit, merges all device snapshots.
    func fetchFromCloudKit() async {
        self.syncStatus = .syncing

        let result = await reader.fetchAllDeviceSnapshots()

        switch result {
        case .success(let snapshots):
            self.deviceSnapshots = snapshots
            self.usingKVSFallback = false
            // Debug: log utilization data presence
            for snap in snapshots {
                for p in snap.providers {
                    let histCount = p.utilizationHistory?.count ?? 0
                    let entryCount = p.utilizationHistory?.reduce(0) { $0 + $1.entries.count } ?? 0
                    if histCount > 0 {
                        print("[CodexBar] Provider \(p.providerName): \(histCount) utilization series, \(entryCount) total entries")
                    } else {
                        print("[CodexBar] Provider \(p.providerName): NO utilization data")
                    }
                }
            }
            if let merged = CloudSyncReader.mergeSnapshots(snapshots) {
                self.snapshot = merged
                self.syncStatus = .synced(ago: Date().timeIntervalSince(merged.syncTimestamp))
            } else {
                self.syncStatus = .incompatibleData
            }

        case .empty:
            // No CloudKit data — fall back to KVS if available
            if let kvsSnapshot = reader.latestKVSSnapshot() {
                self.snapshot = kvsSnapshot
                self.deviceSnapshots = [kvsSnapshot]
                self.usingKVSFallback = true
                self.syncStatus = .synced(ago: Date().timeIntervalSince(kvsSnapshot.syncTimestamp))
            } else {
                self.syncStatus = .noData
            }

        case .error(let cloudError):
            // CloudKit failed — fall back to KVS if available
            if self.snapshot == nil, let kvsSnapshot = reader.latestKVSSnapshot() {
                self.snapshot = kvsSnapshot
                self.deviceSnapshots = [kvsSnapshot]
            }
            self.syncStatus = .error(message: cloudError.description)
        }
    }

    /// Force-refreshes data from CloudKit.
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
}
