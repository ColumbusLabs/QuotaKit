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

    /// iOS 1.6.0 / Mac 0.25.2 — per-provider quota warning configuration
    /// resolved from `CodexBarConfig.quotaWarnings` + the Mac-side
    /// per-provider override store. iOS uses these thresholds to render
    /// warning marker ticks on the usage bar (`UsageCardView`).
    ///
    /// **Optional** so the field is backward-compatible: old Macs
    /// (pre-0.25.2) won't write it, old iOS clients (pre-1.6.0) ignore
    /// it. New iOS that receives `nil` falls back to Mac's documented
    /// defaults via `SyncQuotaWarningConfig.macDefaults`.
    ///
    /// See `Research/020-multi-account-comprehensive.md` §R7.4 for the
    /// 16-cell device matrix proof.
    public let quotaWarnings: SyncQuotaWarningConfig?

    public init(
        deviceID: String,
        deviceName: String,
        appVersion: String?,
        mobileVersion: String?,
        syncTimestamp: Date,
        notificationPushEnabled: Bool?,
        provider: ProviderUsageSnapshot,
        quotaWarnings: SyncQuotaWarningConfig? = nil)
    {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.mobileVersion = mobileVersion
        self.syncTimestamp = syncTimestamp
        self.notificationPushEnabled = notificationPushEnabled
        self.provider = provider
        self.quotaWarnings = quotaWarnings
    }

    /// Custom Codable decoder so the new `quotaWarnings` field uses
    /// `decodeIfPresent` (belt-and-suspenders on top of Codable's
    /// default missing-key tolerance). Pre-1.6.0 envelopes lack this
    /// field and must decode to `nil` without throwing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.deviceID = try c.decode(String.self, forKey: .deviceID)
        self.deviceName = try c.decode(String.self, forKey: .deviceName)
        self.appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        self.mobileVersion = try c.decodeIfPresent(String.self, forKey: .mobileVersion)
        self.syncTimestamp = try c.decode(Date.self, forKey: .syncTimestamp)
        self.notificationPushEnabled = try c.decodeIfPresent(
            Bool.self, forKey: .notificationPushEnabled)
        self.provider = try c.decode(ProviderUsageSnapshot.self, forKey: .provider)
        self.quotaWarnings = try c.decodeIfPresent(
            SyncQuotaWarningConfig.self, forKey: .quotaWarnings)
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case deviceName
        case appVersion
        case mobileVersion
        case syncTimestamp
        case notificationPushEnabled
        case provider
        case quotaWarnings
    }
}
