import Foundation
import Testing
@testable import CodexBarCore

struct CodexRPCSpendControlDecoderTests {
    @Test
    func `RPC reset timestamp truncates fractional values toward zero`() throws {
        let positive = try self.decodedLimit(#""resetsAt": 17.9"#)
        let negative = try self.decodedLimit(#""resetsAt": -17.9"#)

        #expect(positive["resetsAt"] as? Int == 17)
        #expect(negative["resetsAt"] as? Int == -17)
    }

    @Test
    func `RPC out of range reset timestamp falls back to alias or is omitted`() throws {
        let fallback = try self.decodedLimit(#""resetsAt": 1e100, "resets_at": 1782864000"#)
        let omitted = try self.decodedLimit(#""resetsAt": 1e100"#)

        #expect(fallback["resetsAt"] as? Int == 1_782_864_000)
        #expect(omitted["resetsAt"] == nil)
        #expect((omitted["limit"] as? NSNumber)?.doubleValue == 100_000)
        #expect((omitted["used"] as? NSNumber)?.doubleValue == 7761)
    }

    private func decodedLimit(_ resetFields: String) throws -> [String: Any] {
        let input = Data("""
        {
          "rateLimits": {
            "individualLimit": {
              "limit": 100000,
              "used": 7761,
              "remainingPercent": 92.239,
              \(resetFields)
            }
          }
        }
        """.utf8)
        let encoded = try UsageFetcher._redactCodexRPCRateLimitsForTesting(input)
        let root = try #require(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        let rateLimits = try #require(root["rateLimits"] as? [String: Any])
        return try #require(rateLimits["individualLimit"] as? [String: Any])
    }
}
