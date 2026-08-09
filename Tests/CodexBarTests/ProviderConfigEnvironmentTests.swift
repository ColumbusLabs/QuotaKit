import CodexBarCore
import Testing

struct ProviderConfigEnvironmentTests {
    @Test
    func `Claude admin API key overrides the retained environment keys`() {
        let environment = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: [ClaudeAdminAPISettingsReader.adminAPIKeyEnvironmentKey: "old"],
            provider: .claude,
            config: ProviderConfig(id: .claude, apiKey: "  sk-ant-admin-test  "))

        #expect(environment[ClaudeAdminAPISettingsReader.adminAPIKeyEnvironmentKey] == "sk-ant-admin-test")
        #expect(ProviderTokenResolver.token(for: .claude, environment: environment) == "sk-ant-admin-test")
    }

    @Test
    func `empty Claude API key leaves the base environment unchanged`() {
        let base = [ClaudeAdminAPISettingsReader.adminAPIKeyEnvironmentKey: "existing"]
        let environment = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: base,
            provider: .claude,
            config: ProviderConfig(id: .claude, apiKey: "   "))

        #expect(environment == base)
    }

    @Test
    func `only Claude supports direct API key projection`() {
        #expect(ProviderConfigEnvironment.supportsAPIKeyOverride(for: .claude))
        #expect(!ProviderConfigEnvironment.supportsAPIKeyOverride(for: .codex))
        #expect(!ProviderConfigEnvironment.supportsAPIKeyOverride(for: .cursor))
        #expect(!ProviderConfigEnvironment.supportsAPIKeyOverride(for: .grok))
    }

    @Test
    func `providers without environment projections preserve the base environment`() {
        let base = ["EXISTING": "value"]
        for provider in [UsageProvider.codex, .cursor, .grok] {
            let environment = ProviderConfigEnvironment.applyProviderConfigOverrides(
                base: base,
                provider: provider,
                config: ProviderConfig(id: provider.instanceID, apiKey: "ignored"))
            #expect(environment == base)
        }
    }
}
