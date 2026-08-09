import CodexBarCore
import Foundation
import Testing

struct ProviderEnvironmentResolverTests {
    @Test
    func `Claude session account removes API and OAuth credentials`() {
        let environment = ProviderEnvironmentResolver.resolve(
            base: [
                ClaudeAdminAPISettingsReader.alternateAdminAPIKeyEnvironmentKey: "ambient-admin",
                ClaudeOAuthCredentialsStore.environmentTokenKey: "ambient-oauth",
            ],
            provider: .claude,
            config: ProviderConfig(id: .claude, apiKey: "saved-admin"),
            selectedAccount: Self.account(token: "sk-ant-session-account"))

        for key in ClaudeAdminAPISettingsReader.apiKeyEnvironmentKeys {
            #expect(environment[key] == nil)
        }
        #expect(environment[ClaudeOAuthCredentialsStore.environmentTokenKey] == nil)
    }

    @Test
    func `Claude OAuth account replaces incompatible credentials`() {
        let environment = ProviderEnvironmentResolver.resolve(
            base: [
                ClaudeAdminAPISettingsReader.alternateAdminAPIKeyEnvironmentKey: "ambient-admin",
                ClaudeOAuthCredentialsStore.environmentTokenKey: "ambient-oauth",
            ],
            provider: .claude,
            config: ProviderConfig(id: .claude, apiKey: "saved-admin"),
            selectedAccount: Self.account(token: "Bearer sk-ant-oat-account"))

        for key in ClaudeAdminAPISettingsReader.apiKeyEnvironmentKeys {
            #expect(environment[key] == nil)
        }
        #expect(environment[ClaudeOAuthCredentialsStore.environmentTokenKey] == "sk-ant-oat-account")
    }

    @Test
    func `cookie account leaves unrelated provider environment intact`() {
        let base = ["FOO": "bar"]
        let environment = ProviderEnvironmentResolver.resolve(
            base: base,
            provider: .cursor,
            config: ProviderConfig(id: .cursor),
            selectedAccount: Self.account(token: "session=account"))

        #expect(environment == base)
    }

    private static func account(token: String) -> ProviderTokenAccount {
        ProviderTokenAccount(
            id: UUID(),
            label: "Test",
            token: token,
            addedAt: 0,
            lastUsed: nil)
    }
}
