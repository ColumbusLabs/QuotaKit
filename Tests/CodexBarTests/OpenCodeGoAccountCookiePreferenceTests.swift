import CodexBarCore
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI

@Suite(.serialized)
struct OpenCodeGoAccountCookiePreferenceTests {
    private func account(_ token: String, label: String = "Fixture") -> ProviderTokenAccount {
        ProviderTokenAccount(id: UUID(), label: label, token: token, addedAt: 0, lastUsed: nil)
    }

    @Test
    func `CLI isolates selected API keys from ambient credentials`() throws {
        let accounts = [self.account("go_first", label: "First"), self.account("go_second", label: "Second")]
        let config = CodexBarConfig(providers: [ProviderConfig(
            id: .opencodego,
            apiKey: "go_config",
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: accounts, activeIndex: 1))])
        let context = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: true),
            config: config,
            verbose: false,
            baseEnvironment: [:])

        #expect(try context.resolvedAccounts(for: .opencodego).map(\.id) == accounts.map(\.id))
        for account in accounts {
            let environment = context.environment(
                base: ["OPENCODE_API_KEY": "go_ambient", "UNRELATED": "kept"],
                provider: .opencodego,
                account: account)
            #expect(environment["OPENCODE_API_KEY"] == account.token)
            #expect(environment["UNRELATED"] == "kept")
            #expect(context.effectiveSourceMode(base: .auto, provider: .opencodego, account: account) == .api)
        }
    }

    @Test @MainActor
    func `app selected API account uses the isolated API route`() throws {
        let settings = try self.makeSettings()
        settings[providerConfig: .opencodego, field: .apiKey] = "go_config"
        settings.addTokenAccount(provider: .opencodego, label: "First", token: "go_first")
        let overrideAccount = self.account("go_second")
        let override = TokenAccountOverride(provider: .opencodego, account: overrideAccount)
        let environment = ProviderRegistry.makeEnvironment(
            base: ["OPENCODE_API_KEY": "go_ambient"],
            provider: .opencodego,
            settings: settings,
            tokenOverride: override)

        #expect(environment["OPENCODE_API_KEY"] == "go_second")
        #expect(ProviderRegistry.resolvedSourceMode(
            provider: .opencodego, settings: settings, account: overrideAccount) == .api)
        #expect(settings.tokenAccounts(for: .opencodego).first?.token == "go_first")
    }

    @Test(arguments: ["auth=fixture", "Cookie: __Host-console_session=fixture"])
    func `Cookie accounts clear ambient API keys and keep web routing`(token: String) throws {
        let account = self.account(token)
        let context = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: CodexBarConfig(providers: [ProviderConfig(id: .opencodego, apiKey: "go_config")]),
            verbose: false,
            baseEnvironment: [:])
        let environment = context.environment(
            base: ["OPENCODE_API_KEY": "go_ambient"], provider: .opencodego, account: account)
        let settings = try #require(context.settingsSnapshot(for: .opencodego, account: account)?.opencodego)

        #expect(environment["OPENCODE_API_KEY"] == nil)
        #expect(context.effectiveSourceMode(base: .auto, provider: .opencodego, account: account) == .auto)
        #expect(settings.cookieSource == .manual)
        #expect(settings.manualCookieHeader == token)
    }

    @Test(arguments: ["", "   ", "Cookie: broken", "auth=fixture", "two words"])
    func `invalid or Cookie shaped account credentials never become API keys`(token: String) {
        #expect(TokenAccountSupportCatalog.envOverride(for: .opencodego, token: token) == nil)
    }

    @Test(arguments: [" go_key ", "'go_key'", "\"go_key\""])
    func `account API keys use the same normalization as provider keys`(token: String) {
        #expect(TokenAccountSupportCatalog
            .envOverride(for: .opencodego, token: token) == ["OPENCODE_API_KEY": "go_key"])
    }

    @Test(arguments: [ProviderCookieSource.auto, .manual]) @MainActor
    func `API account lifecycle preserves the saved cookie preference`(source: ProviderCookieSource) throws {
        let settings = try self.makeSettings()
        settings.opencodegoCookieSource = source

        settings.addTokenAccount(provider: .opencodego, label: "First", token: "go_first")
        let first = try #require(settings.selectedTokenAccount(for: .opencodego))
        try self.expectSavedCookieSource(source, settings: settings)

        settings.addTokenAccount(provider: .opencodego, label: "Second", token: "go_second")
        let second = try #require(settings.selectedTokenAccount(for: .opencodego))
        try self.expectSavedCookieSource(source, settings: settings)

        settings.setActiveTokenAccountIndex(0, for: .opencodego)
        try self.expectSavedCookieSource(source, settings: settings)

        settings.updateTokenAccount(provider: .opencodego, accountID: first.id, token: "go_updated")
        try self.expectSavedCookieSource(source, settings: settings)

        settings.removeTokenAccount(provider: .opencodego, accountID: first.id)
        #expect(settings.selectedTokenAccount(for: .opencodego)?.id == second.id)
        try self.expectSavedCookieSource(source, settings: settings)

        settings.removeTokenAccount(provider: .opencodego, accountID: second.id)
        try self.expectSavedCookieSource(source, settings: settings)
    }

    @Test(arguments: ["auth=fixture", "Cookie: __Host-console_session=fixture"]) @MainActor
    func `Cookie accounts still select manual cookies`(token: String) throws {
        let settings = try self.makeSettings()
        settings.opencodegoCookieSource = .auto
        settings.addTokenAccount(provider: .opencodego, label: "Cookie", token: token)
        try self.expectSavedCookieSource(.manual, settings: settings)
    }

    @Test @MainActor
    func `changing an API account to a Cookie account selects manual cookies`() throws {
        let settings = try self.makeSettings()
        settings.opencodegoCookieSource = .auto
        settings.addTokenAccount(provider: .opencodego, label: "API", token: "go_key")
        let account = try #require(settings.selectedTokenAccount(for: .opencodego))
        try self.expectSavedCookieSource(.auto, settings: settings)

        settings.updateTokenAccount(provider: .opencodego, accountID: account.id, token: "auth=fixture")
        try self.expectSavedCookieSource(.manual, settings: settings)
    }

    @Test
    func `single configured API key still works without token accounts`() throws {
        let context = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: CodexBarConfig(providers: [ProviderConfig(id: .opencodego, source: .api, apiKey: "go_config")]),
            verbose: false,
            baseEnvironment: [:])
        #expect(try context.resolvedAccounts(for: .opencodego).isEmpty)
        #expect(context.environment(base: [:], provider: .opencodego, account: nil)["OPENCODE_API_KEY"] == "go_config")
        #expect(context.preferredSourceMode(for: .opencodego) == .api)
    }

    @Test(arguments: [ProviderSourceMode.api, .web])
    func `explicit CLI sources remain authoritative`(source: ProviderSourceMode) throws {
        let context = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: CodexBarConfig(providers: []),
            verbose: false,
            baseEnvironment: [:])
        #expect(context.effectiveSourceMode(
            base: source, provider: .opencodego, account: self.account("go_key")) == source)
    }

    @Test
    func `API source validation accepts an account key without a provider key`() {
        let config = CodexBarConfig(providers: [ProviderConfig(
            id: .opencodego,
            source: .api,
            tokenAccounts: ProviderTokenAccountData(
                version: 1, accounts: [self.account("go_key")], activeIndex: 0))])
        #expect(!CodexBarConfigValidator.validate(config).contains { $0.code == "api_key_missing" })
    }

    @MainActor
    private func makeSettings() throws -> SettingsStore {
        try #require(SettingsStore.isRunningTests)
        let settings = testSettingsStore(suiteName: "OpenCodeGoAccountCookiePreferenceTests")
        settings.configFileWatcher?.stop()
        return settings
    }

    @MainActor
    private func expectSavedCookieSource(_ source: ProviderCookieSource, settings: SettingsStore) throws {
        #expect(settings.opencodegoCookieSource == source)
        let savedConfig = try #require(try settings.configStore.load())
        #expect(savedConfig.providerConfig(for: .opencodego)?.cookieSource == source)
    }
}
