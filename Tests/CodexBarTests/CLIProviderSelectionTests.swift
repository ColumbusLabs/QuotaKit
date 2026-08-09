import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIProviderSelectionTests {
    @Test
    func `help exposes only the four provider product`() {
        let usage = CodexBarCLI.usageHelp(version: "0.0.0")
        let root = CodexBarCLI.rootHelp(version: "0.0.0")
        let providerList = "codex|claude|cursor|grok|both|all"

        #expect(usage.contains(providerList))
        #expect(root.contains(providerList))
        #expect(usage.contains("quotakit usage --provider grok"))
        #expect(usage.contains("--json-only"))
        #expect(root.contains("--json-output"))
        #expect(root.contains("--log-level"))
    }

    @Test
    func `help documents source selection without legacy source flags`() {
        let usage = CodexBarCLI.usageHelp(version: "0.0.0")
        let root = CodexBarCLI.rootHelp(version: "0.0.0")

        func tokens(_ text: String) -> [String] {
            let split = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "[]|,"))
            return text.components(separatedBy: split).filter { !$0.isEmpty }
        }

        #expect(usage.contains("--source"))
        #expect(root.contains("--source"))
        #expect(usage.contains("--web-timeout"))
        #expect(!tokens(usage).contains("--web"))
        #expect(!tokens(root).contains("--claude-source"))
    }

    @Test
    func `provider selection accepts every retained provider override`() {
        for provider in UsageProvider.allCases {
            let selection = CodexBarCLI.providerSelection(
                rawOverride: provider.rawValue,
                enabled: [.codex, .claude])
            #expect(selection.asList == [provider])
        }
    }

    @Test
    func `provider selection preserves enabled four provider order`() {
        let enabled: [UsageProvider] = [.grok, .codex, .cursor, .claude]
        let selection = CodexBarCLI.providerSelection(rawOverride: nil, enabled: enabled)
        #expect(selection.asList == enabled)
    }

    @Test
    func `provider selection keeps both as codex and claude`() {
        let selection = CodexBarCLI.providerSelection(rawOverride: "both", enabled: [])
        #expect(selection.asList == [.codex, .claude])
    }

    @Test
    func `provider selection all is exactly four providers`() {
        let selection = CodexBarCLI.providerSelection(rawOverride: "all", enabled: [])
        #expect(selection.asList == UsageProvider.allCases)
    }

    @Test
    func `provider selection honors empty enabled set`() {
        #expect(CodexBarCLI.providerSelection(rawOverride: nil, enabled: []).asList == [])
    }
}
