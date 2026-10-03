import CodexBarSync
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import CodexBarMobile

@MainActor
final class QuotaKitProViewSmokeTests: XCTestCase {
    private nonisolated static let remoteConfigSuiteName = "com.columbuslabs.quotakit.tests.pro-smoke"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: MobileSettingsKeys.freeSelectedProviderID)
        UserDefaults.standard.removeObject(forKey: MobileSettingsKeys.freeSelectedProviderLockedUntil)
        QuotaKitWidgetDisplayModeStore.appGroupDefaults()?
            .removeObject(forKey: QuotaKitWidgetDisplayModeStore.key)
        QuotaKitWidgetProviderPreferencesStore.appGroupDefaults()?
            .removeObject(forKey: QuotaKitWidgetProviderPreferencesStore.providerOrderKey)
        QuotaKitWidgetProviderPreferencesStore.appGroupDefaults()?
            .removeObject(forKey: QuotaKitWidgetProviderPreferencesStore.selectedProviderKey)
        UserDefaults.standard.removePersistentDomain(forName: Self.remoteConfigSuiteName)
        UserDefaults(suiteName: Self.remoteConfigSuiteName)?
            .removePersistentDomain(forName: Self.remoteConfigSuiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MobileSettingsKeys.freeSelectedProviderID)
        UserDefaults.standard.removeObject(forKey: MobileSettingsKeys.freeSelectedProviderLockedUntil)
        QuotaKitWidgetDisplayModeStore.appGroupDefaults()?
            .removeObject(forKey: QuotaKitWidgetDisplayModeStore.key)
        QuotaKitWidgetProviderPreferencesStore.appGroupDefaults()?
            .removeObject(forKey: QuotaKitWidgetProviderPreferencesStore.providerOrderKey)
        QuotaKitWidgetProviderPreferencesStore.appGroupDefaults()?
            .removeObject(forKey: QuotaKitWidgetProviderPreferencesStore.selectedProviderKey)
        super.tearDown()
    }

    func testLockedSettingsProSectionRenders() {
        let view = List {
            Section {
                QuotaKitProSettingsView(store: .preview(state: .locked))
            }
        }

        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
        self.attachIAPReviewScreenshot(from: self.iapReviewScreenshotView())
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

    func testProviderDailySpendAxisRendersLongHistoryAtNarrowWidth() throws {
        let previousStyle = UserDefaults.standard.object(forKey: MobileSettingsKeys.usageCostChartStyle)
        defer {
            if let previousStyle {
                UserDefaults.standard.set(previousStyle, forKey: MobileSettingsKeys.usageCostChartStyle)
            } else {
                UserDefaults.standard.removeObject(forKey: MobileSettingsKeys.usageCostChartStyle)
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let latestDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3)))
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        for historyDays in [30, 365] {
            let daily = try (0..<historyDays).reversed().map { daysAgo in
                let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -daysAgo, to: latestDate))
                return SyncDailyPoint(
                    dayKey: formatter.string(from: date),
                    costUSD: Double(daysAgo % 8 + 1),
                    totalTokens: 1000)
            }
            let provider = ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex", primary: nil, secondary: nil,
                accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
                lastUpdated: latestDate,
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil, sessionTokens: nil, last30DaysCostUSD: nil,
                    last30DaysTokens: nil, daily: daily, historyDays: historyDays))
            for style in CostChartStyle.allCases {
                UserDefaults.standard.set(style.rawValue, forKey: MobileSettingsKeys.usageCostChartStyle)
                let view = NavigationStack {
                    ProviderDetailView(provider: provider, isDemoMode: true)
                }
                .environment(ProEntitlementStore.preview(state: .unlocked(source: .storeKit)))
                .preferredColorScheme(.dark)
                let image = try XCTUnwrap(self.renderToImage(view, size: CGSize(width: 320, height: 900)))
                let attachment = XCTAttachment(image: image)
                attachment.name = "provider-daily-spend-\(historyDays)-\(style.rawValue)-320pt"
                attachment.lifetime = .keepAlways
                self.add(attachment)
            }
        }
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

    func testUsageSettingsRendersWidgetDisplayPicker() {
        let view = NavigationStack {
            UsageSettingsView(initialWidgetDisplayMode: .both)
        }
        .environment(ProEntitlementStore.preview(state: .unlocked(source: .storeKit)))

        XCTAssertNotNil(self.renderToImage(view))
    }

    func testUsageSettingsWidgetDisplayOptionsIncludeAllModes() {
        let options = UsageSettingsView.widgetDisplayModeOptions

        XCTAssertEqual(options.map(\.0), [.both, .session, .weekly])
        XCTAssertEqual(options.map(\.1), ["Both", "Session", "Weekly"])
    }

    func testUsageSettingsWidgetDisplayBindingSavesChangedValueOnce() {
        var currentMode = QuotaKitWidgetDisplayMode.both
        var savedModes: [QuotaKitWidgetDisplayMode] = []
        let binding = UsageSettingsView.widgetDisplayModeBinding(
            value: Binding(
                get: { currentMode },
                set: { currentMode = $0 }),
            save: { savedModes.append($0) })

        binding.wrappedValue = .weekly
        binding.wrappedValue = .weekly

        XCTAssertEqual(currentMode, .weekly)
        XCTAssertEqual(savedModes, [.weekly])
    }

    func testUsageSettingsWidgetDisplaySaveWritesRawValueAndReloadsTimelines() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "quotakit.usage-settings.\(UUID().uuidString)"))
        var reloadCount = 0

        UsageSettingsView.saveWidgetDisplayMode(
            .weekly,
            defaults: defaults,
            reloadTimelines: { reloadCount += 1 })

        XCTAssertEqual(
            defaults.string(forKey: QuotaKitWidgetDisplayModeStore.key),
            QuotaKitWidgetDisplayMode.weekly.rawValue)
        XCTAssertEqual(reloadCount, 1)
    }

    private func renderToImage(_ view: some View, size: CGSize = CGSize(width: 390, height: 900)) -> UIImage? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            XCTFail("Could not find a foreground window scene for view rendering")
            return nil
        }

        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let hostingController = UIHostingController(rootView: view
            .environment(RemoteConfigStore(defaults: UserDefaults(suiteName: Self.remoteConfigSuiteName)))
            .frame(width: size.width, height: size.height)
            .quotaKitThemed())
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        window.layoutIfNeeded()
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            hostingController.view.drawHierarchy(in: hostingController.view.bounds, afterScreenUpdates: true)
        }

        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
        return image
    }

    private func attachIAPReviewScreenshot(from view: some View) {
        let renderer = ImageRenderer(content: view
            .environment(RemoteConfigStore(defaults: UserDefaults(suiteName: Self.remoteConfigSuiteName)))
            .preferredColorScheme(.dark)
            .frame(width: 320, height: 460)
            .quotaKitThemed())
        renderer.scale = 2.0

        guard let image = renderer.uiImage else {
            XCTFail("Could not render IAP review screenshot")
            return
        }

        let attachment = XCTAttachment(image: image)
        attachment.name = "iap_review_screenshot"
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }

    private func iapReviewScreenshotView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("QuotaKit Pro")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(QuotaKitTheme.dark.textPrimary)
                Text("Lifetime unlock")
                    .font(.subheadline)
                    .foregroundStyle(QuotaKitTheme.dark.textMuted)
            }

            QuotaKitProSettingsView(store: .preview(state: .locked))

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(QuotaKitTheme.dark.canvas)
    }
}
