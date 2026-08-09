import CodexBarCore
import Testing

struct ProviderTokenResolverTests {
    @Test
    func `Claude resolution trims the admin API environment token`() {
        let environment = [ClaudeAdminAPISettingsReader.adminAPIKeyEnvironmentKey: "  sk-ant-admin-test  "]
        let resolution = ProviderTokenResolver.resolution(for: .claude, environment: environment)

        #expect(resolution?.token == "sk-ant-admin-test")
        #expect(resolution?.source == .environment)
    }

    @Test
    func `Claude resolution returns nil when admin API token is missing`() {
        #expect(ProviderTokenResolver.resolution(for: .claude, environment: [:]) == nil)
    }

    @Test
    func `providers without environment token resolvers return nil`() {
        for provider in [UsageProvider.codex, .cursor, .grok] {
            #expect(ProviderTokenResolver.resolution(for: provider, environment: ["TOKEN": "value"]) == nil)
        }
    }
}
