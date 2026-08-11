import CodexBarSync
import Foundation

struct ProEntitlementCache: Codable, Equatable, Sendable {
    let productID: String
    let verifiedAt: Date
    /// Missing on caches written before environment tracking. Those caches
    /// came from the production lifetime product and are treated accordingly.
    let environment: ProEntitlementEnvironment?

    init(
        productID: String,
        verifiedAt: Date,
        environment: ProEntitlementEnvironment? = nil)
    {
        self.productID = productID
        self.verifiedAt = verifiedAt
        self.environment = environment
    }

    var effectiveEnvironment: ProEntitlementEnvironment {
        self.environment ?? .production
    }

    var isValidForCurrentProduct: Bool {
        self.productID == ProductConfig.storeKitLifetimeProductID
    }
}

enum ProEntitlementEnvironment: String, Codable, Equatable, Sendable {
    case production
    case sandbox
    case xcode
    case unknown
}

/// Coordinates the current app-group cache with cache locations used by older
/// releases. All production reads, writes, and clears must go through this
/// type so an old standard-defaults value cannot outlive an authoritative
/// StoreKit revocation and later migrate itself back into the app group.
struct ProEntitlementCacheStorage {
    let currentDefaults: UserDefaults
    let legacyDefaults: UserDefaults?

    func load() -> ProEntitlementCache? {
        if let current = self.decodeCache(from: self.currentDefaults) {
            self.clearLegacyCopies()
            return current
        }
        if self.currentDefaults.object(forKey: ProEntitlementCacheStore.key) != nil {
            self.currentDefaults.removeObject(forKey: ProEntitlementCacheStore.key)
        }

        if let legacyWidget = self.decodeLegacyWidgetCache(from: self.currentDefaults),
           self.save(legacyWidget)
        {
            return legacyWidget
        }

        if let legacyDefaults = self.distinctLegacyDefaults,
           let legacy = self.decodeCache(from: legacyDefaults) ?? self.decodeLegacyWidgetCache(from: legacyDefaults),
           self.save(legacy)
        {
            return legacy
        }

        return nil
    }

    /// Saves to the app-group location first and removes legacy copies only
    /// after a verified round trip. This preserves a recoverable old cache if
    /// the new write ever fails.
    @discardableResult
    func save(_ cache: ProEntitlementCache) -> Bool {
        guard cache.isValidForCurrentProduct else {
            self.clear()
            return false
        }
        guard let data = try? JSONEncoder().encode(cache) else {
            return false
        }

        self.currentDefaults.set(data, forKey: ProEntitlementCacheStore.key)
        guard self.decodeCache(from: self.currentDefaults) == cache else {
            return false
        }

        self.currentDefaults.removeObject(forKey: ProEntitlementCacheStore.legacyWidgetProCacheKey)
        self.clearLegacyCopies()
        return true
    }

    func clear() {
        // UserDefaults suites cannot participate in one transaction. Remove
        // legacy sources first so interruption can leave, at worst, the
        // authoritative app-group copy; removing current first could let a
        // surviving legacy value resurrect itself on the next migration.
        self.clearLegacyCopies()
        self.currentDefaults.removeObject(forKey: ProEntitlementCacheStore.legacyWidgetProCacheKey)
        self.currentDefaults.removeObject(forKey: ProEntitlementCacheStore.key)
    }

    private var distinctLegacyDefaults: UserDefaults? {
        guard let legacyDefaults, legacyDefaults !== self.currentDefaults else { return nil }
        return legacyDefaults
    }

    private func clearLegacyCopies() {
        guard let legacyDefaults = self.distinctLegacyDefaults else { return }
        legacyDefaults.removeObject(forKey: ProEntitlementCacheStore.key)
        legacyDefaults.removeObject(forKey: ProEntitlementCacheStore.legacyWidgetProCacheKey)
    }

    private func decodeCache(from defaults: UserDefaults) -> ProEntitlementCache? {
        guard let data = defaults.data(forKey: ProEntitlementCacheStore.key),
              let cache = try? JSONDecoder().decode(ProEntitlementCache.self, from: data),
              cache.isValidForCurrentProduct
        else {
            return nil
        }
        return cache
    }

    private func decodeLegacyWidgetCache(from defaults: UserDefaults) -> ProEntitlementCache? {
        guard let data = defaults.data(forKey: ProEntitlementCacheStore.legacyWidgetProCacheKey),
              let legacy = try? JSONDecoder().decode(LegacyWidgetProCache.self, from: data),
              legacy.isProUnlocked,
              legacy.productID == ProductConfig.storeKitLifetimeProductID
        else {
            return nil
        }
        return ProEntitlementCache(productID: legacy.productID, verifiedAt: legacy.verifiedAt)
    }

    private struct LegacyWidgetProCache: Codable {
        let isProUnlocked: Bool
        let productID: String
        let verifiedAt: Date
    }
}

enum ProEntitlementCacheStore {
    static let key = "com.columbuslabs.quotakit.pro.entitlement.cache"
    static let legacyWidgetProCacheKey = "com.columbuslabs.quotakit.widgets.pro.cache"

    static func appGroupDefaults(
        appGroupIdentifier: String = ProductConfig.appGroupIdentifier) -> UserDefaults?
    {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func productionStorage() -> ProEntitlementCacheStorage {
        if let appGroupDefaults = self.appGroupDefaults() {
            return ProEntitlementCacheStorage(
                currentDefaults: appGroupDefaults,
                legacyDefaults: .standard)
        }
        return ProEntitlementCacheStorage(currentDefaults: .standard, legacyDefaults: nil)
    }

    static func load(defaults: UserDefaults? = nil) -> ProEntitlementCache? {
        if let defaults {
            return ProEntitlementCacheStorage(currentDefaults: defaults, legacyDefaults: nil).load()
        }
        return self.productionStorage().load()
    }

    static func save(_ cache: ProEntitlementCache, defaults: UserDefaults? = nil) {
        if let defaults {
            ProEntitlementCacheStorage(currentDefaults: defaults, legacyDefaults: nil).save(cache)
        } else {
            self.productionStorage().save(cache)
        }
    }

    static func clear(defaults: UserDefaults? = nil) {
        if let defaults {
            ProEntitlementCacheStorage(currentDefaults: defaults, legacyDefaults: nil).clear()
        } else {
            self.productionStorage().clear()
        }
    }
}
