import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SettingsStoreAdditionalTests {
    @Test
    func `typed provider config bindings normalize standard fields`() {
        let settings = Self.makeSettingsStore(suite: "SettingsStoreAdditionalTests-provider-config-bindings")
        let fields: [(ProviderConfigStringField, String)] = [
            (.apiKey, "api"),
            (.secretKey, "secret"),
            (.region, "region"),
            (.endpoint, "https://example.test"),
            (.workspace, "workspace"),
            (.cookieHeader, "session=fixture"),
        ]
        for (field, value) in fields {
            settings[providerConfig: .grok, field: field] = "  \(value)  "
            #expect(settings[providerConfig: .grok, field: field] == value)
        }

        let binding = settings.providerConfigBinding(provider: .codex, field: .secretWorkspace(logField: "projectID"))
        binding.wrappedValue = "  project  "
        #expect(binding.wrappedValue == "project")

        let cookieSource = settings.providerCookieSourceBinding(provider: .grok, fallback: .auto)
        #expect(cookieSource.wrappedValue == .auto)
        cookieSource.wrappedValue = .manual
        #expect(cookieSource.wrappedValue == .manual)

        settings[providerConfig: .grok, field: .apiKey] = "   "
        #expect(settings.providerConfig(for: .grok)?.apiKey == nil)
    }

    @Test
    func `cursor metric migration preserves released metric meaning`() throws {
        let primaryDefaults = try self.cursorMetricDefaults(suffix: "primary", preference: .primary)
        #expect(SettingsStore(userDefaults: primaryDefaults).menuBarMetricPreference(for: .cursor) == .automatic)
        #expect(primaryDefaults.bool(forKey: "cursorAutoAPIMetricPreferenceMigrated"))

        let secondaryDefaults = try self.cursorMetricDefaults(suffix: "secondary", preference: .secondary)
        #expect(SettingsStore(userDefaults: secondaryDefaults).menuBarMetricPreference(for: .cursor) == .primary)

        let tertiaryDefaults = try self.cursorMetricDefaults(suffix: "tertiary", preference: .tertiary)
        #expect(SettingsStore(userDefaults: tertiaryDefaults).menuBarMetricPreference(for: .cursor) == .secondary)
    }

    @Test
    func `menu bar metric capability membership covers supported providers`() {
        let settings = Self.makeSettingsStore(suite: "SettingsStoreAdditionalTests-menu-metric-capabilities")
        let standard: Set<MenuBarMetricPreference> = [.automatic, .primary, .secondary]
        let overrides: [UsageProvider: Set<MenuBarMetricPreference>] = [
            .codex: standard.union([.primaryAndSecondary]),
            .claude: standard.union([.primaryAndSecondary, .extraUsage]),
            .cursor: standard.union([.tertiary, .extraUsage]),
        ]

        for provider in UsageProvider.allCases {
            let supported = overrides[provider] ?? standard
            for preference in MenuBarMetricPreference.allCases {
                settings.setMenuBarMetricPreference(preference, for: provider)
                let expected = supported.contains(preference) ? preference : .automatic
                #expect(settings.menuBarMetricPreference(for: provider) == expected)
            }
        }
    }

    @Test
    func `claude token accounts select manual cookie source`() {
        let settings = Self.makeSettingsStore(suite: "SettingsStoreAdditionalTests-token-accounts")

        settings.addTokenAccount(provider: .claude, label: "Primary", token: "token-1")

        #expect(settings.tokenAccounts(for: .claude).count == 1)
        #expect(settings.claudeCookieSource == .manual)
    }

    @Test
    func `detects codex token cost usage sources from filesystem`() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: sessions.appendingPathComponent("usage.jsonl"))
        defer { try? fileManager.removeItem(at: root) }

        #expect(SettingsStore.hasAnyTokenCostUsageSources(env: ["CODEX_HOME": root.path], fileManager: fileManager))
    }

    private static func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(userDefaults: defaults, configStore: testConfigStore(suiteName: suite))
    }

    private func cursorMetricDefaults(
        suffix: String,
        preference: MenuBarMetricPreference) throws -> UserDefaults
    {
        let suite = "SettingsStoreAdditionalTests-cursor-metric-\(suffix)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(
            [UsageProvider.cursor.rawValue: preference.rawValue],
            forKey: "menuBarMetricPreferences")
        return defaults
    }
}
