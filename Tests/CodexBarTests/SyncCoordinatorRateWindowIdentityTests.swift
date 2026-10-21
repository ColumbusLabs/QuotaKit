import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

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
    func `antigravity sync projects ordinary Gemini representative and keeps model quota rows`() async throws {
        let quota: [String: Any] = ["groups": [
            ["name": "General models", "buckets": [
                [
                    "id": "gemini-weekly",
                    "name": "Weekly",
                    "window": "weekly",
                    "disabled": false,
                    "remaining_fraction": 0.9996,
                    "reset_time": "2030-03-17T17:46:40Z",
                ],
                [
                    "id": "gemini-synthetic-limited-weekly",
                    "name": "Weekly",
                    "window": "weekly",
                    "disabled": false,
                    "remaining_fraction": 0,
                    "reset_time": "2030-03-17T17:46:40Z",
                ],
            ]],
            ["name": "Third party models", "buckets": [
                [
                    "id": "3p-weekly",
                    "name": "Weekly",
                    "window": "weekly",
                    "disabled": false,
                    "remaining_fraction": 0.7,
                    "reset_time": "2030-03-17T17:46:40Z",
                ],
            ]],
        ]]
        let report: [String: Any] = [
            "status": "SUCCESS",
            "command": ["name": "usage", "data": quota],
        ]
        let snapshot = try AntigravityStatusProbe.parseCLIUsageReport(
            JSONSerialization.data(withJSONObject: report)).toUsageSnapshot()
        let provider = try await self.syncedProvider(
            .antigravity,
            snapshot: snapshot,
            suite: "SyncCoord-antigravity-ordinary-gemini-projection")

        let primary = try #require(provider.rateWindows.first)
        #expect(primary.label == "Gemini Models")
        #expect(abs(primary.usedPercent - 0.04) < 0.000001)
        let secondary = try #require(provider.rateWindows.dropFirst().first)
        #expect(secondary.label == "Claude and GPT")
        #expect(abs(secondary.usedPercent - 30) < 0.000001)
        let geminiDetails = provider.rateWindows.filter { $0.label == "General models weekly" }
        #expect(geminiDetails.map(\.usedPercent) == [primary.usedPercent, 100])
        let thirdPartyDetails = try #require(
            provider.rateWindows.first { $0.label == "Third party models weekly" })
        #expect(abs(thirdPartyDetails.usedPercent - 30) < 0.000001)
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
    func `alibaba monthly-only Personal usage syncs as Monthly`() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try AlibabaTokenPlanPersonalUsageParser.parse(
            from: Data(#"{"per1MonthPercentage":0.25}"#.utf8),
            subscriptionData: nil,
            quotaConfigData: nil,
            now: now).toUsageSnapshot()
        let provider = try await self.syncedProvider(
            .alibabatokenplan,
            snapshot: snapshot,
            suite: "SyncCoord-alibaba-personal-monthly")

        #expect(provider.rateWindows.map(\.label) == ["Monthly"])
    }

    @Test
    func `gemini sync uses source specific labels and rate window identities`() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let webProvider = try await self.syncedProvider(
            .gemini,
            snapshot: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 71,
                    windowMinutes: 5 * 60,
                    resetsAt: now.addingTimeInterval(3600),
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 4,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: now.addingTimeInterval(86400),
                    resetDescription: nil),
                updatedAt: now),
            suite: "SyncCoord-gemini-web-rate-window-labels")

        #expect(webProvider.rateWindows.map(\.label) == ["5-hour", "Weekly"])
        #expect(webProvider.rateWindows[0].identity == .session)
        #expect(webProvider.rateWindows[1].identity == .weekly)

        let cliProvider = try await self.syncedProvider(
            .gemini,
            snapshot: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12,
                    windowMinutes: 24 * 60,
                    resetsAt: now.addingTimeInterval(3600),
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 3,
                    windowMinutes: 24 * 60,
                    resetsAt: now.addingTimeInterval(86400),
                    resetDescription: nil),
                updatedAt: now),
            suite: "SyncCoord-gemini-cli-rate-window-labels")

        #expect(cliProvider.rateWindows.map(\.label) == ["Pro", "Flash"])
    }

    @Test
    func `qwen cloud monthly window syncs as Monthly`() async throws {
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

        #expect(provider.rateWindows.map(\.label) == ["Monthly"])
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
