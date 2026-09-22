import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct SyncCoordinatorCodeRabbitSyncTests {
    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
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
    func `CodeRabbit detail-only snapshots stay out of both iPhone sync streams`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-coderabbit-mac-only")
        settings.iCloudSyncEnabled = true
        for provider in [UsageProvider.coderabbit, .codex] {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(ProviderDefaults.metadata[provider]),
                enabled: true)
        }

        let store = self.makeUsageStore(settings: settings)
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let codeRabbitUsage = try CodeRabbitUsageParser.parse(usageText: """
        Organization: Example Team
        User: reviewer
        Plan: Pro
        Your reviews: 10
        Usage billing: included
        """, now: updatedAt).toUsageSnapshot()
        store._setSnapshotForTesting(codeRabbitUsage, provider: .coderabbit)

        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, updatedAt: updatedAt),
            provider: .codex)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 30,
                sessionCostUSD: 3,
                last30DaysTokens: 300,
                last30DaysCostUSD: 9,
                historyCoverageIsEstablished: true,
                daily: [],
                updatedAt: updatedAt),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let localCodeRabbit = try #require(store.snapshots[UsageProvider.coderabbit.instanceID])
        #expect(localCodeRabbit.detailRow(label: "Reviews")?.value == "10")
        #expect(localCodeRabbit.identity?.loginMethod == "Pro")
        #expect(mock.lastSnapshot?.providers.contains {
            $0.providerID == UsageProvider.coderabbit.rawValue
        } == false)
        let legacyCodex = try #require(mock.lastSnapshot?.providers.first {
            $0.providerID == UsageProvider.codex.rawValue
        })
        #expect(legacyCodex.costSummary?.last30DaysCostUSD == 9)

        #expect(!mock.lastPerProviderEnvelopes.contains {
            $0.provider.providerID == UsageProvider.coderabbit.rawValue
        })
        let perProviderCodex = try #require(mock.lastPerProviderEnvelopes.first {
            $0.provider.providerID == UsageProvider.codex.rawValue
        })
        #expect(perProviderCodex.provider.costSummary?.last30DaysCostUSD == 9)
    }
}
