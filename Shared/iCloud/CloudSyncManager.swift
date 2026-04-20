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

    /// Per-provider incremental write (P4). The `pushSnapshot` path keeps
    /// legacy-zone consumers happy; this one populates the new
    /// `DeviceProvidersZone` so future iOS builds can consume changes without
    /// downloading the whole monolithic blob.
    @discardableResult
    func pushPerProviderRecords(
        _ envelopes: [ProviderUsageEnvelope]
    ) async -> SyncPushResult
}

extension SyncPushing {
    /// Default no-op so existing test doubles don't have to implement the new
    /// method. CloudSyncManager overrides with the real CloudKit write.
    public func pushPerProviderRecords(
        _: [ProviderUsageEnvelope]
    ) async -> SyncPushResult {
        .success
    }
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
///
/// **Custom zone:** All `DeviceSnapshot` records live in a custom record zone
/// (`CloudSyncConstants.customZoneName`), not the default zone. This is required for
/// CloudKit silent push notifications via `CKRecordZoneSubscription` to fire reliably
/// on the private database — the default zone of the private database does not deliver
/// silent push reliably (see `apple/sample-cloudkit-privatedb-sync` and Apple's
/// "Remote Records" documentation).
public final class CloudSyncManager: SyncPushing, @unchecked Sendable {
    public static let shared = CloudSyncManager()

    /// CloudKit container and database — optional because CKContainer(identifier:) will
    /// hard-crash (_os_crash / SIGTRAP) if the CloudKit entitlement is missing or misconfigured.
    /// We probe for the entitlement at init time; if absent, CloudKit is disabled and we use KVS only.
    private let _container: CKContainer?
    private let _privateDatabase: CKDatabase?
    private let cloudKitAvailable: Bool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// The custom record zone where all `DeviceSnapshot` records live.
    /// See class doc-comment for why a custom zone is required.
    private let customZone = CKRecordZone(zoneName: CloudSyncConstants.customZoneName)

    /// Per-provider record zone (P4). One `DeviceProviderSnapshot` record per
    /// (deviceID, providerID, accountEmail) — see
    /// `CodexBarMobile/Research/010-mac-per-provider-cloudkit.md`.
    private let providerZone = CKRecordZone(zoneName: CloudSyncConstants.providerZoneName)

    // Legacy KVS
    private let kvsStore = NSUbiquitousKeyValueStore.default
    private var kvsObserverToken: NSObjectProtocol?

    #if canImport(OSLog)
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.o1xhack.codexbar",
        category: "cloudkit-sync")
    #endif

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        // Probe for CloudKit entitlement before touching CKContainer.
        var available = false
        #if os(macOS)
        // SecTaskCopyValueForEntitlement reads the actual code-signing entitlements.
        if let task = SecTaskCreateFromSelf(nil) {
            let value = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.icloud-services" as CFString, nil)
            if let services = value as? [String], services.contains("CloudKit") {
                available = true
            }
        }
        #else
        // iOS entitlements are guaranteed by the provisioning profile.
        available = true
        #endif
        if available {
            let c = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
            self._container = c
            self._privateDatabase = c.privateCloudDatabase
        } else {
            self._container = nil
            self._privateDatabase = nil
        }
        self.cloudKitAvailable = available
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

        // 1. Push to CloudKit (primary) — skipped if entitlement not available
        let result: SyncPushResult
        if cloudKitAvailable {
            result = await self.pushToCloudKit(snapshot: snapshot, data: data)
        } else {
            self.logInfo("CloudKit not available (missing entitlement), using KVS only")
            result = .success
        }

        // 2. Also push to KVS for backward compatibility with older iOS versions
        self.pushToKVS(data: data)

        return result
    }

    /// Ensures the custom record zone exists on the server.
    ///
    /// Uses fetch-then-create pattern: queries the server for the zone, only creates if
    /// missing. This is self-healing across iCloud account switches and server-side
    /// resets — a stale local cache cannot mask a missing server zone (which would
    /// otherwise cause every write to fail with `.zoneNotFound`).
    ///
    /// Cost: one extra zone fetch per call. Cheap enough to call from every push.
    private func ensureCustomZoneExists() async throws {
        // Fast path: zone already exists on server.
        do {
            _ = try await _privateDatabase!.recordZone(for: customZone.zoneID)
            return
        } catch let error as CKError {
            if error.code != .zoneNotFound {
                // Network or other error — propagate, don't silently mask
                throw error
            }
            // Fall through to create
        }

        _ = try await _privateDatabase!.modifyRecordZones(
            saving: [customZone], deleting: [])
        self.logInfo("Custom zone created", metadata: [
            "zone": customZone.zoneID.zoneName,
        ])
    }

    private func pushToCloudKit(snapshot: SyncedUsageSnapshot, data: Data) async -> SyncPushResult {
        guard let deviceID = snapshot.deviceID else {
            let message = "iCloud sync failed: no device ID in snapshot."
            self.logError(message)
            return .failure(message)
        }

        // Ensure the custom zone exists before writing into it. Without this, the first
        // write to a non-existent zone fails with .zoneNotFound.
        do {
            try await ensureCustomZoneExists()
        } catch {
            let syncError = CloudSyncError(from: error as? CKError ?? CKError(.internalError))
            let message = "Failed to create custom zone: \(syncError.description)"
            self.logError(message)
            return .failure(message)
        }

        let recordID = CKRecord.ID(recordName: deviceID, zoneID: customZone.zoneID)

        // Fetch existing record to avoid conflicts, or create new
        let record: CKRecord
        do {
            record = try await _privateDatabase!.record(for: recordID)
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
            try await _privateDatabase!.save(record)
            self.logInfo("Pushed snapshot to CloudKit", metadata: [
                "deviceID": deviceID,
                "providers": "\(snapshot.providers.count)",
                "bytes": "\(data.count)",
            ])
            return .success
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Conflict: re-fetch the server record and retry once
            self.logInfo("CloudKit conflict, retrying with server record")
            guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                return .failure("CloudKit conflict but no server record returned")
            }
            serverRecord["deviceName"] = snapshot.deviceName as CKRecordValue
            serverRecord["deviceID"] = deviceID as CKRecordValue
            serverRecord["appVersion"] = (snapshot.appVersion ?? "") as CKRecordValue
            serverRecord["syncTimestamp"] = snapshot.syncTimestamp as CKRecordValue
            serverRecord["payload"] = data as CKRecordValue
            do {
                try await _privateDatabase!.save(serverRecord)
                self.logInfo("CloudKit conflict resolved, snapshot saved")
                return .success
            } catch {
                let retryError = CloudSyncError(from: error as? CKError ?? CKError(.internalError))
                self.logError("CloudKit retry failed: \(retryError.description)")
                return .failure(retryError.description)
            }
        } catch let error as CKError {
            let syncError = CloudSyncError(from: error)
            self.logError("CloudKit save failed: \(syncError.description)")
            return .failure(syncError.description)
        } catch {
            self.logError("CloudKit save failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - CloudKit Per-Provider Write (Mac side, P4)

    /// Pushes per-provider snapshot records to `DeviceProvidersZone`.
    ///
    /// Each envelope becomes one `DeviceProviderSnapshot` CKRecord keyed by the
    /// composite (`deviceID`, `providerID`, `accountEmail`). Payload is JSON +
    /// zlib-compressed. Legacy zone writes continue via `pushSnapshot`; callers
    /// should treat this as an **additive** write — failure here must not stop
    /// the legacy write from succeeding.
    ///
    /// An empty `envelopes` array is a successful no-op (caller's per-provider
    /// diff produced no changes this cycle).
    @discardableResult
    public func pushPerProviderRecords(
        _ envelopes: [ProviderUsageEnvelope]
    ) async -> SyncPushResult {
        guard !envelopes.isEmpty else { return .success }
        guard cloudKitAvailable, _privateDatabase != nil else {
            return .failure("CloudKit not available")
        }

        do {
            try await ensureProviderZoneExists()
        } catch {
            let syncError = CloudSyncError(from: error as? CKError ?? CKError(.internalError))
            let message = "Failed to create provider zone: \(syncError.description)"
            self.logError(message)
            return .failure(message)
        }

        // Build CKRecords. Any encode/compress failure is surfaced individually
        // but does not abort the whole batch — we still push the records we
        // could build.
        var records: [CKRecord] = []
        var encodeFailures: [String] = []
        for envelope in envelopes {
            do {
                let record = try self.makePerProviderRecord(from: envelope)
                records.append(record)
            } catch {
                encodeFailures.append(
                    "\(envelope.provider.providerID): \(error.localizedDescription)")
                self.logError(
                    "Per-provider encode failed for \(envelope.provider.providerID): " +
                        error.localizedDescription)
            }
        }
        guard !records.isEmpty else {
            return .failure("All per-provider payloads failed to encode")
        }

        // CKModifyRecordsOperation batches in chunks of ≤200. Real users rarely
        // have >30 providers, but chunk defensively anyway so we don't surprise
        // ourselves later.
        let batchSize = 200
        for chunkStart in stride(from: 0, to: records.count, by: batchSize) {
            let chunkEnd = min(chunkStart + batchSize, records.count)
            let chunk = Array(records[chunkStart..<chunkEnd])
            if let failure = await self.saveChunk(chunk) {
                return failure
            }
        }

        self.logInfo("Pushed per-provider records to CloudKit", metadata: [
            "count": "\(records.count)",
            "encodeFailures": "\(encodeFailures.count)",
            "zone": providerZone.zoneID.zoneName,
        ])
        if !encodeFailures.isEmpty {
            // Partial success — surface as a non-fatal warning in the result
            // string so upstream callers can log but continue.
            return SyncPushResult(
                succeeded: true,
                message: "Encoded \(records.count) / failed \(encodeFailures.count)")
        }
        return .success
    }

    /// Ensures `DeviceProvidersZone` exists. Same fetch-first self-heal pattern
    /// as `ensureCustomZoneExists`.
    private func ensureProviderZoneExists() async throws {
        do {
            _ = try await _privateDatabase!.recordZone(for: providerZone.zoneID)
            return
        } catch let error as CKError {
            if error.code != .zoneNotFound { throw error }
        }
        _ = try await _privateDatabase!.modifyRecordZones(
            saving: [providerZone], deleting: [])
        self.logInfo("Provider zone created", metadata: [
            "zone": providerZone.zoneID.zoneName,
        ])
    }

    /// Encodes one envelope into a CKRecord in `DeviceProvidersZone` with a
    /// zlib-compressed JSON payload and all queryable metadata fields set.
    private func makePerProviderRecord(from envelope: ProviderUsageEnvelope) throws -> CKRecord {
        let json = try encoder.encode(envelope)
        let compressed = try PayloadCompression.compress(json)

        let recordName = Self.perProviderRecordName(
            deviceID: envelope.deviceID,
            providerID: envelope.provider.providerID,
            accountEmail: envelope.provider.accountEmail)
        let recordID = CKRecord.ID(recordName: recordName, zoneID: providerZone.zoneID)
        let record = CKRecord(
            recordType: CloudSyncConstants.providerRecordType, recordID: recordID)
        record["deviceID"] = envelope.deviceID as CKRecordValue
        record["deviceName"] = envelope.deviceName as CKRecordValue
        record["providerID"] = envelope.provider.providerID as CKRecordValue
        record["providerName"] = envelope.provider.providerName as CKRecordValue
        // CloudKit coerces nil strings awkwardly — store empty "" and have the
        // reader treat empty as nil. Matches how we already handle `appVersion`
        // in the legacy writer.
        record["accountEmail"] = (envelope.provider.accountEmail ?? "") as CKRecordValue
        record["lastUpdated"] = envelope.provider.lastUpdated as CKRecordValue
        record["encodingVersion"] = CloudSyncConstants.providerPayloadVersion as CKRecordValue
        record["payload"] = compressed as CKRecordValue
        return record
    }

    /// Composite record name matching iOS `ProviderSnapshotModel.makeCompositeKey`.
    /// Stable across pushes so repeated saves overwrite in place.
    public static func perProviderRecordName(
        deviceID: String,
        providerID: String,
        accountEmail: String?
    ) -> String {
        "\(deviceID)|\(providerID)|\(accountEmail ?? "_")"
    }

    /// Sends one batch of provider records via `CKModifyRecordsOperation`. On
    /// success returns `nil`; on hard failure returns a `SyncPushResult` that
    /// the caller should return to the coordinator.
    private func saveChunk(_ records: [CKRecord]) async -> SyncPushResult? {
        do {
            let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.qualityOfService = .utility
            return try await withCheckedThrowingContinuation { continuation in
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: nil)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                self._privateDatabase!.add(op)
            }
        } catch let error as CKError {
            let syncError = CloudSyncError(from: error)
            self.logError("Per-provider batch save failed: \(syncError.description)")
            return .failure(syncError.description)
        } catch {
            self.logError("Per-provider batch save failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - CloudKit Quota Transition Write (Mac side, alert push trigger)

    /// Ensures a given quota push zone exists on the private database.
    /// Same fetch-first pattern as `ensureCustomZoneExists`.
    private func ensureQuotaZoneExists(_ zone: CKRecordZone) async throws {
        do {
            _ = try await _privateDatabase!.recordZone(for: zone.zoneID)
            return
        } catch let error as CKError {
            if error.code != .zoneNotFound { throw error }
        }
        _ = try await _privateDatabase!.modifyRecordZones(
            saving: [zone], deleting: [])
        self.logInfo("\(zone.zoneID.zoneName) created")
    }

    /// Writes a `QuotaTransition` record to a **per-provider × state** CloudKit
    /// zone so iOS receives a visible alert push whose body already includes
    /// the provider's name.
    ///
    /// State **and** provider are both encoded in the zone name — e.g. Codex
    /// depleted goes to `Quota-codex-depletedZone`. iOS pre-creates one
    /// `CKRecordZoneSubscription` per `(provider, state)` pair at app launch,
    /// each with an `alertBody` already formatted as "Codex 会话额度已耗尽" /
    /// "Codex session depleted" / etc. for the iPhone's locale. No subscription
    /// args, no `desiredKeys`, no NotificationServiceExtension — this is purely
    /// the Build 48/52 static-alertBody mechanism that is known to persist
    /// reliably on this container, scaled to `#providers × 2` subscriptions.
    ///
    /// Only fields that already exist in the Production schema are written
    /// (`providerName`, `providerID`, `state`, `transitionAt`, `deviceID`). No
    /// new fields — so no CloudKit Dashboard schema deploy is required.
    ///
    /// `recordName` is derived from `(providerID, hourBucket)` so concurrent
    /// transitions from multiple Macs within the same hour collapse to a
    /// single record per zone (idempotent overwrite). Provider and state are
    /// not part of the name because they are already implied by the zone.
    public func writeQuotaTransition(
        providerName: String,
        providerID: String,
        state: String,
        transitionAt: Date) async -> SyncPushResult
    {
        guard cloudKitAvailable, _privateDatabase != nil else {
            return .failure("CloudKit not available")
        }

        let zoneName = QuotaProviderList.quotaZoneName(
            providerID: providerID, state: state)
        let zone = CKRecordZone(zoneName: zoneName)

        do {
            try await ensureQuotaZoneExists(zone)
        } catch {
            let syncError = CloudSyncError(from: error as? CKError ?? CKError(.internalError))
            return .failure("Failed to create \(zone.zoneID.zoneName): \(syncError.description)")
        }

        let deviceID = self.stableDeviceID()
        let hourBucket = Int(transitionAt.timeIntervalSince1970 / 3600)
        let recordName = "\(providerID)-\(hourBucket)"
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zone.zoneID)

        let record = CKRecord(
            recordType: CloudSyncConstants.quotaTransitionRecordType, recordID: recordID)
        record["providerName"] = providerName as CKRecordValue
        record["providerID"] = providerID as CKRecordValue
        record["state"] = state as CKRecordValue
        record["transitionAt"] = transitionAt as CKRecordValue
        record["deviceID"] = deviceID as CKRecordValue

        do {
            try await _privateDatabase!.save(record)
            self.logInfo("QuotaTransition record written", metadata: [
                "providerName": providerName,
                "state": state,
                "zone": zone.zoneID.zoneName,
                "recordName": recordName,
            ])
            return .success
        } catch let error as CKError where error.code == .serverRecordChanged {
            self.logInfo("QuotaTransition same-hour collision (idempotent overwrite)")
            return .success
        } catch let error as CKError {
            let syncError = CloudSyncError(from: error)
            self.logError("QuotaTransition save failed: \(syncError.description)")
            return .failure(syncError.description)
        } catch {
            self.logError("QuotaTransition save failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    /// Returns a stable UUID for this Mac, persisted across launches in `UserDefaults`.
    /// Mirrors the same key used by `SyncCoordinator`'s record name on the Mac side so
    /// the value is shared across the two writers.
    private func stableDeviceID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: CloudSyncConstants.deviceIDKey) {
            return existing
        }
        let newID = UUID().uuidString
        defaults.set(newID, forKey: CloudSyncConstants.deviceIDKey)
        return newID
    }

    // MARK: - CloudKit Read (iOS side)

    /// Fetches usage snapshots from all devices via CloudKit.
    ///
    /// Reads from BOTH the custom zone (where new builds write) and the default zone
    /// (where old Mac builds may still write during the migration window). Snapshots are
    /// deduped by `deviceID` keeping the most recent `syncTimestamp` per device, so a
    /// freshly-upgraded Mac writing to the custom zone replaces any stale default-zone
    /// record from the same device.
    public func fetchAllDeviceSnapshots() async -> MultiDeviceSyncResult {
        guard cloudKitAvailable, _privateDatabase != nil else {
            return .error(CloudSyncError(from: CKError(.serviceUnavailable)))
        }
        let query = CKQuery(
            recordType: CloudSyncConstants.recordType,
            predicate: NSPredicate(value: true))

        var snapshots: [SyncedUsageSnapshot] = []
        var firstError: CloudSyncError?

        // Read from custom zone (primary, where new builds write).
        // .zoneNotFound is an expected first-run condition — treat it as empty, not error.
        do {
            let (matchResults, _) = try await _privateDatabase!.records(
                matching: query, inZoneWith: customZone.zoneID)
            snapshots.append(contentsOf: self.decodeSnapshots(matchResults, source: "custom"))
        } catch let error as CKError where error.code == .zoneNotFound {
            self.logInfo("Custom zone does not exist yet (first run on this device)")
        } catch let error as CKError {
            firstError = CloudSyncError(from: error)
            self.logError("Custom zone query failed: \(firstError!.description)")
        } catch {
            firstError = .unknown(error.localizedDescription)
            self.logError("Custom zone query failed: \(error.localizedDescription)")
        }

        // Read from default zone (legacy, where old Mac builds still write).
        // This is the migration safety net — once all Macs are on the new build, the
        // default zone is empty and this query returns nothing.
        do {
            let (matchResults, _) = try await _privateDatabase!.records(matching: query)
            snapshots.append(contentsOf: self.decodeSnapshots(matchResults, source: "default"))
        } catch let error as CKError {
            // Only surface this error if the custom-zone read also failed.
            if firstError == nil {
                firstError = CloudSyncError(from: error)
                self.logError("Default zone query failed: \(firstError!.description)")
            } else {
                self.logError("Default zone query also failed: \(error.localizedDescription)")
            }
        } catch {
            if firstError == nil {
                firstError = .unknown(error.localizedDescription)
            }
        }

        // Dedupe by deviceID, keeping the most recent syncTimestamp per device.
        // After Mac upgrades, the custom-zone version of each device will be newer.
        var byDeviceID: [String: SyncedUsageSnapshot] = [:]
        for snapshot in snapshots {
            let key = snapshot.deviceID ?? snapshot.deviceName
            if let existing = byDeviceID[key] {
                if snapshot.syncTimestamp > existing.syncTimestamp {
                    byDeviceID[key] = snapshot
                }
            } else {
                byDeviceID[key] = snapshot
            }
        }
        snapshots = Array(byDeviceID.values)

        // Sort by syncTimestamp descending (newest first), client-side.
        snapshots.sort { $0.syncTimestamp > $1.syncTimestamp }

        if snapshots.isEmpty {
            if let firstError {
                return .error(firstError)
            }
            self.logInfo("CloudKit query returned no decodable snapshots")
            return .empty
        }

        self.logInfo("Fetched snapshots from CloudKit", metadata: [
            "devices": "\(snapshots.count)",
        ])
        return .success(snapshots)
    }

    /// Decodes a CloudKit query match result list into snapshot objects, logging any failures.
    private func decodeSnapshots(
        _ matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
        source: String) -> [SyncedUsageSnapshot]
    {
        var result: [SyncedUsageSnapshot] = []
        for (recordID, queryResult) in matchResults {
            switch queryResult {
            case .success(let record):
                if let data = record["payload"] as? Data,
                   let snapshot = try? decoder.decode(SyncedUsageSnapshot.self, from: data)
                {
                    result.append(snapshot)
                } else {
                    self.logError(
                        "Failed to decode snapshot from \(source) record \(recordID.recordName)")
                }
            case .failure(let error):
                self.logError(
                    "Failed to fetch \(source) record \(recordID.recordName): " +
                        error.localizedDescription)
            }
        }
        return result
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
