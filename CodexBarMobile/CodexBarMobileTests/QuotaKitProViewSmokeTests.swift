import SwiftUI
import XCTest

@testable import CodexBarMobile

@MainActor
final class QuotaKitProViewSmokeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: MobileSettingsKeys.freeSelectedProviderID)
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

    private func renderToImage<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 390, height: 900))
        renderer.scale = 2.0
        return renderer.uiImage
    }
}
