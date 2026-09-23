import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct SettingsStoreExternalConfigTests {
    @Test
    func `external visibility changes stay presentation-only while fetch changes refresh`() throws {
        let suite = "SettingsStoreExternalConfigTests-visibility-impact"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        let initialConfigRevision = store.configRevision
        let initialProviderRevision = store.providerConfigRevision(for: .codex)
        let initialBackgroundRevision = store.backgroundWorkSettingsRevision
        var visibilityChange = store.configSnapshot
        let codexIndex = try #require(visibilityChange.providers.firstIndex(where: { $0.id == .codex }))
        visibilityChange.providers[codexIndex].hiddenUsageItemIDs = ["metric:codex-spark"]
        store.applyExternalConfig(visibilityChange, reason: "usage-visibility")

        #expect(store.configRevision == initialConfigRevision + 1)
        #expect(store.providerConfigRevision(for: .codex) == initialProviderRevision)
        #expect(store.backgroundWorkSettingsRevision == initialBackgroundRevision)

        var fetchChange = store.configSnapshot
        let fetchCodexIndex = try #require(fetchChange.providers.firstIndex(where: { $0.id == .codex }))
        fetchChange.providers[fetchCodexIndex].source = .cli
        store.applyExternalConfig(fetchChange, reason: "provider-source")

        #expect(store.backgroundWorkSettingsRevision == initialBackgroundRevision + 1)
    }
}
