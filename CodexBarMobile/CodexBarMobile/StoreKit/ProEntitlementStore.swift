import CodexBarSync
import Foundation
import Observation

@Observable
@MainActor
final class ProEntitlementStore {
    enum State: Equatable {
        case loading
        case locked
        case unlocked(source: Source)
        case pending
        case productUnavailable
        case error(String)
    }

    enum Source: Equatable {
        case cache
        case storeKit
    }

    private let service: any ProPurchaseServicing
    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?

    private(set) var state: State
    private(set) var product: ProProductInfo?
    private(set) var isPurchasing = false
    private(set) var isRestoring = false

    var isProUnlocked: Bool {
        if case .unlocked = self.state { return true }
        return false
    }

    var statusText: String {
        switch self.state {
        case .loading:
            "Checking App Store"
        case .locked:
            "Free"
        case .unlocked:
            "Pro unlocked"
        case .pending:
            "Purchase pending"
        case .productUnavailable:
            "Unavailable"
        case .error:
            "Needs attention"
        }
    }

    var displayPrice: String {
        self.product?.displayPrice ?? ProductConfig.launchPriceCopy
    }

    init(
        service: any ProPurchaseServicing = StoreKitPurchaseService(),
        defaults: UserDefaults? = nil)
    {
        self.service = service
        self.defaults = defaults ?? ProEntitlementCacheStore.appGroupDefaults() ?? .standard
        if ProEntitlementCacheStore.load(defaults: self.defaults) != nil {
            self.state = .unlocked(source: .cache)
        } else {
            self.state = .loading
        }
    }

    func start() {
        guard self.updatesTask == nil else { return }
        self.updatesTask = Task { [weak self] in
            guard let self else { return }
            for await status in self.service.transactionUpdates() {
                await self.apply(status)
            }
        }
        Task { await self.refresh() }
    }

    func refresh() async {
        if !self.isProUnlocked {
            self.state = .loading
        }
        do {
            self.product = try await self.service.loadProduct()
            let status = await self.service.currentEntitlementStatus()
            if self.product == nil, !self.isProUnlocked, status == .none {
                self.state = .productUnavailable
                return
            }
            await self.apply(status)
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    func purchase() async {
        guard !self.isPurchasing else { return }
        self.isPurchasing = true
        defer { self.isPurchasing = false }

        do {
            switch try await self.service.purchase() {
            case .purchased(let status):
                await self.apply(status)
            case .pending:
                self.state = .pending
            case .cancelled:
                if !self.isProUnlocked {
                    self.state = .locked
                }
            }
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    func restorePurchases() async {
        guard !self.isRestoring else { return }
        self.isRestoring = true
        defer { self.isRestoring = false }

        do {
            await self.apply(try await self.service.restorePurchases())
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    func isUnlocked(_ feature: FeatureGate) -> Bool {
        !feature.requiresPro || self.isProUnlocked
    }

    func apply(_ status: StoreKitEntitlementStatus) async {
        switch status {
        case .verified(let productID, let verifiedAt)
            where productID == ProductConfig.storeKitLifetimeProductID:
            ProEntitlementCacheStore.save(
                ProEntitlementCache(productID: productID, verifiedAt: verifiedAt),
                defaults: self.defaults)
            self.state = .unlocked(source: .storeKit)
        case .unverified(let productID)
            where productID == ProductConfig.storeKitLifetimeProductID:
            ProEntitlementCacheStore.clear(defaults: self.defaults)
            self.state = .locked
        case .none:
            ProEntitlementCacheStore.clear(defaults: self.defaults)
            self.state = .locked
        default:
            break
        }
    }
}

#if DEBUG
extension ProEntitlementStore {
    static func preview(state: State, product: ProProductInfo? = nil) -> ProEntitlementStore {
        let store = ProEntitlementStore(
            service: PreviewProPurchaseService(product: product),
            defaults: UserDefaults(suiteName: "quotakit.pro.preview.\(UUID().uuidString)")!)
        store.state = state
        store.product = product
        return store
    }
}

private struct PreviewProPurchaseService: ProPurchaseServicing {
    let product: ProProductInfo?

    init(product: ProProductInfo?) {
        self.product = product
    }

    func loadProduct() async throws -> ProProductInfo? {
        self.product
    }

    func purchase() async throws -> StoreKitPurchaseOutcome {
        .purchased(.verified(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date()))
    }

    func restorePurchases() async throws -> StoreKitEntitlementStatus {
        .none
    }

    func currentEntitlementStatus() async -> StoreKitEntitlementStatus {
        .none
    }

    func transactionUpdates() -> AsyncStream<StoreKitEntitlementStatus> {
        AsyncStream { $0.finish() }
    }
}
#endif
