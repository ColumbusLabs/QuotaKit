import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite("SyncCoordinator descriptor pace", .serialized)
struct SyncCoordinatorDescriptorPaceTests {
    private func syncedProvider(
        _ provider: UsageProvider,
        snapshot: UsageSnapshot,
        suite: String) async throws -> ProviderUsageSnapshot
    {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite))
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: provider,
            metadata: #require(ProviderDefaults.metadata[provider]),
            enabled: true)

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(snapshot, provider: provider)

        let sync = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: sync)
        await coordinator.pushCurrentSnapshot()
        return try #require(sync.lastPerProviderEnvelopes
            .first { $0.provider.providerID == provider.rawValue }?
            .provider)
    }

    @Test
    func `Grok weekly reset window produces descriptor backed pace`() async throws {
        let now = Date()
        let provider = try await self.syncedProvider(
            .grok,
            snapshot: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 25,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                    resetDescription: "Weekly reset"),
                secondary: nil,
                updatedAt: now),
            suite: "SyncCoord-descriptor-pace-grok")

        let credits = try #require(provider.rateWindows.first { $0.label == "Credits" })
        #expect(credits.pace != nil)
    }

    @Test
    func `descriptor pace below the Mac display threshold stays nil`() async throws {
        let now = Date()
        let provider = try await self.syncedProvider(
            .grok,
            snapshot: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 1,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: now.addingTimeInterval((7 * 24 - 1) * 60 * 60),
                    resetDescription: "Weekly reset"),
                secondary: nil,
                updatedAt: now),
            suite: "SyncCoord-descriptor-pace-threshold")

        let credits = try #require(provider.rateWindows.first { $0.label == "Credits" })
        #expect(credits.pace == nil)
    }
}
