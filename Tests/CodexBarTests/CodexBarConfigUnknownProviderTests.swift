import Foundation
import Testing
@testable import CodexBarCore

struct CodexBarConfigUnknownProviderTests {
    @Test
    func `well formed dynamic provider entries survive plugin availability changes`() throws {
        let data = Data(#"""
        {
          "version": 1,
          "providers": [
            {"id": "kimik2", "enabled": true},
            {"id": "crossmodel", "enabled": true},
            {"id": "Bad_ID", "enabled": true},
            {"id": "codex", "enabled": false, "source": "oauth"}
          ]
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(CodexBarConfig.self, from: data)
        let kimik2 = try #require(ProviderInstanceID(rawValue: "kimik2"))
        let crossmodel = try #require(ProviderInstanceID(rawValue: "crossmodel"))

        #expect(decoded.providers.map(\.id) == [kimik2, crossmodel, .codex])
        #expect(decoded.providerConfig(for: .codex)?.enabled == false)
        #expect(decoded.providerConfig(for: .codex)?.source == .oauth)
    }
}
