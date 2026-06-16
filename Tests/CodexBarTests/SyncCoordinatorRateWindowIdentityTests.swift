import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

extension SyncCoordinatorTests {
    private func makeRateWindowIdentitySettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func makeRateWindowIdentityUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }

    @Test
    func kimiPerProviderRateWindowsUseSemanticIdentities() async throws {
        let settings = self.makeRateWindowIdentitySettingsStore(suite: "SyncCoord-kimi-rate-window-identities")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .kimi,
            metadata: #require(ProviderDefaults.metadata[.kimi]),
            enabled: true)

        let store = self.makeRateWindowIdentityUsageStore(settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 24,
                    windowMinutes: nil,
                    resetsAt: Date(timeIntervalSince1970: 1_700_604_800),
                    resetDescription: "24/100 requests"),
                secondary: RateWindow(
                    usedPercent: 75,
                    windowMinutes: 300,
                    resetsAt: Date(timeIntervalSince1970: 1_700_018_000),
                    resetDescription: "Rate: 15/20 per 5 hours"),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .kimi)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastPerProviderEnvelopes
            .first { $0.provider.providerID == UsageProvider.kimi.rawValue }?
            .provider)
        let weekly = try #require(provider.rateWindows.first { $0.label == "Weekly" })
        let rateLimit = try #require(provider.rateWindows.first { $0.label == "Rate Limit" })

        #expect(weekly.identity == .weekly)
        #expect(rateLimit.identity == .session)
    }
}
