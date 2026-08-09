import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

extension SyncCoordinatorTests {
    @Test
    func `Codex per-provider sync caps session while weekly quota is exhausted`() async throws {
        let suite = "SyncCoord-codex-weekly-cap-sync"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite))
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let weeklyReset = Date(timeIntervalSince1970: 4_102_444_800)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 1,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 100,
                    windowMinutes: 10080,
                    resetsAt: weeklyReset,
                    resetDescription: "Weekly resets later"),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastPerProviderEnvelopes
            .first { $0.provider.providerID == UsageProvider.codex.rawValue }?
            .provider)
        let session = try #require(provider.rateWindows.first { $0.identity == .session })
        let weekly = try #require(provider.rateWindows.first { $0.identity == .weekly })

        #expect(session.usedPercent == 100)
        #expect(session.remainingPercent == 0)
        #expect(session.resetsAt == weeklyReset)
        #expect(session.resetDescription == "Weekly resets later")
        #expect(weekly.usedPercent == 100)
    }
}
