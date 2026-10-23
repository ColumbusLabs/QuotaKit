import Foundation
import Testing
@testable import CodexBarCore

/// Mythos is available to verified organizations and its rates are published by Anthropic.
struct CostUsagePricingClaudeMythosTests {
    @Test
    func `claude cost supports mythos 5 point 1 bundled fallback`() throws {
        let emptyCacheRoot = try Self.cacheRoot()
        defer { try? FileManager.default.removeItem(at: emptyCacheRoot) }
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-mythos-5-1",
            inputTokens: 100,
            cacheReadInputTokens: 20,
            cacheCreationInputTokens: 30,
            cacheCreationInputTokens1h: 20,
            outputTokens: 5,
            modelsDevCacheRoot: emptyCacheRoot)
        let expected = (100.0 * 1e-5)
            + (20.0 * 2.5e-7)
            + (10.0 * 1.25e-5)
            + (20.0 * 2e-5)
            + (5.0 * 5e-5)
        #expect(cost == expected)
    }

    @Test
    func `claude cost supports mythos 5 bundled fallback`() throws {
        let emptyCacheRoot = try Self.cacheRoot()
        defer { try? FileManager.default.removeItem(at: emptyCacheRoot) }
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-mythos-5",
            inputTokens: 100,
            cacheReadInputTokens: 20,
            cacheCreationInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: emptyCacheRoot)
        let expected = (100.0 * 1e-5) + (20.0 * 1e-6) + (10.0 * 1.25e-5) + (5.0 * 5e-5)
        #expect(cost == expected)
    }

    private static func cacheRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-mythos-pricing-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
