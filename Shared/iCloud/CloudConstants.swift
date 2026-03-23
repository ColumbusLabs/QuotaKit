import Foundation

/// Constants for iCloud sync between Mac and iOS.
public enum CloudSyncConstants {
    // MARK: - CloudKit

    /// The CloudKit container identifier shared by Mac and iOS apps.
    public static let containerIdentifier = "iCloud.com.o1xhack.codexbar"

    /// The CloudKit record type for per-device usage snapshots.
    public static let recordType = "DeviceSnapshot"

    /// CloudKit subscription ID for receiving push notifications on record changes.
    public static let subscriptionID = "device-snapshot-changes"

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
