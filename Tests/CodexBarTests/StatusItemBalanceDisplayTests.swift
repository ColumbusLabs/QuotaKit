import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct StatusItemBalanceDisplayTests {
    @Test
    func `menu bar display text skips exhausted cursor api subquota when auto remains usable`() {
        let settings = self.makeSettings(
            suiteName: "StatusItemBalanceDisplayTests-cursor-exhausted-api",
            provider: .cursor)
        settings.usageBarsShowUsed = false
        settings.setMenuBarMetricPreference(.automatic, for: .cursor)
        let (store, controller) = self.makeStoreAndController(settings: settings)
        defer { controller.releaseStatusItemsForTesting() }
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 34,
                windowMinutes: 30 * 24 * 60,
                resetsAt: nil,
                resetDescription: "Auto"),
            secondary: RateWindow(
                usedPercent: 100,
                windowMinutes: 30 * 24 * 60,
                resetsAt: nil,
                resetDescription: "API"),
            tertiary: nil,
            updatedAt: Date())

        store._setSnapshotForTesting(snapshot, provider: .cursor)
        store._setErrorForTesting(nil, provider: .cursor)

        let displayText = controller.menuBarDisplayText(for: .cursor, snapshot: snapshot)

        #expect(displayText == "66%")
    }

    @Test
    func `debug bundle identity updates status item accessibility`() {
        #expect(StatusItemController.isDebugApp(bundleIdentifier: "com.columbuslabs.quotakit.mac.debug"))
        #expect(!StatusItemController.isDebugApp(bundleIdentifier: "com.columbuslabs.quotakit.mac"))
        #expect(!StatusItemController.isDebugApp(bundleIdentifier: nil))
        #expect(StatusItemController.statusItemAccessibilityTitle(isDebugApp: true) == "QuotaKit Debug")
        #expect(StatusItemController.statusItemAccessibilityTitle(isDebugApp: false) == "QuotaKit")
    }

    private func makeSettings(suiteName: String, provider: UsageProvider) -> SettingsStore {
        let settings = testSettingsStore(suiteName: suiteName)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = provider.instanceID
        settings.menuBarDisplayMode = .both
        settings.usageBarsShowUsed = true

        if let metadata = ProviderRegistry.shared.metadata[provider] {
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: true)
        }
        return settings
    }

    private func makeStoreAndController(settings: SettingsStore) -> (UsageStore, StatusItemController) {
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        return (store, controller)
    }
}
