import CodexBarSync
import Foundation

struct ProEntitlementCache: Codable, Equatable, Sendable {
    let productID: String
    let verifiedAt: Date

    var isValidForCurrentProduct: Bool {
        self.productID == ProductConfig.storeKitLifetimeProductID
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

    static func load(defaults: UserDefaults? = nil) -> ProEntitlementCache? {
        if let defaults {
            return self.load(from: defaults)
        }

        guard let appGroupDefaults = self.appGroupDefaults() else {
            return self.load(from: .standard)
        }

        if let cache = self.load(from: appGroupDefaults) {
            return cache
        }

        if let legacyStandard = self.load(from: .standard) {
            self.save(legacyStandard, defaults: appGroupDefaults)
            UserDefaults.standard.removeObject(forKey: Self.key)
            return legacyStandard
        }

        if let migrated = self.migrateLegacyWidgetProCache(into: appGroupDefaults) {
            return migrated
        }

        return nil
    }

    static func save(_ cache: ProEntitlementCache, defaults: UserDefaults? = nil) {
        let storage = defaults ?? self.appGroupDefaults() ?? .standard
        guard let data = try? JSONEncoder().encode(cache) else { return }
        storage.set(data, forKey: Self.key)
        if defaults == nil {
            UserDefaults.standard.removeObject(forKey: Self.key)
            self.clearLegacyWidgetProCache()
        }
    }

    static func clear(defaults: UserDefaults? = nil) {
        let storage = defaults ?? self.appGroupDefaults() ?? .standard
        storage.removeObject(forKey: Self.key)
        if defaults == nil {
            UserDefaults.standard.removeObject(forKey: Self.key)
            self.clearLegacyWidgetProCache()
        }
    }

    private static func load(from defaults: UserDefaults) -> ProEntitlementCache? {
        guard let data = defaults.data(forKey: Self.key),
              let cache = try? JSONDecoder().decode(ProEntitlementCache.self, from: data)
        else {
            if let migrated = Self.migrateLegacyWidgetProCache(into: defaults) {
                return migrated
            }
            return nil
        }
        guard cache.isValidForCurrentProduct else {
            defaults.removeObject(forKey: Self.key)
            return nil
        }
        return cache
    }

    private struct LegacyWidgetProCache: Codable {
        let isProUnlocked: Bool
        let productID: String
        let verifiedAt: Date
    }

    private static func migrateLegacyWidgetProCache(into defaults: UserDefaults) -> ProEntitlementCache? {
        guard let data = defaults.data(forKey: Self.legacyWidgetProCacheKey),
              let legacy = try? JSONDecoder().decode(LegacyWidgetProCache.self, from: data),
              legacy.isProUnlocked,
              legacy.productID == ProductConfig.storeKitLifetimeProductID
        else {
            return nil
        }

        let cache = ProEntitlementCache(productID: legacy.productID, verifiedAt: legacy.verifiedAt)
        self.save(cache, defaults: defaults)
        defaults.removeObject(forKey: Self.legacyWidgetProCacheKey)
        return cache
    }

    private static func clearLegacyWidgetProCache() {
        self.appGroupDefaults()?.removeObject(forKey: Self.legacyWidgetProCacheKey)
    }
}
