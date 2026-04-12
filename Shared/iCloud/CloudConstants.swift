import Foundation

/// Constants for iCloud sync between Mac and iOS.
public enum CloudSyncConstants {
    // MARK: - CloudKit

    /// The CloudKit container identifier shared by Mac and iOS apps.
    public static let containerIdentifier = "iCloud.com.o1xhack.codexbar"

    /// The CloudKit record type for per-device usage snapshots.
    public static let recordType = "DeviceSnapshot"

    /// Custom record zone name for per-device usage snapshots.
    public static let customZoneName = "DeviceSnapshotsZone"

    /// Dedicated zone for quota transition push events. Separate from DeviceSnapshotsZone
    /// so the CKRecordZoneSubscription only fires for QuotaTransition changes, not for
    /// every DeviceSnapshot update (which happens every ~60s).
    public static let quotaTransitionsZoneName = "QuotaTransitionsZone"

    /// CloudKit record type for visible quota change push events (alert push design).
    /// One record per (deviceID, provider, state, hourBucket) — see
    /// `Research/004-alert-push-cloudkit.md`.
    public static let quotaTransitionRecordType = "QuotaTransition"

    /// Subscription IDs for the two visible alert-push subscriptions iOS creates.
    /// Each subscription's predicate filters on `state`, and its `notificationInfo`
    /// holds the localization key for the matching template.
    public static let quotaTransitionDepletedSubscriptionID = "quota-transition-depleted"
    public static let quotaTransitionRestoredSubscriptionID = "quota-transition-restored"

    /// UserDefaults key for the stable device UUID (persisted on each Mac).
    public static let deviceIDKey = "com.codexbar.sync.deviceID"

    // MARK: - Legacy KVS (kept for backward compatibility during transition)

    /// The key used in NSUbiquitousKeyValueStore for the usage snapshot.
    public static let kvsSnapshotKey = "com.codexbar.usage.snapshot"

    /// Maximum allowed payload size for NSUbiquitousKeyValueStore (1 MB).
    public static let maxKVSPayloadBytes = 1_048_576

    /// Legacy alias — existing tests reference `maxPayloadBytes`.
    public static let maxPayloadBytes = maxKVSPayloadBytes
}
