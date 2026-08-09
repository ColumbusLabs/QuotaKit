import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
struct CodexBarConfigMigratorTests {
    @Test
    func `missing config loads the supported provider defaults`() {
        let store = testConfigStore(suiteName: "CodexBarConfigMigratorTests-default-\(UUID().uuidString)")

        let config = CodexBarConfigMigrator.load(configStore: store)

        #expect(config.providers.compactMap(\.id.firstPartyProvider) == UsageProvider.allCases)
    }

    @Test
    func `stored unknown providers survive normalization`() throws {
        let store = testConfigStore(suiteName: "CodexBarConfigMigratorTests-unknown-\(UUID().uuidString)")
        let customID = try #require(ProviderInstanceID(rawValue: "custom-provider"))
        try store.save(CodexBarConfig(providers: [
            ProviderConfig(id: customID, enabled: true, apiKey: "custom-token"),
            ProviderConfig(id: .claude, enabled: false),
        ]))

        let config = CodexBarConfigMigrator.load(configStore: store)

        #expect(config.providers.map(\.id) == [customID, .claude, .codex, .cursor, .grok])
        #expect(config.providerConfig(for: customID)?.apiKey == "custom-token")
        #expect(config.providerConfig(for: .claude)?.enabled == false)
    }

    @Test
    func `duplicate stored providers are collapsed without reordering`() throws {
        let store = testConfigStore(suiteName: "CodexBarConfigMigratorTests-duplicates-\(UUID().uuidString)")
        try store.save(CodexBarConfig(providers: [
            ProviderConfig(id: .cursor, enabled: false),
            ProviderConfig(id: .cursor, enabled: true),
            ProviderConfig(id: .codex, enabled: true),
        ]))

        let config = CodexBarConfigMigrator.load(configStore: store)

        #expect(config.providers.map(\.id) == [.cursor, .codex, .claude, .grok])
        #expect(config.providerConfig(for: .cursor)?.enabled == false)
    }
}
