import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct SettingsStoreCoverageTests {
    @Test
    func `token account mutations preserve identity and active selection`() throws {
        let settings = try Self.makeSettingsStore("token-mutations")
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "sk-ant-session-one")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "sk-ant-session-two")
        settings.setActiveTokenAccountIndex(0, for: .claude)
        let original = try #require(settings.selectedTokenAccount(for: .claude))

        settings.updateTokenAccount(
            provider: .claude,
            accountID: original.id,
            label: "Primary Updated",
            token: "sk-ant-session-updated")

        let updated = try #require(settings.selectedTokenAccount(for: .claude))
        #expect(updated.id == original.id)
        #expect(updated.label == "Primary Updated")
        #expect(updated.token == "sk-ant-session-updated")
        #expect(settings.claudeCookieSource == .manual)
    }

    @Test
    func `removing another account preserves the active Claude selection`() throws {
        let settings = try Self.makeSettingsStore("token-removal")
        settings.addTokenAccount(provider: .claude, label: "A", token: "sk-ant-session-a")
        settings.addTokenAccount(provider: .claude, label: "B", token: "sk-ant-session-b")
        settings.addTokenAccount(provider: .claude, label: "C", token: "sk-ant-session-c")
        settings.setActiveTokenAccountIndex(1, for: .claude)
        let active = try #require(settings.selectedTokenAccount(for: .claude))
        let first = try #require(settings.tokenAccounts(for: .claude).first)

        settings.removeTokenAccount(provider: .claude, accountID: first.id)

        #expect(settings.selectedTokenAccount(for: .claude)?.id == active.id)
        #expect(settings.tokenAccounts(for: .claude).map(\.label) == ["B", "C"])
    }

    @Test
    func `Claude snapshot routes OAuth token accounts`() throws {
        let settings = try Self.makeSettingsStore("claude-oauth")
        settings.addTokenAccount(provider: .claude, label: "OAuth", token: "Bearer sk-ant-oat-account-token")

        let snapshot = settings.claudeSettingsSnapshot(tokenOverride: nil)

        #expect(snapshot.usageDataSource == .oauth)
        #expect(snapshot.cookieSource == .off)
        #expect(snapshot.manualCookieHeader?.isEmpty == true)
    }

    @Test
    func `Claude snapshot routes session key accounts as manual web cookies`() throws {
        let settings = try Self.makeSettingsStore("claude-cookie")
        settings.addTokenAccount(provider: .claude, label: "Cookie", token: "sk-ant-session-token")

        let snapshot = settings.claudeSettingsSnapshot(tokenOverride: nil)

        #expect(snapshot.usageDataSource == .web)
        #expect(snapshot.cookieSource == .manual)
        #expect(snapshot.manualCookieHeader == "sessionKey=sk-ant-session-token")
    }

    @Test
    func `Claude manual config cookie uses shared normalization`() throws {
        let settings = try Self.makeSettingsStore("claude-config-cookie")
        settings.claudeCookieSource = .manual
        settings.claudeCookieHeader = "Cookie: sessionKey=sk-ant-session-token; foo=bar"

        let snapshot = settings.claudeSettingsSnapshot(tokenOverride: nil)

        #expect(snapshot.cookieSource == .manual)
        #expect(snapshot.manualCookieHeader == "sessionKey=sk-ant-session-token; foo=bar")
    }

    @Test
    func `Claude swap settings persist in provider config`() throws {
        let settings = try Self.makeSettingsStore("claude-swap")

        settings.claudeSwapEnabled = true
        settings.claudeSwapShowSingleAccount = true
        settings.claudeSwapExecutablePath = "  /opt/homebrew/bin/ccs  "

        let config = try #require(settings.providerConfig(for: .claude))
        #expect(config.claudeSwapEnabled == true)
        #expect(config.claudeSwapShowSingleAccount == true)
        #expect(config.sanitizedClaudeSwapExecutablePath == "/opt/homebrew/bin/ccs")
    }

    @Test
    func `keychain disable forces retained auto cookie sources to manual`() throws {
        let settings = try Self.makeSettingsStore("keychain-disabled")
        settings.codexCookieSource = .auto
        settings.claudeCookieSource = .auto

        settings.debugDisableKeychainAccess = true

        #expect(settings.codexCookieSource == .manual)
        #expect(settings.claudeCookieSource == .manual)
    }

    @Test
    func `Claude keychain policy defaults and persists without reading Keychain`() throws {
        let suite = "SettingsStoreCoverageTests-claude-keychain-policy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let first = SettingsStore(userDefaults: defaults, configStore: configStore)
        #expect(first.claudeOAuthKeychainPromptMode == .onlyOnUserAction)

        first.claudeOAuthKeychainPromptMode = .never
        let second = SettingsStore(userDefaults: defaults, configStore: configStore)

        #expect(second.claudeOAuthKeychainPromptMode == .never)
        #expect(second.claudeOAuthPromptFreeCredentialsEnabled)
    }

    @Test
    func `weekly work days and preferred currency persist`() throws {
        let suite = "SettingsStoreCoverageTests-generic-persistence-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let first = SettingsStore(userDefaults: defaults, configStore: configStore)
        first.weeklyProgressWorkDays = 5
        first.preferredCurrencyCode = "GBP"

        let second = SettingsStore(userDefaults: defaults, configStore: configStore)

        #expect(second.weeklyProgressWorkDays == 5)
        #expect(second.preferredCurrencyCode == "GBP")
    }

    private static func makeSettingsStore(_ suffix: String) throws -> SettingsStore {
        let suite = "SettingsStoreCoverageTests-\(suffix)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(userDefaults: defaults, configStore: testConfigStore(suiteName: suite))
    }
}
