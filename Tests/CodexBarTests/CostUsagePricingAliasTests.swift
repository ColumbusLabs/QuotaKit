import Foundation
import Testing
@testable import CodexBarCore

struct CostUsagePricingAliasTests {
    @Test
    func `reserve normalizes to Luna and invalidates the built in pricing fingerprint`() throws {
        #expect(CostUsagePricing.normalizeCodexModel("gpt-reserve") == "gpt-5.6-luna")
        #expect(CostUsagePricing.normalizeCodexModel("openai/gpt-reserve") == "gpt-5.6-luna")
        #expect(CostUsagePricing.codexBuiltInPricingFingerprint()
            .contains("modelAlias=gpt-reserve->gpt-5.6-luna"))

        let root = try Self.cacheRoot()
        let luna = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-luna",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)
        let reserve = CostUsagePricing.codexCostUSD(
            model: "gpt-reserve",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)

        #expect(reserve == luna)
    }

    @Test
    func `reserve tries the exact OpenAI model before Luna without crossing providers`() throws {
        let targets = CostUsagePricing.codexModelsDevPricingTargets(for: "openai/gpt-reserve")
        #expect(targets.map { "\($0.providerID)/\($0.modelID)" } == [
            "openai/gpt-reserve",
            "openai/gpt-5.6-luna",
        ])

        let exactRoot = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-reserve": {"id": "gpt-reserve", "cost": {"input": 9, "output": 90}},
              "gpt-5.6-luna": {"id": "gpt-5.6-luna", "cost": {"input": 0.2, "output": 1.2}}
            }
          }
        }
        """)
        let canonicalOnlyRoot = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.6-luna": {"id": "gpt-5.6-luna", "cost": {"input": 0.2, "output": 1.2}}
            }
          }
        }
        """)

        let exact = CostUsagePricing.codexCostUSD(
            model: "openai/gpt-reserve",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 0,
            modelsDevCacheRoot: exactRoot)
        let fallback = CostUsagePricing.codexCostUSD(
            model: "openai/gpt-reserve",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 0,
            modelsDevCacheRoot: canonicalOnlyRoot)
        let wrongProvider = CostUsagePricing.codexCostUSD(
            model: "deepseek/gpt-reserve",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 0,
            modelsDevCacheRoot: exactRoot)

        #expect(exact == 100 * 9e-6)
        #expect(abs((fallback ?? 0) - (100 * 0.2e-6)) < 1e-12)
        #expect(wrongProvider == nil)
    }

    @Test
    func `reserve uses Luna historical rates across the July cutoff`() throws {
        let root = try Self.cacheRoot()
        let beforeCutoff = Date(timeIntervalSince1970: 1_785_369_599)
        let afterCutoff = Date(timeIntervalSince1970: 1_785_369_601)

        func cost(model: String, date: Date) -> Double? {
            CostUsagePricing.codexCostUSD(
                model: model,
                inputTokens: 100,
                cachedInputTokens: 10,
                outputTokens: 5,
                pricingDate: date,
                modelsDevCacheRoot: root)
        }

        #expect(cost(model: "gpt-reserve", date: beforeCutoff)
            == cost(model: "gpt-5.6-luna", date: beforeCutoff))
        #expect(cost(model: "gpt-reserve", date: afterCutoff)
            == cost(model: "gpt-5.6-luna", date: afterCutoff))
    }

    @Test(arguments: ["gpt-5.6-sol", "gpt-5.6"], [100, 272_001])
    func `Sol keeps historical rates before its August repricing`(model: String, input: Int) throws {
        let root = try Self.cacheRoot()
        let beforeCutoff = Date(timeIntervalSince1970: 1_787_270_399) // 2026-08-20T23:59:59Z
        let cutoff = Date(timeIntervalSince1970: 1_787_270_400) // 2026-08-21T00:00:00Z
        let isLongContext = input > 272_000

        func cost(on date: Date) -> Double? {
            CostUsagePricing.codexCostUSD(
                model: model,
                inputTokens: input,
                cachedInputTokens: 10,
                outputTokens: 5,
                pricingDate: date,
                modelsDevCacheRoot: root)
        }

        let oldInputRate = isLongContext ? 1e-5 : 5e-6
        let oldCachedRate = isLongContext ? 1e-6 : 5e-7
        let oldOutputRate = isLongContext ? 4.5e-5 : 3e-5
        let newInputRate = isLongContext ? 8e-6 : 4e-6
        let newCachedRate = isLongContext ? 8e-7 : 4e-7
        let newOutputRate = isLongContext ? 3e-5 : 2e-5
        let oldExpected = Double(input - 10) * oldInputRate + 10 * oldCachedRate + 5 * oldOutputRate
        let newExpected = Double(input - 10) * newInputRate + 10 * newCachedRate + 5 * newOutputRate

        #expect(abs((cost(on: beforeCutoff) ?? 0) - oldExpected) < 1e-12)
        #expect(abs((cost(on: cutoff) ?? 0) - newExpected) < 1e-12)
    }

    private static func seedModelsDevCache(_ json: String) throws -> URL {
        let root = try Self.cacheRoot()
        let catalog = try JSONDecoder().decode(ModelsDevCatalog.self, from: Data(json.utf8))
        ModelsDevCache.save(catalog: catalog, fetchedAt: Date(), cacheRoot: root)
        return root
    }

    private static func cacheRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-pricing-alias-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
