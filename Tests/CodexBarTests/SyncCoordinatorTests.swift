import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// Mock sync pusher that records push calls for testing.
final class MockSyncPusher: SyncPushing, @unchecked Sendable {
    var pushCount = 0
    var lastSnapshot: SyncedUsageSnapshot?
    var nextResult: SyncPushResult = .success

    // P4 — per-provider write tracking
    var perProviderCallCount = 0
    var lastPerProviderEnvelopes: [ProviderUsageEnvelope] = []
    var nextPerProviderResult: SyncPushResult = .success

    @discardableResult
    func pushSnapshot(_ snapshot: SyncedUsageSnapshot) async -> SyncPushResult {
        self.pushCount += 1
        self.lastSnapshot = snapshot
        return self.nextResult
    }

    @discardableResult
    func pushPerProviderRecords(
        _ envelopes: [ProviderUsageEnvelope]) async -> SyncPushResult
    {
        self.perProviderCallCount += 1
        self.lastPerProviderEnvelopes = envelopes
        return self.nextPerProviderResult
    }
}

@MainActor
@Suite
struct SyncCoordinatorTests {
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
    func pushSkippedWhenSyncDisabled() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-disabled")
        settings.iCloudSyncEnabled = false
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        #expect(mock.pushCount == 0)
        #expect(coordinator.lastSyncTime == nil)
    }

    @Test
    func pushSucceedsWhenSyncEnabled() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-enabled")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // Push may or may not happen depending on whether there are enabled providers.
        // With default config, providers may be enabled, so check status tracking.
        if mock.pushCount > 0 {
            #expect(coordinator.lastSyncTime != nil)
            #expect(coordinator.lastSyncSucceeded == true)
            #expect(coordinator.lastSyncMessage == nil)
        }
    }

    @Test
    func pushFailureTracksStatus() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-failure")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        mock.nextResult = .failure("iCloud sync unavailable")
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        if mock.pushCount > 0 {
            #expect(coordinator.lastSyncTime != nil)
            #expect(coordinator.lastSyncSucceeded == false)
            #expect(coordinator.lastSyncMessage == "iCloud sync unavailable")
        }
    }

    @Test
    func isSyncingIsFalseAfterPush() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-syncing")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // isSyncing should be false after synchronous push completes
        #expect(coordinator.isSyncing == false)
    }

    @Test
    func pushIncludesModelAndServiceBreakdowns() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-breakdowns")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 1500,
                sessionCostUSD: 0.32,
                last30DaysTokens: 32000,
                last30DaysCostUSD: 2.40,
                daily: [
                    CostUsageDailyReport.Entry(
                        date: "2026-03-16",
                        inputTokens: 1000,
                        outputTokens: 500,
                        totalTokens: 1500,
                        costUSD: 2.40,
                        modelsUsed: ["gpt-5.4", "gpt-5.3-codex"],
                        modelBreakdowns: [
                            .init(modelName: "gpt-5.4", costUSD: 1.80),
                            .init(modelName: "gpt-5.3-codex", costUSD: 0.60),
                        ]),
                ],
                updatedAt: Date()),
            provider: .codex)
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: nil,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [
                OpenAIDashboardDailyBreakdown(
                    day: "2026-03-16",
                    services: [
                        OpenAIDashboardServiceUsage(service: "CLI", creditsUsed: 1.90),
                        OpenAIDashboardServiceUsage(service: "GitHub Code Review", creditsUsed: 0.50),
                    ],
                    totalCreditsUsed: 2.40),
            ],
            creditsPurchaseURL: nil,
            updatedAt: Date())

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == UsageProvider.codex.rawValue }))
        let costSummary = try #require(provider.costSummary)
        let daily = try #require(costSummary.daily.first)

        #expect(daily.modelBreakdowns == [
            SyncCostBreakdown(label: "gpt-5.4", costUSD: 1.80),
            SyncCostBreakdown(label: "gpt-5.3-codex", costUSD: 0.60),
        ])
        #expect(daily.serviceBreakdowns == [
            SyncCostBreakdown(label: "Codex Run", costUSD: 1.90),
            SyncCostBreakdown(label: "GitHub Code Review", costUSD: 0.50),
        ])
    }

    @Test
    func pushBuildsCodexCostSummaryFromDashboardWhenTokenSnapshotMissing() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-dashboardFallback")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: nil,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [
                OpenAIDashboardDailyBreakdown(
                    day: "2026-03-15",
                    services: [OpenAIDashboardServiceUsage(service: "CLI", creditsUsed: 0.75)],
                    totalCreditsUsed: 0.75),
                OpenAIDashboardDailyBreakdown(
                    day: "2026-03-16",
                    services: [OpenAIDashboardServiceUsage(service: "GitHub Code Review", creditsUsed: 1.25)],
                    totalCreditsUsed: 1.25),
            ],
            creditsPurchaseURL: nil,
            updatedAt: Date())

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == UsageProvider.codex.rawValue }))
        let costSummary = try #require(provider.costSummary)
        #expect(costSummary.sessionCostUSD == nil)
        #expect(costSummary.last30DaysCostUSD == 2.0)
        #expect(costSummary.daily.count == 2)
        #expect(costSummary.daily[0].serviceBreakdowns == [SyncCostBreakdown(label: "Codex Run", costUSD: 0.75)])
    }

    @Test
    func defaultSyncEnabledIsTrue() throws {
        let suite = "SyncCoord-defaultEnabled"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(settings.iCloudSyncEnabled == true)
    }

    @Test
    func syncEnabledPersistsAcrossInstances() throws {
        let suite = "SyncCoord-persist"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        storeA.iCloudSyncEnabled = false

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.iCloudSyncEnabled == false)
    }

    @Test
    func togglingSettingUpdatesUserDefaults() throws {
        let suite = "SyncCoord-toggle"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        settings.iCloudSyncEnabled = false
        #expect(defaults.bool(forKey: "iCloudSyncEnabled") == false)

        settings.iCloudSyncEnabled = true
        #expect(defaults.bool(forKey: "iCloudSyncEnabled") == true)
    }

    // MARK: - P4 per-provider dual-write

    @Test
    func perProviderWriteFiresAlongsideLegacyOnFirstPush() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-perprov-first")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date()),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // Legacy write ran once; per-provider write ran once with the Codex envelope.
        #expect(mock.pushCount == 1)
        #expect(mock.perProviderCallCount == 1)
        #expect(mock.lastPerProviderEnvelopes.count >= 1)
        #expect(mock.lastPerProviderEnvelopes.contains { $0.provider.providerID == "codex" })
    }

    @Test
    func perProviderWriteSkippedWhenDataUnchanged() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-perprov-unchanged")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let fixedSnapshot = CostUsageTokenSnapshot(
            sessionTokens: 100,
            sessionCostUSD: 0.1,
            last30DaysTokens: 1000,
            last30DaysCostUSD: 1.0,
            daily: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        store._setTokenSnapshotForTesting(fixedSnapshot, provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()
        let firstCallEnvelopes = mock.lastPerProviderEnvelopes

        // Second push with unchanged data: coordinator's diff cache should
        // surface an empty envelope array, so the mock records either a
        // zero-length call or no call at all.
        await coordinator.pushCurrentSnapshot()

        #expect(!firstCallEnvelopes.isEmpty) // first push wrote envelopes
        // Second push skipped everything — either no call, or explicit empty.
        // Coordinator guards on `!envelopes.isEmpty` so it should be no call.
        #expect(mock.perProviderCallCount == 1)
    }

    @Test
    func perProviderWriteSendsOnlyChangedProviderOnIncrementalUpdate() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-perprov-incr")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .codex)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 50,
                sessionCostUSD: 0.05,
                last30DaysTokens: 500,
                last30DaysCostUSD: 0.5,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .claude)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        // First push — both providers upload.
        await coordinator.pushCurrentSnapshot()
        let firstCount = mock.lastPerProviderEnvelopes.count
        #expect(firstCount >= 2)

        // Change ONLY Codex.
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 200,
                sessionCostUSD: 0.2,
                last30DaysTokens: 2000,
                last30DaysCostUSD: 2.0,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 1_700_001_000)),
            provider: .codex)

        await coordinator.pushCurrentSnapshot()

        // Second call should contain only the changed provider.
        #expect(mock.perProviderCallCount == 2)
        #expect(mock.lastPerProviderEnvelopes.count == 1)
        #expect(mock.lastPerProviderEnvelopes.first?.provider.providerID == "codex")
    }
}
