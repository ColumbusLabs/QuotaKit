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
                verifiedAt: verifiedAt,
                environment: .production))
    }

    func testUnverifiedConfiguredTransactionDoesNotGrantFreshInstallPro() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let store = ProEntitlementStore(
            service: FakeProPurchaseService(),
            defaults: defaults)

        await store.apply(.unverified(productID: ProductConfig.storeKitLifetimeProductID))

        XCTAssertFalse(store.isProUnlocked)
        XCTAssertEqual(store.state, .locked)
        XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
    }

    func testCachedLifetimeEntitlementSurvivesUnverifiedTransaction() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let cached = ProEntitlementCache(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_050))
        ProEntitlementCacheStore.save(cached, defaults: defaults)
        let store = ProEntitlementStore(
            service: FakeProPurchaseService(),
            defaults: defaults)

        await store.apply(.unverified(productID: ProductConfig.storeKitLifetimeProductID))

        XCTAssertEqual(store.state, .unlocked(source: .cache))
        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults), cached)
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
            purchaseOutcome: .purchased(StoreKitEntitlementSnapshot(
                status: .verified(
                    productID: ProductConfig.storeKitLifetimeProductID,
                    verifiedAt: Date()),
                environment: .sandbox)))
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

    func testCachedLifetimeEntitlementSurvivesProductMetadataFailure() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let cached = ProEntitlementCache(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_150))
        ProEntitlementCacheStore.save(cached, defaults: defaults)
        let service = FakeProPurchaseService(
            productError: FakeStoreKitError.productMetadataUnavailable,
            currentStatus: .none)
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()

        XCTAssertTrue(store.isProUnlocked)
        XCTAssertEqual(store.state, .unlocked(source: .cache))
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults), cached)
        XCTAssertEqual(service.currentEntitlementCallCount, 1)
        XCTAssertEqual(service.loadProductCallCount, 1)
    }

    func testCachedLifetimeEntitlementSurvivesMissingProductMetadata() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let cached = ProEntitlementCache(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_160))
        ProEntitlementCacheStore.save(cached, defaults: defaults)
        let service = FakeProPurchaseService(product: nil, currentStatus: .none)
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()

        XCTAssertTrue(store.isProUnlocked)
        XCTAssertEqual(store.state, .unlocked(source: .cache))
        XCTAssertEqual(
            store.lastError,
            StoreKitPurchaseServiceError.productUnavailable.localizedDescription)
        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults), cached)
    }

    func testEmptyProductionEntitlementClearsProductionCacheWhenProductMetadataThrows() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        ProEntitlementCacheStore.save(
            ProEntitlementCache(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_165),
                environment: .production),
            defaults: defaults)
        let service = FakeProPurchaseService(
            productError: FakeStoreKitError.productMetadataUnavailable,
            currentStatus: .none,
            currentEnvironment: .production)
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()

        XCTAssertEqual(store.state, .locked)
        XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
        XCTAssertEqual(store.lastError, FakeStoreKitError.productMetadataUnavailable.localizedDescription)
    }

    func testEmptyProductionEntitlementClearsProductionCacheWhenProductMetadataIsMissing() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        ProEntitlementCacheStore.save(
            ProEntitlementCache(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_170),
                environment: .production),
            defaults: defaults)
        let service = FakeProPurchaseService(
            product: nil,
            currentStatus: .none,
            currentEnvironment: .production)
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()

        XCTAssertEqual(store.state, .locked)
        XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
    }

    func testVerifiedEntitlementUnlocksWhenProductMetadataFails() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let verifiedAt = Date(timeIntervalSince1970: 1_800_000_175)
        let service = FakeProPurchaseService(
            productError: FakeStoreKitError.productMetadataUnavailable,
            currentStatus: .verified(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: verifiedAt))
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()

        XCTAssertTrue(store.isProUnlocked)
        XCTAssertEqual(store.state, .unlocked(source: .storeKit))
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults)?.verifiedAt, verifiedAt)
    }

    func testRefreshRecoversAfterTransientProductMetadataFailure() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let service = FakeProPurchaseService(
            productError: FakeStoreKitError.productMetadataUnavailable,
            currentStatus: .none)
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()
        XCTAssertEqual(store.state, .error(FakeStoreKitError.productMetadataUnavailable.localizedDescription))

        service.productError = nil
        service.currentStatus = .verified(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_190))
        await store.refresh()

        XCTAssertTrue(store.isProUnlocked)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(service.currentEntitlementCallCount, 2)
        XCTAssertEqual(service.loadProductCallCount, 2)
    }

    func testProductionStyleStorageMigratesLegacyStandardCacheOnce() {
        let currentDefaults = Self.makeDefaults()
        let legacyDefaults = Self.makeDefaults()
        defer {
            Self.clear(currentDefaults)
            Self.clear(legacyDefaults)
        }
        let legacyCache = ProEntitlementCache(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_195))
        ProEntitlementCacheStore.save(legacyCache, defaults: legacyDefaults)

        let store = ProEntitlementStore(
            service: FakeProPurchaseService(),
            defaults: currentDefaults,
            legacyDefaults: legacyDefaults)

        XCTAssertEqual(store.state, .unlocked(source: .cache))
        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: currentDefaults), legacyCache)
        XCTAssertNil(legacyDefaults.data(forKey: ProEntitlementCacheStore.key))
    }

    func testLegacyProductionCacheSurvivesEmptySandboxRefresh() async {
        let currentDefaults = Self.makeDefaults()
        let legacyDefaults = Self.makeDefaults()
        defer {
            Self.clear(currentDefaults)
            Self.clear(legacyDefaults)
        }
        let legacyCache = ProEntitlementCache(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_196))
        ProEntitlementCacheStore.save(legacyCache, defaults: legacyDefaults)
        let service = FakeProPurchaseService(
            currentStatus: .none,
            currentEnvironment: .sandbox)
        let store = ProEntitlementStore(
            service: service,
            defaults: currentDefaults,
            legacyDefaults: legacyDefaults)

        await store.refresh()

        XCTAssertEqual(store.state, .unlocked(source: .cache))
        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: currentDefaults), legacyCache)
        XCTAssertNil(legacyDefaults.data(forKey: ProEntitlementCacheStore.key))
    }

    func testProductionCacheSurvivesEmptySandboxRefresh() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let cache = ProEntitlementCache(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_196),
            environment: .production)
        ProEntitlementCacheStore.save(cache, defaults: defaults)
        let service = FakeProPurchaseService(
            currentStatus: .none,
            currentEnvironment: .sandbox)
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()

        XCTAssertEqual(store.state, .unlocked(source: .cache))
        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults), cache)
    }

    func testFreshInstallStaysLockedAfterEmptySandboxRefresh() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let service = FakeProPurchaseService(
            currentStatus: .none,
            currentEnvironment: .sandbox)
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()

        XCTAssertEqual(store.state, .locked)
        XCTAssertFalse(store.isProUnlocked)
        XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
    }

    func testSandboxCacheDoesNotCarryIntoEmptyProductionEnvironment() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        ProEntitlementCacheStore.save(
            ProEntitlementCache(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_197),
                environment: .sandbox),
            defaults: defaults)
        let service = FakeProPurchaseService(
            currentStatus: .none,
            currentEnvironment: .production)
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()

        XCTAssertEqual(store.state, .locked)
        XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
    }

    func testProductionCacheClearsAfterEmptyProductionRefresh() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        ProEntitlementCacheStore.save(
            ProEntitlementCache(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_197),
                environment: .production),
            defaults: defaults)
        let service = FakeProPurchaseService(
            currentStatus: .none,
            currentEnvironment: .production)
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()

        XCTAssertEqual(store.state, .locked)
        XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
    }

    func testSandboxCacheClearsAfterEmptySandboxRefresh() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        ProEntitlementCacheStore.save(
            ProEntitlementCache(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_197),
                environment: .sandbox),
            defaults: defaults)
        let service = FakeProPurchaseService(
            currentStatus: .none,
            currentEnvironment: .sandbox)
        let store = ProEntitlementStore(service: service, defaults: defaults)

        await store.refresh()

        XCTAssertEqual(store.state, .locked)
        XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
    }

    func testEmptyUnknownEnvironmentPreservesOnlyProductionCache() async {
        for cacheEnvironment in ProEntitlementEnvironment.allTestCases {
            let defaults = Self.makeDefaults()
            defer { Self.clear(defaults) }
            let cache = ProEntitlementCache(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_197),
                environment: cacheEnvironment)
            ProEntitlementCacheStore.save(cache, defaults: defaults)
            let service = FakeProPurchaseService(
                currentStatus: .none,
                currentEnvironment: .unknown)
            let store = ProEntitlementStore(service: service, defaults: defaults)

            await store.refresh()

            if cacheEnvironment == .production {
                XCTAssertEqual(store.state, .unlocked(source: .cache))
                XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults), cache)
            } else {
                XCTAssertEqual(store.state, .locked, "cache environment: \(cacheEnvironment)")
                XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
            }
        }
    }

    func testAuthoritativeRevocationClearsCurrentAndLegacyCaches() async {
        let currentDefaults = Self.makeDefaults()
        let legacyDefaults = Self.makeDefaults()
        defer {
            Self.clear(currentDefaults)
            Self.clear(legacyDefaults)
        }
        let store = ProEntitlementStore(
            service: FakeProPurchaseService(),
            defaults: currentDefaults,
            legacyDefaults: legacyDefaults)
        let staleCache = ProEntitlementCache(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_198))
        ProEntitlementCacheStore.save(staleCache, defaults: currentDefaults)
        ProEntitlementCacheStore.save(staleCache, defaults: legacyDefaults)

        await store.apply(.revoked(productID: ProductConfig.storeKitLifetimeProductID))

        XCTAssertEqual(store.state, .locked)
        XCTAssertNil(currentDefaults.data(forKey: ProEntitlementCacheStore.key))
        XCTAssertNil(legacyDefaults.data(forKey: ProEntitlementCacheStore.key))
        XCTAssertNil(ProEntitlementCacheStorage(
            currentDefaults: currentDefaults,
            legacyDefaults: legacyDefaults).load())
    }

    func testRevocationEnvironmentMatrixProtectsProductionFromTestEnvironments() async {
        for cacheEnvironment in ProEntitlementEnvironment.allTestCases {
            for revocationEnvironment in ProEntitlementEnvironment.allTestCases {
                let defaults = Self.makeDefaults()
                defer { Self.clear(defaults) }
                let cache = ProEntitlementCache(
                    productID: ProductConfig.storeKitLifetimeProductID,
                    verifiedAt: Date(timeIntervalSince1970: 1_800_000_198),
                    environment: cacheEnvironment)
                ProEntitlementCacheStore.save(cache, defaults: defaults)
                let store = ProEntitlementStore(
                    service: FakeProPurchaseService(),
                    defaults: defaults)

                await store.apply(StoreKitEntitlementSnapshot(
                    status: .revoked(productID: ProductConfig.storeKitLifetimeProductID),
                    environment: revocationEnvironment))

                let shouldClear = revocationEnvironment == .production ||
                    cacheEnvironment != .production
                if shouldClear {
                    XCTAssertEqual(
                        store.state,
                        .locked,
                        "cache: \(cacheEnvironment), revocation: \(revocationEnvironment)")
                    XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
                } else {
                    XCTAssertEqual(
                        store.state,
                        .unlocked(source: .cache),
                        "cache: \(cacheEnvironment), revocation: \(revocationEnvironment)")
                    XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults), cache)
                }
            }
        }
    }

    func testVerifiedRevokedTransactionMapsToRevokedEntitlement() {
        let status = StoreKitPurchaseService.verifiedEntitlementStatus(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_199),
            revocationDate: Date(timeIntervalSince1970: 1_800_000_200))

        XCTAssertEqual(status, .revoked(productID: ProductConfig.storeKitLifetimeProductID))
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

    func testCacheClearRemovesLegacySourcesBeforeCurrentAppGroupCache() throws {
        let source = try String(
            contentsOf: Self.projectRoot().appendingPathComponent(
                "CodexBarMobile/CodexBarMobile/StoreKit/ProEntitlementCache.swift"),
            encoding: .utf8)
        guard let clearStart = source.range(of: "    func clear() {"),
              let clearEnd = source.range(
                  of: "    private var distinctLegacyDefaults",
                  range: clearStart.upperBound..<source.endIndex)
        else {
            XCTFail("Unable to locate ProEntitlementCacheStorage.clear")
            return
        }
        let clearBody = source[clearStart.lowerBound..<clearEnd.lowerBound]
        guard let legacyClear = clearBody.range(of: "self.clearLegacyCopies()"),
              let currentClear = clearBody.range(of: "self.currentDefaults.removeObject")
        else {
            XCTFail("Unable to locate coordinated cache clear operations")
            return
        }

        XCTAssertLessThan(legacyClear.lowerBound, currentClear.lowerBound)
    }

    func testPurchaseInvalidatesSuspendedRefreshSnapshot() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let verifiedAt = Date(timeIntervalSince1970: 1_800_000_210)
        let service = SuspendingProductPurchaseService(
            purchaseOutcome: .purchased(StoreKitEntitlementSnapshot(
                status: .verified(
                    productID: ProductConfig.storeKitLifetimeProductID,
                    verifiedAt: verifiedAt),
                environment: .production)))
        let store = ProEntitlementStore(service: service, defaults: defaults)

        let refreshTask = Task { await store.refresh() }
        await service.waitUntilProductLoadIsSuspended()
        await store.purchase()
        service.resumeProductLoad()
        await refreshTask.value

        XCTAssertEqual(store.state, .unlocked(source: .storeKit))
        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults)?.verifiedAt, verifiedAt)
    }

    func testRestoreInvalidatesSuspendedRefreshSnapshot() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let verifiedAt = Date(timeIntervalSince1970: 1_800_000_220)
        let service = SuspendingProductPurchaseService(
            restoreSnapshot: StoreKitEntitlementSnapshot(
                status: .verified(
                    productID: ProductConfig.storeKitLifetimeProductID,
                    verifiedAt: verifiedAt),
                environment: .production))
        let store = ProEntitlementStore(service: service, defaults: defaults)

        let refreshTask = Task { await store.refresh() }
        await service.waitUntilProductLoadIsSuspended()
        await store.restorePurchases()
        service.resumeProductLoad()
        await refreshTask.value

        XCTAssertEqual(store.state, .unlocked(source: .storeKit))
        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults)?.verifiedAt, verifiedAt)
    }

    func testTransactionUpdateInvalidatesSuspendedRefreshSnapshot() async {
        let defaults = Self.makeDefaults()
        defer { Self.clear(defaults) }
        let verifiedAt = Date(timeIntervalSince1970: 1_800_000_230)
        let service = SuspendingProductPurchaseService()
        let store = ProEntitlementStore(service: service, defaults: defaults)

        let refreshTask = Task { await store.refresh() }
        await service.waitUntilProductLoadIsSuspended()
        await store.apply(StoreKitEntitlementSnapshot(
            status: .verified(
                productID: ProductConfig.storeKitLifetimeProductID,
                verifiedAt: verifiedAt),
            environment: .production))
        service.resumeProductLoad()
        await refreshTask.value

        XCTAssertEqual(store.state, .unlocked(source: .storeKit))
        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults)?.verifiedAt, verifiedAt)
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
        ])
        XCTAssertTrue(FeatureGate.allCases.allSatisfy(\.requiresPro))
    }

    func testProFeatureAccessLocksEveryV1FeatureForFreeRealData() {
        for feature in FeatureGate.allCases {
            XCTAssertFalse(ProFeatureAccess.isUnlocked(
                feature,
                isDemoMode: false,
                isProUnlocked: false))
            XCTAssertTrue(ProFeatureAccess.isLocked(
                feature,
                isDemoMode: false,
                isProUnlocked: false))
        }
    }

    func testProFeatureAccessUnlocksEveryV1FeatureForProRealData() {
        for feature in FeatureGate.allCases {
            XCTAssertTrue(ProFeatureAccess.isUnlocked(
                feature,
                isDemoMode: false,
                isProUnlocked: true))
            XCTAssertFalse(ProFeatureAccess.isLocked(
                feature,
                isDemoMode: false,
                isProUnlocked: true))
        }
    }

    func testProFeatureAccessUnlocksEveryV1FeatureForDemoMode() {
        for feature in FeatureGate.allCases {
            XCTAssertTrue(ProFeatureAccess.isUnlocked(
                feature,
                isDemoMode: true,
                isProUnlocked: false))
            XCTAssertFalse(ProFeatureAccess.isLocked(
                feature,
                isDemoMode: true,
                isProUnlocked: false))
        }
    }

    func testAdvancedMergeGateUsesSameFreeRealDataPolicy() {
        XCTAssertFalse(ProFeatureAccess.isUnlocked(
            .advancedMergeViews,
            isDemoMode: false,
            isProUnlocked: false))
        XCTAssertTrue(ProFeatureAccess.isUnlocked(
            .advancedMergeViews,
            isDemoMode: false,
            isProUnlocked: true))
        XCTAssertTrue(ProFeatureAccess.isUnlocked(
            .advancedMergeViews,
            isDemoMode: true,
            isProUnlocked: false))
    }

    func testSharedSchemeUsesStoreKitConfigurationForRunAction() throws {
        let schemeXML = try String(
            contentsOf: Self.projectRoot()
                .appendingPathComponent(
                    "CodexBarMobile/CodexBarMobile.xcodeproj/xcshareddata/xcschemes/CodexBarMobile.xcscheme"),
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
        defaults.removeObject(forKey: ProEntitlementCacheStore.legacyWidgetProCacheKey)
    }

    private static func projectRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }
}

extension ProEntitlementEnvironment {
    fileprivate static let allTestCases: [Self] = [.production, .sandbox, .xcode, .unknown]
}

@MainActor
private final class SuspendingProductPurchaseService: ProPurchaseServicing {
    private let purchaseOutcome: StoreKitPurchaseOutcome
    private let restoreSnapshot: StoreKitEntitlementSnapshot
    private var productLoadContinuation: CheckedContinuation<ProProductInfo?, Never>?
    private var productLoadStartedContinuation: CheckedContinuation<Void, Never>?

    init(
        purchaseOutcome: StoreKitPurchaseOutcome = .cancelled,
        restoreSnapshot: StoreKitEntitlementSnapshot = StoreKitEntitlementSnapshot(
            status: .none,
            environment: .production))
    {
        self.purchaseOutcome = purchaseOutcome
        self.restoreSnapshot = restoreSnapshot
    }

    func loadProduct() async throws -> ProProductInfo? {
        await withCheckedContinuation { continuation in
            self.productLoadContinuation = continuation
            self.productLoadStartedContinuation?.resume()
            self.productLoadStartedContinuation = nil
        }
    }

    func waitUntilProductLoadIsSuspended() async {
        if self.productLoadContinuation != nil { return }
        await withCheckedContinuation { continuation in
            self.productLoadStartedContinuation = continuation
        }
    }

    func resumeProductLoad() {
        self.productLoadContinuation?.resume(returning: ProProductInfo(
            id: ProductConfig.storeKitLifetimeProductID,
            displayName: "QuotaKit Pro",
            description: "Unlock QuotaKit Pro for life.",
            displayPrice: ProductConfig.launchPriceCopy))
        self.productLoadContinuation = nil
    }

    func purchase() async throws -> StoreKitPurchaseOutcome {
        self.purchaseOutcome
    }

    func restorePurchases() async throws -> StoreKitEntitlementSnapshot {
        self.restoreSnapshot
    }

    func currentEntitlementStatus() async -> StoreKitEntitlementSnapshot {
        StoreKitEntitlementSnapshot(status: .none, environment: .production)
    }

    nonisolated func transactionUpdates() -> AsyncStream<StoreKitEntitlementSnapshot> {
        AsyncStream { $0.finish() }
    }
}

private final class FakeProPurchaseService: ProPurchaseServicing, @unchecked Sendable {
    var product: ProProductInfo?
    var productError: Error?
    var purchaseOutcome: StoreKitPurchaseOutcome
    var restoreStatus: StoreKitEntitlementStatus
    var currentStatus: StoreKitEntitlementStatus
    var restoreEnvironment: ProEntitlementEnvironment
    var currentEnvironment: ProEntitlementEnvironment
    var loadProductCallCount = 0
    var currentEntitlementCallCount = 0
    var purchaseCallCount = 0
    var restoreCallCount = 0

    init(
        product: ProProductInfo? = ProProductInfo(
            id: ProductConfig.storeKitLifetimeProductID,
            displayName: "QuotaKit Pro",
            description: "Unlock QuotaKit Pro for life.",
            displayPrice: ProductConfig.launchPriceCopy),
        productError: Error? = nil,
        purchaseOutcome: StoreKitPurchaseOutcome = .cancelled,
        restoreStatus: StoreKitEntitlementStatus = .none,
        currentStatus: StoreKitEntitlementStatus = .none,
        restoreEnvironment: ProEntitlementEnvironment = .sandbox,
        currentEnvironment: ProEntitlementEnvironment = .sandbox)
    {
        self.product = product
        self.productError = productError
        self.purchaseOutcome = purchaseOutcome
        self.restoreStatus = restoreStatus
        self.currentStatus = currentStatus
        self.restoreEnvironment = restoreEnvironment
        self.currentEnvironment = currentEnvironment
    }

    func loadProduct() async throws -> ProProductInfo? {
        self.loadProductCallCount += 1
        if let productError {
            throw productError
        }
        return self.product
    }

    func purchase() async throws -> StoreKitPurchaseOutcome {
        self.purchaseCallCount += 1
        return self.purchaseOutcome
    }

    func restorePurchases() async throws -> StoreKitEntitlementSnapshot {
        self.restoreCallCount += 1
        return StoreKitEntitlementSnapshot(
            status: self.restoreStatus,
            environment: self.restoreEnvironment)
    }

    func currentEntitlementStatus() async -> StoreKitEntitlementSnapshot {
        self.currentEntitlementCallCount += 1
        return StoreKitEntitlementSnapshot(
            status: self.currentStatus,
            environment: self.currentEnvironment)
    }

    nonisolated func transactionUpdates() -> AsyncStream<StoreKitEntitlementSnapshot> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private enum FakeStoreKitError: LocalizedError {
    case productMetadataUnavailable

    var errorDescription: String? {
        "Product metadata unavailable"
    }
}
