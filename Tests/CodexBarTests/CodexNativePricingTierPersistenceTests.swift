import Foundation
import Testing
@testable import CodexBarCore

struct CodexNativePricingTierPersistenceTests {
    @Test(arguments: [
        CostUsageScanner.CodexNativePricingTier.standard,
        .priority,
        .unknown,
    ])
    func `buffered tier survives storage roundtrip`(_ tier: CostUsageScanner.CodexNativePricingTier) throws {
        let line = CostUsageScanner.CodexBufferedFastLine(
            lineIndex: 1,
            ordinal: nil,
            line: .threadSettingsApplied(priority: tier))
        let decoded = try JSONDecoder().decode(
            CostUsageScanner.CodexBufferedFastLine.self,
            from: JSONEncoder().encode(line))
        #expect(decoded == line)
    }

    @Test
    func `legacy booleans still decode to established tiers`() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(CostUsageScanner.CodexNativePricingTier.self, from: Data("true".utf8)) == .priority)
        #expect(try decoder.decode(CostUsageScanner.CodexNativePricingTier.self, from: Data("false".utf8)) == .standard)
    }
}
