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

    private func syncedProvider(
        _ provider: UsageProvider,
        snapshot: UsageSnapshot,
        suite: String) async throws -> ProviderUsageSnapshot
    {
        let settings = self.makeRateWindowIdentitySettingsStore(suite: suite)
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: provider,
            metadata: #require(ProviderDefaults.metadata[provider]),
            enabled: true)

        let store = self.makeRateWindowIdentityUsageStore(settings: settings)
        store._setSnapshotForTesting(snapshot, provider: provider)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        return try #require(mock.lastPerProviderEnvelopes
            .first { $0.provider.providerID == provider.rawValue }?
            .provider)
    }

    @Test
    func `amp subscription sync uses dynamic usage lane labels`() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = try await self.syncedProvider(
            .amp,
            snapshot: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 20,
                    windowMinutes: ProviderPaceCapability.monthlyWindowSentinelMinutes,
                    resetsAt: now,
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 30,
                    windowMinutes: ProviderPaceCapability.monthlyWindowSentinelMinutes,
                    resetsAt: now,
                    resetDescription: nil),
                extraRateWindows: [NamedRateWindow(
                    id: "amp-free",
                    title: "Amp Free",
                    window: RateWindow(
                        usedPercent: 40,
                        windowMinutes: 24 * 60,
                        resetsAt: now,
                        resetDescription: "resets daily"))],
                ampUsage: AmpUsageDetails(
                    individualCredits: nil,
                    workspaceBalances: [],
                    subscriptionPlan: "Power"),
                updatedAt: now),
            suite: "SyncCoord-amp-dynamic-window-labels")

        #expect(provider.rateWindows.map(\.label) == ["Other usage", "Orb usage", "Amp Free"])
    }

    @Test
    func `antigravity sync hides an untouched family when another family is active`() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = try await self.syncedProvider(
            .antigravity,
            snapshot: UsageSnapshot(
                primary: nil,
                secondary: nil,
                extraRateWindows: [
                    NamedRateWindow(
                        id: "antigravity-quota-summary-gemini-5h",
                        title: "Gemini 5-hour",
                        window: RateWindow(
                            usedPercent: 25,
                            windowMinutes: 5 * 60,
                            resetsAt: now,
                            resetDescription: nil)),
                    NamedRateWindow(
                        id: "antigravity-quota-summary-3p-5h",
                        title: "Claude/GPT 5-hour",
                        window: RateWindow(
                            usedPercent: 0,
                            windowMinutes: 5 * 60,
                            resetsAt: now,
                            resetDescription: nil)),
                ],
                updatedAt: now),
            suite: "SyncCoord-antigravity-idle-family")

        #expect(provider.rateWindows.map(\.label) == ["Gemini 5-hour"])
    }

    @Test
    func `opencode pay as you go sync labels its limit as monthly`() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = OpenCodeUsageSnapshot.payAsYouGo(
            .init(monthlyUsageUSD: 15, monthlyLimitUSD: 20, balanceUSD: 12.5),
            updatedAt: now).toUsageSnapshot()
        let provider = try await self.syncedProvider(
            .opencode,
            snapshot: snapshot,
            suite: "SyncCoord-opencode-payg-monthly")

        #expect(provider.rateWindows.map(\.label) == ["Monthly"])
    }

    @Test
    func `alibaba token plan sync uses duration based lane labels`() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = try await self.syncedProvider(
            .alibabatokenplan,
            snapshot: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 20,
                    windowMinutes: 5 * 60,
                    resetsAt: now,
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 30,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: now,
                    resetDescription: nil),
                updatedAt: now),
            suite: "SyncCoord-alibaba-dynamic-window-labels")

        #expect(provider.rateWindows.map(\.label) == ["5-hour", "7-day"])
    }

    @Test
    func `qwen cloud legacy monthly window syncs as 30 day`() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = try await self.syncedProvider(
            .qwencloud,
            snapshot: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 20,
                    windowMinutes: 30 * 24 * 60,
                    resetsAt: now,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: now),
            suite: "SyncCoord-qwen-legacy-window-label")

        #expect(provider.rateWindows.map(\.label) == ["30-day"])
    }

    @Test
    func `kimi per provider rate windows use semantic identities`() async throws {
        let settings = self.makeRateWindowIdentitySettingsStore(suite: "SyncCoord-kimi-rate-window-identities")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .kimi,
            metadata: #require(ProviderDefaults.metadata[.kimi]),
            enabled: true)

        let now = Date()
        let store = self.makeRateWindowIdentityUsageStore(settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 24,
                    windowMinutes: 10080,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    resetDescription: "24/100 requests"),
                secondary: RateWindow(
                    usedPercent: 75,
                    windowMinutes: 300,
                    resetsAt: now.addingTimeInterval(5 * 60 * 60),
                    resetDescription: "Rate: 15/20 per 5 hours"),
                updatedAt: now),
            provider: .kimi)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastPerProviderEnvelopes
            .first { $0.provider.providerID == UsageProvider.kimi.rawValue }?
            .provider)
        let weekly = try #require(provider.rateWindows.first { $0.label == "7-day usage" })
        let rateLimit = try #require(provider.rateWindows.first { $0.label == "5-hour usage" })

        #expect(weekly.identity == .weekly)
        #expect(weekly.windowMinutes == 10080)
        #expect(weekly.pace != nil)
        #expect(rateLimit.identity == .session)
    }

    @Test
    func `codex per provider sync caps session while weekly quota is exhausted`() async throws {
        let settings = self.makeRateWindowIdentitySettingsStore(suite: "SyncCoord-codex-weekly-cap-sync")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let weeklyReset = Date(timeIntervalSince1970: 4_102_444_800)
        let store = self.makeRateWindowIdentityUsageStore(settings: settings)
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
