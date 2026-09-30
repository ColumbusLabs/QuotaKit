import Foundation
import Testing
@testable import CodexBarCore

struct CrofRetirementCompatibilityPortableTests {
    @Test
    func `retired provider identifiers still decode historical snapshots`() throws {
        let id = try JSONDecoder().decode(ProviderInstanceID.self, from: Data(#""crof""#.utf8))
        #expect(id.rawValue == "crof")
        #expect(id.firstPartyProvider == nil)
        #expect(UsageProvider(rawValue: "crof") == nil)

        let entry = WidgetSnapshot.ProviderEntry(
            instanceID: id,
            updatedAt: Date(timeIntervalSince1970: 1000),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let decoded = try JSONDecoder().decode(
            WidgetSnapshot.ProviderEntry.self,
            from: JSONEncoder().encode(entry))

        #expect(decoded.provider == id)
        #expect(decoded.updatedAt == entry.updatedAt)
    }

    @Test
    func `retired config remains opaque and byte preserved after normalization`() throws {
        let record = #"{ "id":"crof", "enabled":true, "future":[1e400,-0], "apiKey":"synthetic" }"#
        let input = Data((#"{"version":1,"providers":["# + record + "]}").utf8)
        let config = try CodexBarConfig.decode(from: input).normalized()

        #expect(config.providers.allSatisfy { $0.id.rawValue != "crof" })
        #expect(config.unavailableProviders.map(\.id) == ["crof"])
        #expect(config.unavailableProviders.first?.enabled == true)
        let output = try config.encodedData()
        #expect(try #require(String(bytes: output, encoding: .utf8)).contains(record))
    }
}
