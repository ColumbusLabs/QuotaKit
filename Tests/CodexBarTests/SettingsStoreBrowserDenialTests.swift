import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
@MainActor
struct SettingsStoreBrowserDenialTests {
    @Test(arguments: ["openAIWebAccess", "openAIWebAccessEnabled"])
    func `explicit browser denial remains off in CLI config after relaunch`(key: String) throws {
        let suite = "SettingsStoreBrowserDenialTests-\(UUID().uuidString)"
        let defaults = InMemoryUserDefaults(values: [key: false])

        let first = testSettingsStore(suiteName: suite, userDefaults: defaults)
        #expect(!first.openAIWebAccessEnabled)
        #expect(first.codexCookieSource == .off)
        let saved = try #require(try first.configStore.load())
        #expect(saved.providerConfig(for: .codex)?.cookieSource == .off)

        let second = testSettingsStore(suiteName: suite, config: saved, userDefaults: defaults)
        #expect(!second.openAIWebAccessEnabled)
        #expect(second.codexCookieSource == .off)
    }

    @Test
    func `initial inferred denial is frozen before generic config is created`() {
        let defaults = InMemoryUserDefaults()

        #expect(!SettingsStore.initializeOpenAIWebAccessPreference(
            userDefaults: defaults, config: CodexBarConfig(providers: []), hadExistingConfig: false))
        #expect(defaults.object(forKey: "openAIWebAccessEnabled") as? Bool == false)
        #expect(!SettingsStore.initializeOpenAIWebAccessPreference(
            userDefaults: defaults,
            config: CodexBarConfig(providers: [ProviderConfig(id: .codex)]),
            hadExistingConfig: true))
    }
}
