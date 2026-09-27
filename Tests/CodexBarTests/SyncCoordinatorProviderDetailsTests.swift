import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct SyncCoordinatorProviderDetailsTests {
    @Test
    func `detail-only balance is published without inventing quota windows`() async throws {
        let suite = "SyncCoordinatorProviderDetailsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .atlascloud,
            metadata: #require(ProviderDefaults.metadata[.atlascloud]),
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let details = [ProviderDetailSection.makeSection(
            title: "Account balance",
            rows: [.makeRow(label: "Available balance", value: "$95.50")])]
        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, details: details, updatedAt: Date()),
            provider: .atlascloud)
        let pusher = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: pusher)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(pusher.lastSnapshot?.providers.first { $0.providerID == "atlascloud" })
        #expect(provider.rateWindows.isEmpty)
        #expect(provider.providerDetails?.first?.rows.first?.value == "$95.50")
        let record = try #require(pusher.lastPerProviderEnvelopes.first {
            $0.provider.providerID == "atlascloud"
        })
        #expect(record.provider.providerDetails?.first?.rows.first?.value == "$95.50")
    }

    @Test
    func `plugin detail rows survive Mac mapping into per-provider iPhone records`() async throws {
        let suite = "SyncCoordinatorPluginDetailsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        let providers: [UsageProvider] = [.devpass, .raycast, .typesafe, .xkiro, .poe, .sakana]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            environmentBase: [
                PoeSettingsReader.apiKeyEnvironmentKey: "fixture-key",
                SakanaSettingsReader.cookieHeaderKey: "session=fixture",
            ])
        for provider in providers {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(ProviderDefaults.metadata[provider]),
                enabled: true)
            store._setSnapshotForTesting(
                UsageSnapshot(
                    primary: nil,
                    secondary: nil,
                    details: [.makeSection(
                        title: "Account details",
                        rows: [.makeRow(label: "Value", value: provider.rawValue)])],
                    updatedAt: Date()),
                provider: provider)
        }
        let pusher = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: pusher)
        await coordinator.pushCurrentSnapshot()

        for provider in providers {
            let envelope = try #require(pusher.lastPerProviderEnvelopes.first {
                $0.provider.providerID == provider.rawValue
            })
            #expect(envelope.provider.rateWindows.isEmpty)
            #expect(envelope.provider.providerDetails?.first?.rows.first?.value == provider.rawValue)
        }
    }
}
