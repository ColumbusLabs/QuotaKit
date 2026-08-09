import CodexBarCore
import Testing
@testable import CodexBarCLI

struct CLIDiagnoseCommandTests {
    @Test
    func `diagnose help describes generic safe JSON export`() {
        let help = CodexBarCLI.diagnoseHelp(version: "0.0.0")

        #expect(help.contains("quotakit diagnose --provider <name|all> --format json"))
        #expect(help.contains("quotakit diagnose --provider all --format json"))
        #expect(help.contains("safe JSON export"))
        #expect(help.contains("raw API tokens"))
    }

    @Test
    func `diagnose recognizes configured Claude admin API credentials`() {
        let summary = CodexBarCLI._diagnosticAuthSummaryForTesting(
            provider: .claude,
            account: nil,
            config: ProviderConfig(id: .claude, apiKey: "sk-ant-admin-test"),
            environment: [:],
            settings: nil)

        #expect(summary.configured)
        #expect(summary.modes == ["api"])
    }

    @Test(arguments: [UsageProvider.codex, .cursor, .grok])
    func `diagnose does not assume ambient credentials`(provider: UsageProvider) {
        let summary = CodexBarCLI._diagnosticAuthSummaryForTesting(
            provider: provider,
            account: nil,
            config: nil,
            environment: [:],
            settings: nil)

        #expect(!summary.configured)
        #expect(summary.modes.isEmpty)
    }
}
