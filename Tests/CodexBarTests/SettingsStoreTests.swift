import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct SettingsStoreTests {
    @Test
    func `persists generic defaults across instances`() throws {
        let fixture = try Self.fixture("SettingsStoreTests-defaults")
        fixture.settings.refreshFrequency = .fifteenMinutes
        fixture.settings.refreshAllProvidersOnMenuOpen = true
        fixture.settings.hidePersonalInfo = true

        let reloaded = SettingsStore(userDefaults: fixture.defaults, configStore: fixture.configStore)

        #expect(reloaded.refreshFrequency == .fifteenMinutes)
        #expect(reloaded.refreshAllProvidersOnMenuOpen)
        #expect(reloaded.hidePersonalInfo)
    }

    @Test
    func `default provider order is exactly the supported providers`() throws {
        let fixture = try Self.fixture("SettingsStoreTests-default-order")

        #expect(fixture.settings.orderedProviders() == [.codex, .claude, .cursor, .grok])
    }

    @Test
    func `provider enablement updates config and revision`() throws {
        let fixture = try Self.fixture("SettingsStoreTests-enablement")
        let metadata = ProviderDescriptorRegistry.descriptor(for: .grok).metadata
        let revision = fixture.settings.configRevision

        fixture.settings.setProviderEnabled(provider: .grok, metadata: metadata, enabled: true)

        #expect(fixture.settings.isProviderEnabled(provider: .grok, metadata: metadata))
        #expect(fixture.settings.providerConfig(for: .grok)?.enabled == true)
        #expect(fixture.settings.configRevision == revision + 1)
    }

    @Test
    func `UI provider reordering keeps unknown persisted entries as an untouched tail`() throws {
        let suite = "SettingsStoreTests-order-unknown-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let custom = try #require(ProviderInstanceID(rawValue: "custom-provider"))
        let customConfig = try Self.providerConfig(from: """
        {
          "id": "custom-provider",
          "enabled": true,
          "apiKey": "  opaque-api-key  ",
          "secretKey": "opaque-secret-key",
          "cookieHeader": "session=opaque-cookie",
          "region": "retired-region",
          "workspaceID": "retired-workspace",
          "futureOptions": {
            "bytes": [0, 127, 255],
            "nested": {"enabled": true, "label": "opaque-value"}
          }
        }
        """)
        let originalCustomData = try Self.encoded(customConfig)
        try configStore.save(CodexBarConfig(providers: [
            customConfig,
            ProviderConfig(id: .codex),
            ProviderConfig(id: .claude),
            ProviderConfig(id: .cursor),
            ProviderConfig(id: .grok),
        ]))
        let settings = SettingsStore(userDefaults: defaults, configStore: configStore)

        #expect(settings.orderedProviders() == [.codex, .claude, .cursor, .grok])
        settings.moveProvider(fromOffsets: IndexSet(integer: 3), toOffset: 0)

        #expect(settings.orderedProviders() == [.grok, .codex, .claude, .cursor])
        #expect(settings.configSnapshot.providers.map(\.id) == [.grok, .codex, .claude, .cursor, custom])
        let preservedCustom = try #require(settings.configSnapshot.providerConfig(for: custom))
        #expect(try Self.encoded(preservedCustom) == originalCustomData)
        let loadedConfig = try configStore.load()
        let persistedConfig = try #require(loadedConfig)
        let persistedCustom = try #require(persistedConfig.providerConfig(for: custom))
        #expect(try Self.encoded(persistedCustom) == originalCustomData)
    }

    @Test
    func `token account reload updates live providers without touching unknown provider data`() throws {
        let suite = "SettingsStoreTests-token-reload-unknown-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let custom = try #require(ProviderInstanceID(rawValue: "retired-provider"))
        let originalCustom = try Self.providerConfig(from: """
        {
          "id": "retired-provider",
          "apiKey": "retired-api-key",
          "tokenAccounts": {
            "version": 7,
            "activeIndex": 0,
            "accounts": [{
              "id": "00000000-0000-0000-0000-000000000001",
              "label": "Retired account",
              "token": "retired-token",
              "addedAt": 123,
              "lastUsed": 456
            }]
          },
          "futureCredential": {"blob": "AAECAwQ="}
        }
        """)
        try configStore.save(CodexBarConfig(providers: [
            originalCustom,
            ProviderConfig(id: .claude),
        ]))
        let settings = SettingsStore(userDefaults: defaults, configStore: configStore)
        let originalCustomData = try Self.encoded(#require(settings.configSnapshot.providerConfig(for: custom)))
        let claudeAccounts = Self.tokenAccounts(provider: "Claude", token: "new-claude-token")

        try configStore.save(CodexBarConfig(providers: [
            ProviderConfig(id: custom, tokenAccounts: Self.tokenAccounts(provider: "Disk retired", token: "changed")),
            ProviderConfig(id: .claude, tokenAccounts: claudeAccounts),
        ]))
        settings.reloadTokenAccounts()

        let preservedCustom = try #require(settings.configSnapshot.providerConfig(for: custom))
        #expect(try Self.encoded(preservedCustom) == originalCustomData)
        #expect(settings.configSnapshot.providerConfig(for: .claude)?.tokenAccounts?.accounts.first?.token ==
            "new-claude-token")
        let loadedConfig = try configStore.load()
        let persistedConfig = try #require(loadedConfig)
        let persistedCustom = try #require(persistedConfig.providerConfig(for: custom))
        #expect(try Self.encoded(persistedCustom) == originalCustomData)
    }

    @Test
    func `quota warning overrides remain provider scoped`() throws {
        let fixture = try Self.fixture("SettingsStoreTests-quota-warnings")

        fixture.settings.setQuotaWarningThresholds(provider: .claude, window: .weekly, thresholds: [25, 75])
        fixture.settings.setQuotaWarningWindowEnabled(provider: .claude, window: .weekly, enabled: false)

        #expect(fixture.settings.explicitQuotaWarningThresholds(provider: .claude, window: .weekly) == [75, 25])
        #expect(fixture.settings.quotaWarningEnabled(provider: .claude, window: .weekly) == false)
        #expect(fixture.settings.explicitQuotaWarningThresholds(provider: .codex, window: .weekly) == nil)
    }

    private static func fixture(_ name: String) throws -> Fixture {
        let suite = "\(name)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        return Fixture(
            defaults: defaults,
            configStore: configStore,
            settings: SettingsStore(userDefaults: defaults, configStore: configStore))
    }

    private static func providerConfig(from json: String) throws -> ProviderConfig {
        try JSONDecoder().decode(ProviderConfig.self, from: Data(json.utf8))
    }

    private static func encoded(_ config: ProviderConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(config)
    }

    private static func tokenAccounts(provider: String, token: String) -> ProviderTokenAccountData {
        ProviderTokenAccountData(
            version: 1,
            accounts: [
                ProviderTokenAccount(
                    id: UUID(),
                    label: "\(provider) account",
                    token: token,
                    addedAt: 100,
                    lastUsed: nil),
            ],
            activeIndex: 0)
    }

    private struct Fixture {
        let defaults: UserDefaults
        let configStore: CodexBarConfigStore
        let settings: SettingsStore
    }
}
