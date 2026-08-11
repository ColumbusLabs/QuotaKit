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
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
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
    func `Copilot reset date produces descriptor backed pace`() async throws {
        let now = Date()
        let provider = try await self.syncedProvider(
            .copilot,
            snapshot: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 20,
                    windowMinutes: nil,
                    resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60),
                    resetDescription: "Monthly reset"),
                secondary: nil,
                updatedAt: now),
            suite: "SyncCoord-descriptor-pace-copilot")

        let premium = try #require(provider.rateWindows.first { $0.label == "Premium" })
        #expect(premium.pace != nil)
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

    @Test
    func `Doubao tertiary monthly sentinel uses calendar duration and rejects unsupported extras`() async throws {
        let reset = Date(timeIntervalSince1970: 1_775_001_600) // 2026-04-01 00:00:00 UTC
        let normalized = SyncCoordinator.resetWindowForPace(
            provider: .doubao,
            window: RateWindow(
                usedPercent: 50,
                windowMinutes: ProviderPaceCapability.monthlyWindowSentinelMinutes,
                resetsAt: reset,
                resetDescription: nil))
        #expect(normalized.windowMinutes == 31 * 24 * 60)

        let now = Date()
        let provider = try await self.syncedProvider(
            .doubao,
            snapshot: UsageSnapshot(
                primary: nil,
                secondary: nil,
                tertiary: RateWindow(
                    usedPercent: 50,
                    windowMinutes: ProviderPaceCapability.monthlyWindowSentinelMinutes,
                    resetsAt: now.addingTimeInterval(10 * 24 * 60 * 60),
                    resetDescription: "Monthly reset"),
                extraRateWindows: [
                    NamedRateWindow(
                        id: "unsupported-weekly",
                        title: "Unsupported",
                        window: RateWindow(
                            usedPercent: 50,
                            windowMinutes: 7 * 24 * 60,
                            resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                            resetDescription: nil)),
                ],
                updatedAt: now),
            suite: "SyncCoord-descriptor-pace-doubao")

        let monthly = try #require(provider.rateWindows.first { $0.label == "Monthly" })
        let unsupported = try #require(provider.rateWindows.first { $0.label == "Unsupported" })
        #expect(monthly.pace != nil)
        #expect(unsupported.pace == nil)
    }
}
