import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite
struct ProviderRegistryTests {
    @Test
    func defaultsEnableCodexAndDisableClaude() {
        let defaults = UserDefaults(suiteName: "ProviderRegistryTests-defaults")!
        defaults.removePersistentDomain(forName: "ProviderRegistryTests-defaults")
        let settings = SettingsStore(userDefaults: defaults)
        let registry = ProviderRegistry.shared

        let codexEnabled = settings.isProviderEnabled(provider: .codex, metadata: registry.metadata[.codex]!)
        let claudeEnabled = settings.isProviderEnabled(provider: .claude, metadata: registry.metadata[.claude]!)

        #expect(codexEnabled)
        #expect(!claudeEnabled)
    }

    @Test
    func togglesPersistAcrossStoreInstances() {
        let suite = "ProviderRegistryTests-persist"
        let defaultsA = UserDefaults(suiteName: suite)!
        defaultsA.removePersistentDomain(forName: suite)

        let settingsA = SettingsStore(userDefaults: defaultsA)
        let registry = ProviderRegistry.shared
        let claudeMeta = registry.metadata[.claude]!

        settingsA.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: true)

        let defaultsB = UserDefaults(suiteName: suite)!
        let settingsB = SettingsStore(userDefaults: defaultsB)
        let enabledAfterReload = settingsB.isProviderEnabled(provider: .claude, metadata: claudeMeta)

        #expect(enabledAfterReload)
    }

    @Test
    func registryBuildsSpecsForAllProviders() {
        let registry = ProviderRegistry.shared
        let defaults = UserDefaults(suiteName: "ProviderRegistryTests-specs")!
        defaults.removePersistentDomain(forName: "ProviderRegistryTests-specs")
        let settings = SettingsStore(userDefaults: defaults)
        let specs = registry.specs(
            settings: settings,
            metadata: registry.metadata,
            codexFetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher())
        #expect(specs.keys.count == UsageProvider.allCases.count)
    }
}
