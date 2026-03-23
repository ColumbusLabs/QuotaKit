import CloudKit
import Foundation
#if canImport(OSLog)
import OSLog
#endif
#if canImport(Security)
import Security
#endif

// MARK: - Sync Push Protocol

/// Protocol for pushing usage snapshots, enabling mock injection in tests.
public protocol SyncPushing: Sendable {
    @discardableResult
    func pushSnapshot(_ snapshot: SyncedUsageSnapshot) async -> SyncPushResult
}

public struct SyncPushResult: Sendable, Equatable {
    public let succeeded: Bool
    public let message: String?

    public init(succeeded: Bool, message: String? = nil) {
        self.succeeded = succeeded
        self.message = message
    }

    public static let success = SyncPushResult(succeeded: true)

    public static func failure(_ message: String) -> SyncPushResult {
        SyncPushResult(succeeded: false, message: message)
    }
}

// MARK: - Sync Error

/// Detailed sync error with user-readable descriptions.
public enum CloudSyncError: Error, Sendable, CustomStringConvertible {
    case networkUnavailable
    case notAuthenticated
    case quotaExceeded
    case serverError(String)
    case decodingFailed(String)
    case unknown(String)

    public var description: String {
        switch self {
        case .networkUnavailable:
            "Network unavailable"
        case .notAuthenticated:
            "iCloud account not signed in"
        case .quotaExceeded:
            "iCloud storage quota exceeded"
        case .serverError(let msg):
            "Server error: \(msg)"
        case .decodingFailed(let msg):
            "Data format error: \(msg)"
        case .unknown(let msg):
            msg
        }
    }

    public init(from ckError: CKError) {
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            self = .networkUnavailable
        case .notAuthenticated:
            self = .notAuthenticated
        case .quotaExceeded:
            self = .quotaExceeded
        case .serverResponseLost, .serviceUnavailable, .requestRateLimited:
            self = .serverError(ckError.localizedDescription)
        default:
            self = .unknown(ckError.localizedDescription)
        }
    }
}

// MARK: - Multi-device Sync Result

/// Result of fetching snapshots from all devices via CloudKit.
public enum MultiDeviceSyncResult: Sendable {
    /// Successfully fetched snapshots from one or more devices.
    case success([SyncedUsageSnapshot])
    /// No device records found in CloudKit.
    case empty
    /// CloudKit operation failed with a specific error.
    case error(CloudSyncError)
}

// MARK: - Legacy KVS Sync Result (backward compatibility)

/// Result of an iCloud KVS sync event (kept for transition period).
public enum SyncResult: Sendable {
    case success(SyncedUsageSnapshot)
    case empty
    case quotaExceeded
    case accountChanged
    case initialSync
}

// MARK: - Cloud Sync Manager

/// Manages reading/writing usage snapshots via CloudKit (primary) and KVS (legacy fallback).
///
/// - Mac side calls `pushSnapshot(_:)` to save a per-device record to CloudKit.
/// - iOS side calls `fetchAllDeviceSnapshots()` to read all device records and merge.
/// - KVS dual-write is maintained during the transition period for older app versions.
public final class CloudSyncManager: SyncPushing, @unchecked Sendable {
    public static let shared = CloudSyncManager()

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Legacy KVS
    private let kvsStore = NSUbiquitousKeyValueStore.default
    private var kvsObserverToken: NSObjectProtocol?

    #if canImport(OSLog)
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.o1xhack.codexbar",
        category: "cloudkit-sync")
    #endif

    private init() {
        self.container = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
        self.privateDatabase = container.privateCloudDatabase
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - CloudKit Write (Mac side)

    /// Pushes the latest usage snapshot to CloudKit as a per-device record,
    /// and also writes to KVS for backward compatibility with older iOS versions.
    @discardableResult
    public func pushSnapshot(_ snapshot: SyncedUsageSnapshot) async -> SyncPushResult {
        guard let data = try? encoder.encode(snapshot) else {
            let message = "iCloud sync failed: could not encode the snapshot payload."
            self.logError(message)
            return .failure(message)
        }

        // 1. Push to CloudKit (primary)
        let result = await self.pushToCloudKit(snapshot: snapshot, data: data)

        // 2. Also push to KVS for backward compatibility with older iOS versions
        self.pushToKVS(data: data)

        return result
    }

    private func pushToCloudKit(snapshot: SyncedUsageSnapshot, data: Data) async -> SyncPushResult {
        guard let deviceID = snapshot.deviceID else {
            let message = "iCloud sync failed: no device ID in snapshot."
            self.logError(message)
            return .failure(message)
        }

        let recordID = CKRecord.ID(recordName: deviceID)

        // Fetch existing record to avoid conflicts, or create new
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CloudSyncConstants.recordType, recordID: recordID)
        } catch {
            let syncError = CloudSyncError(from: error as? CKError ?? CKError(.internalError))
            self.logError("CloudKit fetch failed: \(syncError.description)")
            return .failure(syncError.description)
        }

        record["deviceName"] = snapshot.deviceName as CKRecordValue
        record["deviceID"] = deviceID as CKRecordValue
        record["appVersion"] = (snapshot.appVersion ?? "") as CKRecordValue
        record["syncTimestamp"] = snapshot.syncTimestamp as CKRecordValue
        record["payload"] = data as CKRecordValue

        do {
            try await privateDatabase.save(record)
            self.logInfo("Pushed snapshot to CloudKit", metadata: [
                "deviceID": deviceID,
                "providers": "\(snapshot.providers.count)",
                "bytes": "\(data.count)",
            ])
            return .success
        } catch let error as CKError {
            let syncError = CloudSyncError(from: error)
            self.logError("CloudKit save failed: \(syncError.description)")
            return .failure(syncError.description)
        } catch {
            self.logError("CloudKit save failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - CloudKit Read (iOS side)

    /// Fetches usage snapshots from all devices via CloudKit.
    public func fetchAllDeviceSnapshots() async -> MultiDeviceSyncResult {
        let query = CKQuery(
            recordType: CloudSyncConstants.recordType,
            predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "syncTimestamp", ascending: false)]

        do {
            let (matchResults, _) = try await privateDatabase.records(matching: query)

            var snapshots: [SyncedUsageSnapshot] = []
            for (recordID, result) in matchResults {
                switch result {
                case .success(let record):
                    if let data = record["payload"] as? Data,
                       let snapshot = try? decoder.decode(SyncedUsageSnapshot.self, from: data)
                    {
                        snapshots.append(snapshot)
                    } else {
                        self.logError("Failed to decode snapshot from record \(recordID.recordName)")
                    }
                case .failure(let error):
                    self.logError("Failed to fetch record \(recordID.recordName): \(error.localizedDescription)")
                }
            }

            if snapshots.isEmpty {
                self.logInfo("CloudKit query returned no decodable snapshots")
                return .empty
            }

            self.logInfo("Fetched snapshots from CloudKit", metadata: [
                "devices": "\(snapshots.count)",
            ])
            return .success(snapshots)
        } catch let error as CKError {
            let syncError = CloudSyncError(from: error)
            self.logError("CloudKit query failed: \(syncError.description)")
            return .error(syncError)
        } catch {
            self.logError("CloudKit query failed: \(error.localizedDescription)")
            return .error(.unknown(error.localizedDescription))
        }
    }

    // MARK: - CloudKit Subscription (iOS side)

    /// Sets up a CloudKit subscription to receive push notifications when device records change.
    /// Call this once during app initialization on iOS.
    public func setupSubscription() async throws {
        let subscription = CKQuerySubscription(
            recordType: CloudSyncConstants.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: CloudSyncConstants.subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion])

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent push
        subscription.notificationInfo = notificationInfo

        do {
            try await privateDatabase.save(subscription)
            self.logInfo("CloudKit subscription set up successfully")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Subscription may already exist — that's fine
            self.logInfo("CloudKit subscription already exists, skipping")
        }
    }

    // MARK: - Legacy KVS (backward compatibility)

    /// Fetches the latest snapshot from KVS (fallback for when CloudKit has no data).
    public func fetchKVSSnapshot() -> SyncedUsageSnapshot? {
        guard let data = kvsStore.data(forKey: CloudSyncConstants.kvsSnapshotKey) else { return nil }
        return try? decoder.decode(SyncedUsageSnapshot.self, from: data)
    }

    @discardableResult
    public func synchronizeKVSStore() -> Bool {
        let result = kvsStore.synchronize()
        if !result {
            self.logError("iCloud Key-Value Store synchronize() returned unavailable")
        }
        return result
    }

    /// Starts observing KVS changes (backward compat with older Mac apps that only write KVS).
    public func startKVSObserving(handler: @escaping @MainActor (SyncResult) -> Void) {
        self.stopKVSObserving()
        self.kvsObserverToken = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvsStore,
            queue: .main)
        { [weak self] notification in
            let result = self?.parseKVSSyncResult(from: notification) ?? .empty
            Task { @MainActor in
                handler(result)
            }
        }
        _ = self.synchronizeKVSStore()
    }

    /// Stops observing KVS changes.
    public func stopKVSObserving() {
        guard let kvsObserverToken else { return }
        NotificationCenter.default.removeObserver(kvsObserverToken)
        self.kvsObserverToken = nil
    }

    // MARK: - Deprecated compatibility shims

    /// Legacy fetch — reads from KVS. Prefer `fetchAllDeviceSnapshots()` for CloudKit.
    public func fetchSnapshot() -> SyncedUsageSnapshot? {
        fetchKVSSnapshot()
    }

    /// Legacy observe — uses KVS. Prefer CloudKit subscription for real-time updates.
    public func startObserving(handler: @escaping @MainActor (SyncResult) -> Void) {
        startKVSObserving(handler: handler)
    }

    /// Legacy stop — stops KVS observation.
    public func stopObserving() {
        stopKVSObserving()
    }

    /// Legacy synchronize — triggers KVS sync.
    @discardableResult
    public func synchronizeStore() -> Bool {
        synchronizeKVSStore()
    }

    // MARK: - Private

    private func pushToKVS(data: Data) {
        guard data.count <= CloudSyncConstants.maxKVSPayloadBytes else {
            self.logError("Snapshot too large for KVS fallback (\(data.count) bytes)")
            return
        }
        kvsStore.set(data, forKey: CloudSyncConstants.kvsSnapshotKey)
        kvsStore.synchronize()
    }

    private func parseKVSSyncResult(from notification: Notification) -> SyncResult {
        let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int

        switch reason {
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            return .quotaExceeded
        case NSUbiquitousKeyValueStoreAccountChange:
            if let snapshot = fetchKVSSnapshot() {
                return .success(snapshot)
            }
            return .accountChanged
        case NSUbiquitousKeyValueStoreInitialSyncChange:
            if let snapshot = fetchKVSSnapshot() {
                return .success(snapshot)
            }
            return .initialSync
        default:
            if let snapshot = fetchKVSSnapshot() {
                return .success(snapshot)
            }
            return .empty
        }
    }

    private func logInfo(_ message: String, metadata: [String: String]? = nil) {
        #if canImport(OSLog)
        if let metadata, !metadata.isEmpty {
            let rendered = metadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            logger.info("\(message, privacy: .public) \(rendered, privacy: .public)")
        } else {
            logger.info("\(message, privacy: .public)")
        }
        #endif
    }

    private func logError(_ message: String) {
        #if canImport(OSLog)
        logger.error("\(message, privacy: .public)")
        #endif
    }
}
