import Testing

@testable import CodexBarCore

@Suite
struct CostUsagePricingTests {
    @Test
    func normalizesCodexModelVariants() {
        #expect(CostUsagePricing.normalizeCodexModel("openai/gpt-5-codex") == "gpt-5")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.2-codex") == "gpt-5.2")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.1-codex-max") == "gpt-5.1")
    }

    @Test
    func codexCostSupportsGpt51CodexMax() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.1-codex-max",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func normalizesClaudeOpus41DatedVariants() {
        #expect(CostUsagePricing.normalizeClaudeModel("claude-opus-4-1-20250805") == "claude-opus-4-1")
    }

    @Test
    func claudeCostSupportsOpus41DatedVariant() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-1-20250805",
            inputTokens: 10,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func claudeCostSupportsGlmVariants() {
        let glm46Cost = CostUsagePricing.claudeCostUSD(
            model: "glm-4.6",
            inputTokens: 100,
            cacheReadInputTokens: 500,
            cacheCreationInputTokens: 0,
            outputTokens: 40)
        let glm46Expected = 100 * 2.25e-6 + 40 * 2.75e-6
        #expect(glm46Cost != nil)
        if let glm46Cost {
            #expect(abs(glm46Cost - glm46Expected) < 1e-12)
        }

        let glm45Cost = CostUsagePricing.claudeCostUSD(
            model: "glm-4.5-air",
            inputTokens: 200,
            cacheReadInputTokens: 1000,
            cacheCreationInputTokens: 0,
            outputTokens: 50)
        let glm45Expected = 200 * 2e-7 + 50 * 1.1e-6
        #expect(glm45Cost != nil)
        if let glm45Cost {
            #expect(abs(glm45Cost - glm45Expected) < 1e-12)
        }
    }
}
