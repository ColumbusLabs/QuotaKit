import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct SyncCoordinatorProviderDetailsTests {
    @Test
    func `Muse browser team source reaches iPhone without the team list or credential rows`() async throws {
        let suite = "SyncCoordinatorMuseDetailsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .muse,
            metadata: #require(ProviderDefaults.metadata[.muse]),
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let details = try [
            ProviderDetailSection(title: "Muse Code subscription", rows: [
                .init(label: "Plan", value: "Muse Code Power Usage"),
            ]),
            ProviderDetailSection(title: "Browser teams", rows: [
                .init(label: "Other", value: "11"),
                .init(label: "Selected", value: "22"),
            ]),
            ProviderDetailSection(title: "Browser team quota (dev.meta.ai)", rows: [
                .init(label: "Team", value: "Selected"),
                .init(label: "Weekly", value: "15%"),
                .init(label: "Cookie", value: "llama_dev_sess=fixture-secret"),
            ]),
        ]
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 15, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                details: details,
                updatedAt: Date(),
                dataConfidence: .estimated),
            provider: .muse)
        let pusher = MockSyncPusher()
        await SyncCoordinator(store: store, settings: settings, syncManager: pusher).pushCurrentSnapshot()

        let provider = try #require(pusher.lastPerProviderEnvelopes.first {
            $0.provider.providerID == "muse"
        }?.provider)
        #expect(provider.rateWindows.count == 2)
        #expect(provider.providerDetails == [SyncProviderDetailSection(
            title: "Browser team quota (dev.meta.ai)",
            rows: [.init(label: "Team", value: "Selected")])])
        let legacy = try #require(pusher.lastSnapshot?.providers.first { $0.providerID == "muse" })
        #expect(legacy.providerDetails == provider.providerDetails)
    }

    @Test
    func `Copilot seat credits are published as provider details`() async throws {
        let suite = "SyncCoordinatorCopilotDetailsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .copilot,
            metadata: #require(ProviderDefaults.metadata[.copilot]),
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                details: [.makeSection(title: "Credits", rows: [
                    .makeRow(label: "Credits used", value: "12 / 50", secondaryValue: "Resets next month"),
                ])],
                updatedAt: Date()),
            provider: .copilot)
        let pusher = MockSyncPusher()
        await SyncCoordinator(store: store, settings: settings, syncManager: pusher).pushCurrentSnapshot()

        let provider = try #require(pusher.lastPerProviderEnvelopes.first {
            $0.provider.providerID == "copilot"
        }?.provider)
        #expect(provider.providerDetails?.first?.rows.first?.value == "12 / 50")
        #expect(provider.providerDetails?.first?.rows.first?.secondaryValue == "Resets next month")
    }

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
