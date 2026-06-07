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

    static func load(defaults: UserDefaults = .standard) -> ProEntitlementCache? {
        guard let data = defaults.data(forKey: Self.key),
              let cache = try? JSONDecoder().decode(ProEntitlementCache.self, from: data)
        else {
            return nil
        }
        guard cache.isValidForCurrentProduct else {
            Self.clear(defaults: defaults)
            return nil
        }
        return cache
    }

    static func save(_ cache: ProEntitlementCache, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: Self.key)
    }
}
