import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct SyncCoordinatorVercelPersonalBudgetTests {
    @Test
    func `personal budget sync exports its primary and safe details without the access token`() async throws {
        let suite = "SyncCoordinatorVercelPersonalBudgetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        settings.accountWidgetsEnabled = false
        try settings.setProviderEnabled(
            provider: .vercel,
            metadata: #require(ProviderDefaults.metadata[.vercel]),
            enabled: true)
        let accessToken = "fixture-vercel-access-token"
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            environmentBase: [
                VercelProviderDescriptor.tokenKey: accessToken,
                VercelProviderDescriptor.teamKey: "team-fixture",
            ])
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 75,
                    windowMinutes: 30 * 24 * 60,
                    resetsAt: Date(timeIntervalSince1970: 1_800_000_000 + 30 * 24 * 60 * 60),
                    resetDescription: "$75.00 / $100.00"),
                secondary: nil,
                details: [.makeSection(title: "Personal budget", rows: [
                    .makeRow(label: "Spend", value: "$75.00"),
                    .makeRow(label: "Limit", value: "$100.00"),
                    .makeRow(label: "Remaining", value: "$25.00"),
                ])],
                updatedAt: updatedAt,
                identity: ProviderIdentitySnapshot(
                    providerID: UsageProvider.vercel.instanceID,
                    accountEmail: "user@example.com",
                    accountOrganization: "team-fixture",
                    loginMethod: "Access token",
                    accountID: "usr_fixture"),
                dataConfidence: .exact),
            provider: .vercel)

        let pusher = MockSyncPusher()
        await SyncCoordinator(store: store, settings: settings, syncManager: pusher).pushCurrentSnapshot()

        let provider = try #require(pusher.lastPerProviderEnvelopes.first {
            $0.provider.providerID == "vercel"
        }?.provider)
        #expect(provider.rateWindows.map(\.label) == ["Personal budget"])
        #expect(provider.primary?.usedPercent == 75)
        #expect(provider.primary?.windowMinutes == 30 * 24 * 60)
        #expect(provider.providerDetails == [SyncProviderDetailSection(title: "Personal budget", rows: [
            .init(label: "Spend", value: "$75.00"),
            .init(label: "Limit", value: "$100.00"),
            .init(label: "Remaining", value: "$25.00"),
        ])])
        let wire = try #require(String(bytes: JSONEncoder().encode(provider), encoding: .utf8))
        #expect(!wire.contains(accessToken))
    }
}
