import SwiftData
import SwiftUI
import XCTest

@testable import CodexBarMobile

@MainActor
final class QuotaKitProViewSmokeTests: XCTestCase {
    nonisolated private static let remoteConfigSuiteName = "com.columbuslabs.quotakit.tests.pro-smoke"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: MobileSettingsKeys.freeSelectedProviderID)
        UserDefaults.standard.removePersistentDomain(forName: Self.remoteConfigSuiteName)
        UserDefaults(suiteName: Self.remoteConfigSuiteName)?
            .removePersistentDomain(forName: Self.remoteConfigSuiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MobileSettingsKeys.freeSelectedProviderID)
        super.tearDown()
    }

    func testLockedSettingsProSectionRenders() {
        let view = List {
            Section {
                QuotaKitProSettingsView(store: .preview(state: .locked))
            }
        }

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testUnlockedSettingsProSectionRenders() {
        let view = List {
            Section {
                QuotaKitProSettingsView(store: .preview(state: .unlocked(source: .storeKit)))
            }
        }

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testLockedUsageListRendersWithProSummary() {
        UserDefaults.standard.set("claude", forKey: MobileSettingsKeys.freeSelectedProviderID)
        let view = ProviderListView(
            snapshot: PreviewData.sampleSnapshot,
            usageData: PreviewData.makeSyncedUsageData(),
            isDemoMode: false)
            .environment(ProEntitlementStore.preview(state: .locked))

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testUnlockedUsageListRendersAllProviders() {
        let view = ProviderListView(
            snapshot: PreviewData.sampleSnapshot,
            usageData: PreviewData.makeSyncedUsageData(),
            isDemoMode: false)
            .environment(ProEntitlementStore.preview(state: .unlocked(source: .storeKit)))

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testLockedCostTabRendersProState() {
        let view = CostTab(
            usageData: PreviewData.makeSyncedUsageData(),
            isDemoMode: .constant(false))
            .environment(ProEntitlementStore.preview(state: .locked))

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testUnlockedCostTabRendersDashboard() {
        let view = CostTab(
            usageData: PreviewData.makeSyncedUsageData(),
            isDemoMode: .constant(false))
            .environment(ProEntitlementStore.preview(state: .unlocked(source: .storeKit)))

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testDemoCostTabRendersDashboardWhenLocked() {
        let view = CostTab(
            usageData: PreviewData.makeSyncedUsageData(),
            isDemoMode: .constant(true))
            .environment(ProEntitlementStore.preview(state: .locked))

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testDemoUsageListRendersWhenProIsLocked() {
        let view = ProviderListView(
            snapshot: PreviewData.sampleSnapshot,
            usageData: PreviewData.makeSyncedUsageData(),
            isDemoMode: true)
            .environment(ProEntitlementStore.preview(state: .locked))

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testLockedProviderDetailRendersProCard() {
        let view = NavigationStack {
            ProviderDetailView(provider: PreviewData.claudeProvider)
        }
        .environment(ProEntitlementStore.preview(state: .locked))

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testUnlockedProviderDetailRendersHistoryAndCostDetails() {
        let view = NavigationStack {
            ProviderDetailView(provider: PreviewData.claudeProvider)
        }
        .environment(ProEntitlementStore.preview(state: .unlocked(source: .storeKit)))

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testDemoProviderDetailRendersHistoryAndCostDetailsWhenLocked() {
        let view = NavigationStack {
            ProviderDetailView(provider: PreviewData.claudeProvider, isDemoMode: true)
        }
        .environment(ProEntitlementStore.preview(state: .locked))

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testLockedCostSettingsRenders() {
        let view = NavigationStack {
            CostSettingsView(isDemoMode: false)
        }
        .environment(ProEntitlementStore.preview(state: .locked))
        .modelContainer(ModelContainerFactory.shared())

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testDemoCostSettingsRendersUnlockedWhenProIsLocked() {
        let view = NavigationStack {
            CostSettingsView(isDemoMode: true)
        }
        .environment(ProEntitlementStore.preview(state: .locked))
        .modelContainer(ModelContainerFactory.shared())

        XCTAssertNotNil(self.renderToImage(view))
    }

    private func renderToImage<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view
            .environment(RemoteConfigStore(defaults: UserDefaults(suiteName: Self.remoteConfigSuiteName)))
            .frame(width: 390, height: 900)
            .quotaKitThemed())
        renderer.scale = 2.0
        return renderer.uiImage
    }
}
