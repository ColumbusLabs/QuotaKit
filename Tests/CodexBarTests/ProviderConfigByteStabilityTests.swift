import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ProviderConfigByteStabilityTests {
    @Test(arguments: [
        "provider-specific-full",
        "provider-specific-sparse",
    ])
    func `current provider config fixtures re-encode byte for byte`(fixtureName: String) throws {
        let fixtureURL = try #require(Bundle.module.url(
            forResource: fixtureName,
            withExtension: "json",
            subdirectory: "Fixtures/Config"))
        let fixtureData = try Data(contentsOf: fixtureURL)
        let config = try JSONDecoder().decode(CodexBarConfig.self, from: fixtureData)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(config)

        // Text fixtures keep the repository-standard final newline; JSONEncoder intentionally does not emit one.
        #expect(Data(fixtureData.dropLast()) == encoded)
    }

    @Test
    func `hidden usage item selections round trip and preserve explicit empty values`() throws {
        let config = CodexBarConfig(providers: [
            ProviderConfig(id: .codex, hiddenUsageItemIDs: ["metric:codex-spark"]),
            ProviderConfig(id: .claude, hiddenUsageItemIDs: []),
        ])

        let decoded = try JSONDecoder().decode(CodexBarConfig.self, from: JSONEncoder().encode(config))

        #expect(decoded.providerConfig(for: .codex)?.hiddenUsageItemIDs == ["metric:codex-spark"])
        #expect(decoded.providerConfig(for: .claude)?.hiddenUsageItemIDs == [])
    }

    @Test
    func `presentation preferences are excluded from fetch identity`() throws {
        let configured = ProviderConfig(
            id: .codex,
            apiKey: "fictitious-test-key",
            accentColor: "#123456",
            hiddenUsageItemIDs: ["metric:codex-spark"])
        let unconfigured = ProviderConfig(id: .codex, apiKey: "fictitious-test-key")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        #expect(try encoder.encode(configured.fetchIdentityConfig) == encoder.encode(unconfigured.fetchIdentityConfig))
    }
}
