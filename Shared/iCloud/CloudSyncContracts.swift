import CloudKit
import Foundation

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
        _ envelopes: [ProviderUsageEnvelope]) async -> SyncPushResult

    /// Delete per-provider records by their composite recordName
    /// (`{deviceID}|{providerID}|{accountEmail-or-_}`). Called when a
    /// provider transitions from enabled → disabled, or when its account
    /// identity drifts (composite key changes between Mac versions). Without
    /// this, stale records accumulate in `DeviceProvidersZone` and surface
    /// on iOS as ghost cards (user-reported on iOS 1.3.0; Build 94 added a
    /// display-time filter as L2; this is L1, the root-cause fix).
    @discardableResult
    func deletePerProviderRecords(
        recordNames: [String]) async -> SyncPushResult

    /// Fetches the recordNames of every per-provider record currently in
    /// `DeviceProvidersZone` whose `deviceID` field matches the caller's
    /// device. Used by `SyncCoordinator` at startup to seed
    /// `lastPushedRecordNames` from the actual CloudKit state, so L1
    /// cleanup can detect and delete records pushed by previous Mac
    /// process incarnations (e.g. mock entries left stranded after the
    /// user toggled mock injection off and restarted Mac before any
    /// cleanup cycle ran). Without this seed, the in-memory
    /// `lastPushedRecordNames` starts empty on every Mac launch, and
    /// `pushHistorySeeded`'s first-cycle guard hides any pre-existing
    /// stranded record from the diff forever.
    func fetchPerProviderRecordNames(
        forDeviceID deviceID: String) async -> [String]
}

extension SyncPushing {
    /// Default no-op so existing test doubles don't have to implement the new
    /// method. CloudSyncManager overrides with the real CloudKit write.
    public func pushPerProviderRecords(
        _: [ProviderUsageEnvelope]) async -> SyncPushResult
    {
        .success
    }

    /// Default no-op for delete path — test doubles that don't track CKRecord
    /// state get a successful no-op.
    public func deletePerProviderRecords(
        recordNames _: [String]) async -> SyncPushResult
    {
        .success
    }

    /// Default empty result — test doubles that don't simulate CloudKit
    /// state report no pre-existing records, which makes startup reconcile
    /// a no-op. Real CloudSyncManager overrides with the live query.
    public func fetchPerProviderRecordNames(
        forDeviceID _: String) async -> [String]
    {
        []
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
    case productionSchemaMissingRecordType(String)
    case productionSchemaMissingQueryableIndex(String)
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
        case let .productionSchemaMissingRecordType(recordType):
            "CloudKit Production schema is missing record type \(recordType). " +
                "Deploy CloudKit schema changes to Production for " +
                "\(CloudSyncConstants.containerIdentifier), then try Sync Now again."
        case let .productionSchemaMissingQueryableIndex(fieldName):
            "CloudKit Production index for \(fieldName) is not ready yet. " +
                "Deploy the queryable index for " +
                "\(CloudSyncConstants.containerIdentifier), then try Sync Now again."
        case let .serverError(msg):
            "Server error: \(msg)"
        case let .decodingFailed(msg):
            "Data format error: \(msg)"
        case let .unknown(msg):
            msg
        }
    }

    public init(from ckError: CKError) {
        let diagnosticMessage = Self.diagnosticMessage(from: ckError)
        if let recordType = Self.missingProductionRecordType(in: diagnosticMessage) {
            self = .productionSchemaMissingRecordType(recordType)
            return
        }
        if let fieldName = Self.missingProductionQueryableIndex(in: diagnosticMessage) {
            self = .productionSchemaMissingQueryableIndex(fieldName)
            return
        }

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

    public static func missingProductionRecordType(in message: String) -> String? {
        guard let start = message.range(
            of: "Cannot create new type ",
            options: [.caseInsensitive])
        else { return nil }
        let remainder = message[start.upperBound...]
        guard let end = remainder.range(
            of: " in production schema",
            options: [.caseInsensitive])
        else { return nil }
        let recordType = remainder[..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return recordType.isEmpty ? nil : recordType
    }

    public static func missingProductionQueryableIndex(in message: String) -> String? {
        guard message.range(
            of: "not marked queryable",
            options: [.caseInsensitive]) != nil
        else { return nil }

        let quotedField = #/Field\s+'([^']+)'/#
        if let match = message.firstMatch(of: quotedField) {
            return String(match.1)
        }
        if message.range(of: "recordName", options: [.caseInsensitive]) != nil {
            return "recordName"
        }
        return nil
    }

    private static func diagnosticMessage(from ckError: CKError) -> String {
        let userInfoMessages = ckError.userInfo.values.compactMap { value -> String? in
            if let string = value as? String {
                return string
            }
            if let error = value as? NSError {
                return error.localizedDescription
            }
            return nil
        }
        return ([ckError.localizedDescription] + userInfoMessages).joined(separator: "\n")
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
