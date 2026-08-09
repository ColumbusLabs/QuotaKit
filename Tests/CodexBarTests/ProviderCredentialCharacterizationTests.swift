import CodexBarCore
import Foundation
import Testing

struct ProviderCredentialCharacterizationTests {
    @Test
    func `credential adapters exist only for Claude and Cursor`() {
        #expect(ProviderDescriptorRegistry.descriptor(for: .codex).credentials == nil)
        #expect(ProviderDescriptorRegistry.descriptor(for: .claude).credentials != nil)
        #expect(ProviderDescriptorRegistry.descriptor(for: .cursor).credentials != nil)
        #expect(ProviderDescriptorRegistry.descriptor(for: .grok).credentials == nil)
    }

    @Test
    func `Claude admin API key resolves from environment`() {
        let environment = [ClaudeAdminAPISettingsReader.adminAPIKeyEnvironmentKey: "  sk-ant-admin-test  "]
        let resolution = ProviderTokenResolver.resolution(for: .claude, environment: environment)

        #expect(resolution?.token == "sk-ant-admin-test")
        #expect(resolution?.source == .environment)
    }

    @Test
    func `Claude and Cursor retain token account support`() {
        let claude = TokenAccountSupportCatalog.support(for: .claude)
        let cursor = TokenAccountSupportCatalog.support(for: .cursor)

        if case .cookieHeader = claude?.injection {} else {
            Issue.record("Claude must inject cookies")
        }
        #expect(claude?.requiresManualCookieSource == true)
        #expect(claude?.showsOrganizationField == true)
        if case .cookieHeader = cursor?.injection {} else {
            Issue.record("Cursor must inject cookies")
        }
        #expect(cursor?.requiresManualCookieSource == true)
        #expect(TokenAccountSupportCatalog.support(for: .codex) == nil)
        #expect(TokenAccountSupportCatalog.support(for: .grok) == nil)
    }

    @Test
    func `Claude token account routing projects only API and OAuth credentials`() throws {
        let support = try #require(TokenAccountSupportCatalog.support(for: .claude))
        #expect(support.envOverride(token: "sk-ant-admin-test") == [
            ClaudeAdminAPISettingsReader.adminAPIKeyEnvironmentKey: "sk-ant-admin-test",
        ])
        #expect(support.envOverride(token: "Bearer sk-ant-oat-test") == [
            ClaudeOAuthCredentialsStore.environmentTokenKey: "sk-ant-oat-test",
        ])
        #expect(support.envOverride(token: "sk-ant-session-test") == nil)
    }

    @Test
    func `Cursor token accounts normalize cookie values without environment projection`() throws {
        let support = try #require(TokenAccountSupportCatalog.support(for: .cursor))

        #expect(support.normalizedCookieHeader(token: "session=config") == "session=config")
        #expect(support.envOverride(token: "session=config") == nil)
    }
}
