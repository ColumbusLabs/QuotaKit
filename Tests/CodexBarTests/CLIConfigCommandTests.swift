import CodexBarCore
import Commander
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIConfigCommandTests {
    @Test
    func `config provider toggle parses retained provider and JSON flags`() throws {
        let parser = CommandParser(signature: CodexBarCLI._configProviderToggleSignatureForTesting())
        let parsed = try parser.parse(arguments: ["--provider", "grok", "--json", "--pretty"])

        #expect(parsed.options["provider"] == ["grok"])
        #expect(CodexBarCLI._decodeFormatForTesting(from: parsed) == .json)
        #expect(parsed.flags.contains("pretty"))
    }

    @Test
    func `config provider toggle enables and disables each retained provider`() {
        for provider in UsageProvider.allCases {
            let config = CodexBarConfig.makeDefault()
            let enabled = CodexBarCLI.configSettingProviderEnabled(config, provider: provider, enabled: true)
            let disabled = CodexBarCLI.configSettingProviderEnabled(enabled, provider: provider, enabled: false)

            #expect(enabled.providerConfig(for: provider.instanceID)?.enabled == true)
            #expect(disabled.providerConfig(for: provider.instanceID)?.enabled == false)
        }
    }

    @Test
    func `config provider status inventory is exactly four providers`() throws {
        let config = CodexBarConfig(providers: [
            ProviderConfig(id: .grok, enabled: true),
            ProviderConfig(id: .cursor, enabled: false),
        ])
        let statuses = CodexBarCLI.configProviderStatuses(config)

        #expect(statuses.count == UsageProvider.allCases.count)
        #expect(Set(statuses.map(\.provider)) == Set(UsageProvider.allCases.map(\.rawValue)))
        #expect(try #require(statuses.first { $0.provider == "grok" }).enabled)
        #expect(try !(#require(statuses.first { $0.provider == "cursor" }).enabled))
    }

    @Test
    func `config API key support is limited to Claude`() {
        #expect(!ProviderConfigEnvironment.supportsAPIKeyOverride(for: .codex))
        #expect(ProviderConfigEnvironment.supportsAPIKeyOverride(for: .claude))
        #expect(!ProviderConfigEnvironment.supportsAPIKeyOverride(for: .cursor))
        #expect(!ProviderConfigEnvironment.supportsAPIKeyOverride(for: .grok))
    }

    @Test
    func `config set API key stores Claude key and preserves requested enablement`() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .claude, enabled: false))

        let updated = CodexBarCLI.configSettingAPIKey(
            config,
            provider: .claude,
            apiKey: "sk-ant-admin-test",
            enableProvider: false)

        #expect(updated.providerConfig(for: .claude)?.apiKey == "sk-ant-admin-test")
        #expect(updated.providerConfig(for: .claude)?.enabled == false)
    }

    @Test
    func `config set API key rejects ambiguous input`() {
        #expect(throws: CLIArgumentError.self) {
            try CodexBarCLI.resolveConfigAPIKeyInput(apiKey: "sk-ant-admin-test", readFromStdin: true)
        }
    }

    @Test
    func `config help documents supported config operations`() {
        let help = CodexBarCLI.configHelp(version: "0.0.0")

        #expect(help.contains("config set-api-key --provider <name>"))
        #expect(help.contains("config providers"))
        #expect(help.contains("config enable --provider <name>"))
        #expect(help.contains("config disable --provider <name>"))
        #expect(help.contains("--stdin"))
        #expect(help.contains("--show-secrets"))
        #expect(!help.contains("--label"))
    }

    @Test
    func `config dump redacts Claude credentials by default`() {
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "Team",
            token: "fixture-token",
            addedAt: 1000,
            lastUsed: nil)
        let config = CodexBarConfig(providers: [ProviderConfig(
            id: .claude,
            apiKey: "fixture-api-key",
            cookieHeader: "fixture-cookie",
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0))])

        let redacted = config.sanitizedForDump(showSecrets: false).providerConfig(for: .claude)
        #expect(redacted?.apiKey == "[REDACTED]")
        #expect(redacted?.cookieHeader == "[REDACTED]")
        #expect(redacted?.tokenAccounts?.accounts.first?.token == "[REDACTED]")

        let raw = config.sanitizedForDump(showSecrets: true).providerConfig(for: .claude)
        #expect(raw?.apiKey == "fixture-api-key")
        #expect(raw?.cookieHeader == "fixture-cookie")
        #expect(raw?.tokenAccounts?.accounts.first?.token == "fixture-token")
    }
}
