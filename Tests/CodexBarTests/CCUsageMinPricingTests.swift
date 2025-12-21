import Testing

@testable import CodexBarCore

@Suite
struct CCUsageMinPricingTests {
    @Test
    func normalizesCodexModelVariants() {
        #expect(CCUsageMinPricing.normalizeCodexModel("openai/gpt-5-codex") == "gpt-5")
        #expect(CCUsageMinPricing.normalizeCodexModel("gpt-5.2-codex") == "gpt-5.2")
        #expect(CCUsageMinPricing.normalizeCodexModel("gpt-5.1-codex-max") == "gpt-5.1")
    }

    @Test
    func codexCostSupportsGpt51CodexMax() {
        let cost = CCUsageMinPricing.codexCostUSD(
            model: "gpt-5.1-codex-max",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func normalizesClaudeOpus41DatedVariants() {
        #expect(CCUsageMinPricing.normalizeClaudeModel("claude-opus-4-1-20250805") == "claude-opus-4-1")
    }

    @Test
    func claudeCostSupportsOpus41DatedVariant() {
        let cost = CCUsageMinPricing.claudeCostUSD(
            model: "claude-opus-4-1-20250805",
            inputTokens: 10,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 5)
        #expect(cost != nil)
    }
}
