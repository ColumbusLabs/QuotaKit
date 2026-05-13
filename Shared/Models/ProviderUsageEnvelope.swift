import Foundation

/// Payload pushed to `DeviceProviderSnapshot` CKRecords in `DeviceProvidersZone`.
///
/// Wraps a single `ProviderUsageSnapshot` with the device-level metadata iOS needs
/// to reconstruct the per-device view without downloading every provider's record.
/// Encoded as JSON, then zlib-compressed via `PayloadCompression` before being
/// written to the CKRecord's `payload` field.
public struct ProviderUsageEnvelope: Codable, Sendable, Equatable {
    public let deviceID: String
    public let deviceName: String
    public let appVersion: String?
    public let mobileVersion: String?
    /// Device-level sync timestamp at the moment this envelope was produced.
    /// Envelope-level — NOT used by the per-provider diff in `SyncCoordinator`,
    /// which diffs on `provider` content alone so a timestamp-only change does
    /// not force a rewrite.
    public let syncTimestamp: Date
    public let notificationPushEnabled: Bool?
    public let provider: ProviderUsageSnapshot

    public init(
        deviceID: String,
        deviceName: String,
        appVersion: String?,
        mobileVersion: String?,
        syncTimestamp: Date,
        notificationPushEnabled: Bool?,
        provider: ProviderUsageSnapshot)
    {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.mobileVersion = mobileVersion
        self.syncTimestamp = syncTimestamp
        self.notificationPushEnabled = notificationPushEnabled
        self.provider = provider
    }
}
