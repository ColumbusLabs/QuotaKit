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
    private let cacheStorage: ProEntitlementCacheStorage
    private var updatesTask: Task<Void, Never>?
    private var isRefreshing = false
    private var entitlementRevision: UInt64 = 0

    private(set) var state: State
    private(set) var product: ProProductInfo?
    private(set) var lastError: String?
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
        defaults: UserDefaults? = nil,
        legacyDefaults: UserDefaults? = nil)
    {
        self.service = service
        if let defaults {
            self.cacheStorage = ProEntitlementCacheStorage(
                currentDefaults: defaults,
                legacyDefaults: legacyDefaults)
        } else {
            self.cacheStorage = ProEntitlementCacheStore.productionStorage()
        }
        if self.cacheStorage.load() != nil {
            self.state = .unlocked(source: .cache)
        } else {
            self.state = .loading
        }
    }

    func start() {
        guard self.updatesTask == nil else { return }
        self.updatesTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in self.service.transactionUpdates() {
                await self.apply(snapshot)
            }
        }
        Task { await self.refresh() }
    }

    func refresh() async {
        guard !self.isRefreshing else { return }
        self.isRefreshing = true
        defer { self.isRefreshing = false }
        let startingRevision = self.entitlementRevision

        if !self.isProUnlocked {
            self.state = .loading
        }
        let snapshot = await self.service.currentEntitlementStatus()
        guard startingRevision == self.entitlementRevision else { return }
        do {
            let product = try await self.service.loadProduct()
            guard startingRevision == self.entitlementRevision else { return }
            self.product = product
            self.lastError = nil
            if product == nil, snapshot.status == .none {
                if self.cacheStorage.load() != nil {
                    await self.apply(snapshot)
                    if self.isProUnlocked {
                        self.lastError = StoreKitPurchaseServiceError.productUnavailable.localizedDescription
                    }
                } else {
                    self.state = .productUnavailable
                }
                return
            }
            await self.apply(snapshot)
        } catch {
            guard startingRevision == self.entitlementRevision else { return }
            self.record(error)
            // A durable cache still needs the environment policy applied when
            // product metadata fails. Production/same-test-environment empty
            // snapshots are authoritative; cross-environment and eligible
            // unknown snapshots remain fail-safe in `apply`.
            if snapshot.status != .none || self.cacheStorage.load() != nil {
                await self.apply(snapshot)
            }
        }
    }

    func purchase() async {
        guard !self.isPurchasing else { return }
        self.isPurchasing = true
        defer { self.isPurchasing = false }

        do {
            switch try await self.service.purchase() {
            case let .purchased(snapshot):
                self.lastError = nil
                await self.apply(snapshot)
            case .pending:
                self.state = .pending
            case .cancelled:
                if !self.isProUnlocked {
                    self.state = .locked
                }
            }
        } catch {
            self.record(error)
        }
    }

    func restorePurchases() async {
        guard !self.isRestoring else { return }
        self.isRestoring = true
        defer { self.isRestoring = false }

        do {
            self.lastError = nil
            try await self.apply(self.service.restorePurchases())
        } catch {
            self.record(error)
        }
    }

    func isUnlocked(_ feature: FeatureGate) -> Bool {
        !feature.requiresPro || self.isProUnlocked
    }

    func apply(_ status: StoreKitEntitlementStatus) async {
        // Internal/test seam for already verified production-style statuses.
        await self.apply(StoreKitEntitlementSnapshot(status: status, environment: .production))
    }

    func apply(_ snapshot: StoreKitEntitlementSnapshot) async {
        self.entitlementRevision &+= 1
        switch snapshot.status {
        case let .verified(productID, verifiedAt)
            where productID == ProductConfig.storeKitLifetimeProductID:
            let environment = Self.cacheEnvironment(
                afterVerificationIn: snapshot.environment,
                existingCache: self.cacheStorage.load())
            self.cacheStorage.save(ProEntitlementCache(
                productID: productID,
                verifiedAt: verifiedAt,
                environment: environment))
            self.state = .unlocked(source: .storeKit)
        case let .revoked(productID)
            where productID == ProductConfig.storeKitLifetimeProductID:
            if let cache = self.cacheStorage.load(),
               !Self.shouldDiscardCache(cache, forRevocationEnvironment: snapshot.environment)
            {
                self.state = .unlocked(source: .cache)
            } else {
                self.cacheStorage.clear()
                self.state = .locked
            }
        case let .unverified(productID)
            where productID == ProductConfig.storeKitLifetimeProductID:
            // A failed signature verification cannot grant access, but it is
            // not affirmative evidence that a previously verified lifetime
            // purchase was revoked.
            if self.cacheStorage.load() != nil {
                self.state = .unlocked(source: .cache)
            } else {
                self.state = .locked
            }
        case .none:
            if let cache = self.cacheStorage.load(),
               !Self.shouldDiscardCache(cache, forEmptyEnvironment: snapshot.environment)
            {
                // TestFlight reads sandbox entitlements. A production/legacy
                // lifetime cache must survive an empty sandbox sequence.
                self.state = .unlocked(source: .cache)
            } else {
                self.cacheStorage.clear()
                self.state = .locked
            }
        default:
            break
        }
    }

    private static func cacheEnvironment(
        afterVerificationIn environment: ProEntitlementEnvironment,
        existingCache: ProEntitlementCache?) -> ProEntitlementEnvironment
    {
        if environment == .production {
            return .production
        }
        if existingCache?.effectiveEnvironment == .production {
            // Do not downgrade a production lifetime cache merely because the
            // same buyer exercises a sandbox/TestFlight transaction.
            return .production
        }
        return environment
    }

    private static func shouldDiscardCache(
        _ cache: ProEntitlementCache,
        forEmptyEnvironment environment: ProEntitlementEnvironment) -> Bool
    {
        switch environment {
        case .production:
            // A successfully loaded production product plus no production
            // entitlement is authoritative for every cached origin.
            true
        case .sandbox, .xcode:
            // TestFlight/Xcode cannot see production purchases, but an empty
            // sequence is authoritative for a same-environment test cache.
            cache.effectiveEnvironment != .production
        case .unknown:
            // Unknown environment can preserve a production lifetime cache,
            // but never a sandbox/Xcode cache that could leak test access.
            cache.effectiveEnvironment != .production
        }
    }

    private static func shouldDiscardCache(
        _ cache: ProEntitlementCache,
        forRevocationEnvironment environment: ProEntitlementEnvironment) -> Bool
    {
        if environment == .production {
            return true
        }
        // Non-production revocations can never invalidate a production buyer,
        // but they must clear every test-origin cache to prevent leakage across
        // sandbox, Xcode, and indeterminate test environments.
        return cache.effectiveEnvironment != .production
    }

    private func record(_ error: Error) {
        let message = error.localizedDescription
        self.lastError = message
        if !self.isProUnlocked {
            self.state = .error(message)
        }
    }
}

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

    func loadProduct() async throws -> ProProductInfo? {
        self.product
    }

    func purchase() async throws -> StoreKitPurchaseOutcome {
        .purchased(StoreKitEntitlementSnapshot(
            status: .verified(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: Date()),
            environment: .xcode))
    }

    func restorePurchases() async throws -> StoreKitEntitlementSnapshot {
        StoreKitEntitlementSnapshot(status: .none, environment: .xcode)
    }

    func currentEntitlementStatus() async -> StoreKitEntitlementSnapshot {
        StoreKitEntitlementSnapshot(status: .none, environment: .xcode)
    }

    func transactionUpdates() -> AsyncStream<StoreKitEntitlementSnapshot> {
        AsyncStream { $0.finish() }
    }
}
