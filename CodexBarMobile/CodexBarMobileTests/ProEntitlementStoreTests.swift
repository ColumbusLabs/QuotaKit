import CodexBarSync
import Foundation
import XCTest

@testable import CodexBarMobile

@MainActor
final class ProEntitlementStoreTests: XCTestCase {

    func testProductIDMatchesProductConfig() {
        XCTAssertEqual(
            ProductConfig.storeKitLifetimeProductID,
            "com.columbuslabs.quotakit.pro.lifetime")
    }

    func testVerifiedConfiguredTransactionGrantsProAndCachesEntitlement() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let verifiedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let store = ProEntitlementStore(
            service: FakeProPurchaseService(),
            defaults: defaults)

        await store.apply(.verified(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: verifiedAt))

        XCTAssertTrue(store.isProUnlocked)
        XCTAssertTrue(store.isUnlocked(.unlimitedProviders))
        XCTAssertEqual(store.state, .unlocked(source: .storeKit))
        XCTAssertEqual(
            ProEntitlementCacheStore.load(defaults: defaults),
            ProEntitlementCache(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: verifiedAt))
    }

    func testUnverifiedConfiguredTransactionDoesNotGrantPro() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        ProEntitlementCacheStore.save(
            ProEntitlementCache(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: Date()),
            defaults: defaults)
        let store = ProEntitlementStore(
            service: FakeProPurchaseService(),
            defaults: defaults)

        await store.apply(.unverified(productID: ProductConfig.storeKitLifetimeProductID))

        XCTAssertFalse(store.isProUnlocked)
        XCTAssertEqual(store.state, .locked)
        XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
    }

    func testRestoreRefreshesCurrentEntitlementsAndUpdatesState() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let verifiedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let service = FakeProPurchaseService(
            restoreStatus: .verified(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: verifiedAt))
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.restorePurchases()

        XCTAssertEqual(service.restoreCallCount, 1)
        XCTAssertTrue(store.isProUnlocked)
        XCTAssertEqual(store.state, .unlocked(source: .storeKit))
        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults)?.verifiedAt, verifiedAt)
    }

    func testPurchaseButtonsStateReturnsToIdleAfterPurchase() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let service = FakeProPurchaseService(
            purchaseOutcome: .purchased(.verified(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: Date())))
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.purchase()

        XCTAssertFalse(store.isPurchasing)
        XCTAssertEqual(service.purchaseCallCount, 1)
        XCTAssertTrue(store.isProUnlocked)
    }

    func testProductUnavailableStateRendersWhenNoProductOrEntitlementExists() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let service = FakeProPurchaseService(product: nil, currentStatus: .none)
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()

        XCTAssertEqual(store.state, .productUnavailable)
    }

    func testCacheRoundTripsAndIgnoresMismatchedProductID() {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let cache = ProEntitlementCache(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_200))

        ProEntitlementCacheStore.save(cache, defaults: defaults)

        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults), cache)

        ProEntitlementCacheStore.save(
            ProEntitlementCache(productID: "com.example.other", verifiedAt: Date()),
            defaults: defaults)

        XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
        XCTAssertNil(defaults.data(forKey: ProEntitlementCacheStore.key))
    }

    func testFeatureGateRequiresProForAllV1Features() {
        XCTAssertEqual(Set(FeatureGate.allCases), [
            .unlimitedProviders,
            .homeScreenWidgets,
            .lockScreenWidgets,
            .notifications,
            .fullCostDashboard,
            .usageHistory,
            .shareCards,
            .advancedMergeViews,
            .exports,
        ])
        XCTAssertTrue(FeatureGate.allCases.allSatisfy(\.requiresPro))
    }

    func testSharedSchemeUsesStoreKitConfigurationForRunAction() throws {
        let schemeXML = try String(
            contentsOf: Self.projectRoot()
                .appendingPathComponent("CodexBarMobile/CodexBarMobile.xcodeproj/xcshareddata/xcschemes/CodexBarMobile.xcscheme"),
            encoding: .utf8)
        guard let launchActionRange = schemeXML.range(of: "<LaunchAction"),
              let profileActionRange = schemeXML.range(of: "<ProfileAction")
        else {
            XCTFail("Unable to locate LaunchAction in CodexBarMobile.xcscheme")
            return
        }
        let launchActionXML = String(schemeXML[launchActionRange.lowerBound..<profileActionRange.lowerBound])

        XCTAssertTrue(
            launchActionXML.contains("<StoreKitConfigurationFileReference"),
            "Run action must reference the local QuotaKit StoreKit configuration.")
        XCTAssertTrue(
            launchActionXML.contains("identifier = \"../../StoreKit/QuotaKit.storekit\""),
            "Run action must use the checked-in QuotaKit StoreKit configuration.")
    }

    private static func makeDefaults(
        file: StaticString = #filePath,
        line: UInt = #line) -> UserDefaults
    {
        let suiteName = "quotakit.pro.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test UserDefaults suite", file: file, line: line)
            return .standard
        }
        return defaults
    }

    private static func clear(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: ProEntitlementCacheStore.key)
    }

    private static func projectRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }
}

private final class FakeProPurchaseService: ProPurchaseServicing, @unchecked Sendable {
    var product: ProProductInfo?
    var purchaseOutcome: StoreKitPurchaseOutcome
    var restoreStatus: StoreKitEntitlementStatus
    var currentStatus: StoreKitEntitlementStatus
    var purchaseCallCount = 0
    var restoreCallCount = 0

    init(
        product: ProProductInfo? = ProProductInfo(
            id: ProductConfig.storeKitLifetimeProductID,
            displayName: "QuotaKit Pro",
            description: "Unlock QuotaKit Pro for life.",
            displayPrice: ProductConfig.launchPriceCopy),
        purchaseOutcome: StoreKitPurchaseOutcome = .cancelled,
        restoreStatus: StoreKitEntitlementStatus = .none,
        currentStatus: StoreKitEntitlementStatus = .none)
    {
        self.product = product
        self.purchaseOutcome = purchaseOutcome
        self.restoreStatus = restoreStatus
        self.currentStatus = currentStatus
    }

    func loadProduct() async throws -> ProProductInfo? {
        self.product
    }

    func purchase() async throws -> StoreKitPurchaseOutcome {
        self.purchaseCallCount += 1
        return self.purchaseOutcome
    }

    func restorePurchases() async throws -> StoreKitEntitlementStatus {
        self.restoreCallCount += 1
        return self.restoreStatus
    }

    func currentEntitlementStatus() async -> StoreKitEntitlementStatus {
        self.currentStatus
    }

    nonisolated func transactionUpdates() -> AsyncStream<StoreKitEntitlementStatus> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
