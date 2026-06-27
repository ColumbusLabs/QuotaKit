import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct SyncCoordinatorCursorRateWindowTests {
    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }

    @Test
    func pushExportsCursorAutoAndAPIWindowsWithBillingCyclePace() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-cursor-auto-api-pace")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .cursor,
            metadata: #require(ProviderDefaults.metadata[.cursor]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let reset = Date().addingTimeInterval(6 * 24 * 60 * 60)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 90,
                    windowMinutes: 30 * 24 * 60,
                    resetsAt: reset,
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 85,
                    windowMinutes: 30 * 24 * 60,
                    resetsAt: reset,
                    resetDescription: nil),
                tertiary: nil,
                cursorRateWindowLayout: .autoAPI,
                updatedAt: Date()),
            provider: .cursor)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == UsageProvider.cursor.rawValue }))
        #expect(provider.rateWindows.map(\.label) == ["Auto", "API"])
        #expect(provider.primary?.label == "Auto")
        #expect(provider.secondary?.label == "API")
        #expect(provider.primary?.identity == .weekly)
        #expect(provider.secondary?.identity == .weekly)
        #expect(provider.primary?.pace != nil)
        #expect(provider.secondary?.pace != nil)
    }

    @Test
    func pushExportsCursorPlanFallbackLabelAndIdentity() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-cursor-plan-fallback")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .cursor,
            metadata: #require(ProviderDefaults.metadata[.cursor]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let reset = Date().addingTimeInterval(6 * 24 * 60 * 60)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 73,
                    windowMinutes: 30 * 24 * 60,
                    resetsAt: reset,
                    resetDescription: nil),
                secondary: nil,
                tertiary: nil,
                cursorRateWindowLayout: .plan,
                updatedAt: Date()),
            provider: .cursor)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == UsageProvider.cursor.rawValue }))
        #expect(provider.rateWindows.map(\.label) == ["Plan"])
        #expect(provider.primary?.identity == .weekly)
        #expect(provider.primary?.pace != nil)
    }
}
