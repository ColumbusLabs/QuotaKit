import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageHistoricalPricingTests {
    @Test
    func `Claude Code uses bundled OpenAI long context boundary with catalog rates`() throws {
        let catalog = try JSONDecoder().decode(ModelsDevCatalog.self, from: Data("""
        {"openai":{"id":"openai","models":{"gpt-5.4":{"id":"gpt-5.4","cost":{
          "input":2,"output":4,"cache_read":0.25,"cache_write":3,
          "context_over_200k":{"input":7,"output":11,"cache_read":0.5,"cache_write":9}
        }}}}}
        """.utf8))
        for (tokens, rate) in [(250_000, 2e-6), (280_000, 7e-6)] {
            let cost = try #require(CostUsagePricing.claudeCostUSD(
                model: "gpt-5.4",
                inputTokens: tokens,
                cacheReadInputTokens: 0,
                cacheCreationInputTokens: 0,
                outputTokens: 0,
                modelsDevCatalog: catalog))
            #expect(cost == Double(tokens) * rate)
        }
    }

    @Test
    func `GPT-5_6 Terra and Luna use explicit July 2026 boundary dates`() throws {
        let root = try Self.cacheRoot()
        // Assert against absolute dates, not the shared cutoff constant.
        let beforeCutoff = Date(timeIntervalSince1970: 1_785_369_599) // 2026-07-29T23:59:59Z
        let afterCutoff = Date(timeIntervalSince1970: 1_785_369_601) // 2026-07-30T00:00:01Z

        let terraOld = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-terra",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            pricingDate: beforeCutoff,
            modelsDevCacheRoot: root)
        let terraNew = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-terra",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            pricingDate: afterCutoff,
            modelsDevCacheRoot: root)
        let lunaOld = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-luna",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            pricingDate: beforeCutoff,
            modelsDevCacheRoot: root)
        let lunaNew = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-luna",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            pricingDate: afterCutoff,
            modelsDevCacheRoot: root)

        let expectedTerraOld: Double = (90 * 2.5e-6) + (10 * 2.5e-7) + (5 * 1.5e-5)
        let expectedTerraNew: Double = (90 * 2e-6) + (10 * 2e-7) + (5 * 1.2e-5)
        #expect(abs((terraOld ?? 0) - expectedTerraOld) < 1e-12)
        #expect(abs((terraNew ?? 0) - expectedTerraNew) < 1e-12)
        #expect((terraOld ?? 0) > (terraNew ?? 0))
        let expectedLunaOld: Double = (90 * 1e-6) + (10 * 1e-7) + (5 * 6e-6)
        let expectedLunaNew: Double = (90 * 2e-7) + (10 * 2e-8) + (5 * 1.2e-6)
        #expect(abs((lunaOld ?? 0) - expectedLunaOld) < 1e-12)
        #expect(abs((lunaNew ?? 0) - expectedLunaNew) < 1e-12)
        #expect((lunaOld ?? 0) > (lunaNew ?? 0))
    }

    @Test
    func `historical pricing does not activate without a pricingDate`() throws {
        let root = try Self.cacheRoot()
        let terraNil = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-terra",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            pricingDate: nil,
            modelsDevCacheRoot: root)
        let terraCurrent = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-terra",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            pricingDate: Date(timeIntervalSince1970: 1_785_369_601),
            modelsDevCacheRoot: root)

        #expect(terraNil == terraCurrent)
    }

    private static func cacheRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-historical-pricing-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
