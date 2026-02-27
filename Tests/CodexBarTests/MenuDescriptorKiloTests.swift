import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite
struct MenuDescriptorKiloTests {
    @Test
    func kiloCreditsDetailDoesNotRenderAsResetLine() throws {
        let suite = "MenuDescriptorKiloTests-kilo-detail"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        settings.usageBarsShowUsed = false

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 10,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "10/100 credits"),
            secondary: nil,
            tertiary: nil,
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .kilo,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: "Kilo Pass Pro"))
        store._setSnapshotForTesting(snapshot, provider: .kilo)

        let descriptor = MenuDescriptor.build(
            provider: .kilo,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: false)

        let usageEntries = try #require(descriptor.sections.first?.entries)
        let textLines = usageEntries.compactMap { entry -> String? in
            guard case let .text(text, _) = entry else { return nil }
            return text
        }

        #expect(textLines.contains("10/100 credits"))
        #expect(!textLines.contains(where: { $0.contains("Resets 10/100 credits") }))
    }
}
