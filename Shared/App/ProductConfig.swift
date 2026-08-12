import Foundation

/// Central product identifiers for QuotaKit-owned builds.
///
/// These values define the new product boundary. Do not replace them with
/// upstream team IDs, bundle IDs, CloudKit containers, or release credentials.
public enum ProductConfig {
    public static let appName = "QuotaKit"
    public static let companyName = "Columbus Labs"

    public static let macBundleIdentifier = "com.columbuslabs.quotakit.mac"
    public static let macDebugBundleIdentifier = "com.columbuslabs.quotakit.mac.debug"
    public static let iOSBundleIdentifier = "com.columbuslabs.quotakit.ios"
    public static let iOSPushExtensionBundleIdentifier = "com.columbuslabs.quotakit.ios.pushextension"
    public static let iOSWidgetsBundleIdentifier = "com.columbuslabs.quotakit.ios.widgets"
    public static let syncFrameworkBundleIdentifier = "com.columbuslabs.quotakit.sync"

    public static let appGroupIdentifier = "group.com.columbuslabs.quotakit"
    public static let debugAppGroupIdentifier = "group.com.columbuslabs.quotakit.debug"

    public static let iCloudContainerIdentifier = "iCloud.com.columbuslabs.quotakit"
    public static let ubiquitousKVStoreIdentifierSuffix = "com.columbuslabs.quotakit.shared"

    public static let stableDeviceIDKey = "com.columbuslabs.quotakit.sync.deviceID"
    public static let kvsSnapshotKey = "com.columbuslabs.quotakit.usage.snapshot"

    public static let storeKitLifetimeProductID = "com.columbuslabs.quotakit.pro.lifetime"
    public static let launchPriceCopy = "$4.99 lifetime"

    public static let macSetupURL = URL(string: "https://columbus-labs.com/quotakit/mac")!
    public static let macSetupDisplayURL = "columbus-labs.com/quotakit/mac"
    public static let remoteConfigURL = URL(string: "https://columbus-labs.com/quotakit/config/ios.json")!

    public static let logSubsystem = "com.columbuslabs.quotakit"
}
