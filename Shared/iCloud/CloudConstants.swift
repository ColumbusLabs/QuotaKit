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

    /// Legacy zone used by Build 42–49. Kept only so we can delete the stale
    /// `quota-transition-zone-sub` on upgrade; no new records are written here.
    public static let quotaTransitionsZoneName = "QuotaTransitionsZone"

    /// Dedicated zone for "quota depleted" push events. Split by state (not predicate)
    /// because CKQuerySubscription does not persist on this container (A/B test
    /// confirmed, see `QuotaTransitionSubscriptions.swift`). Splitting by zone lets
    /// each CKRecordZoneSubscription carry its own static localization key.
    public static let quotaDepletedZoneName = "QuotaDepletedZone"

    /// Dedicated zone for "quota restored" push events. See `quotaDepletedZoneName`.
    public static let quotaRestoredZoneName = "QuotaRestoredZone"

    /// CloudKit record type for visible quota change push events (alert push design).
    /// One record per (provider, hourBucket) within each state-specific zone — see
    /// `Research/004-alert-push-cloudkit.md`.
    public static let quotaTransitionRecordType = "QuotaTransition"

    /// Subscription ID used by Build 42–49 (single zone-level sub on
    /// `QuotaTransitionsZone`). Kept as a constant so the new setup code can
    /// delete it during upgrade.
    public static let quotaTransitionLegacySubscriptionID = "quota-transition-zone-sub"

    /// Subscription ID for the "depleted" CKRecordZoneSubscription on
    /// `QuotaDepletedZone`.
    public static let quotaTransitionDepletedSubscriptionID = "quota-transition-depleted"

    /// Subscription ID for the "restored" CKRecordZoneSubscription on
    /// `QuotaRestoredZone`.
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
