import Foundation

extension CostUsagePricing {
    // Prices a recorded route without treating a model vendor namespace as its billing provider.
    // OpenAI retains historical/bundled behavior; other providers require exact cache-class rates.
    // swiftlint:disable:next function_parameter_count
    static func providerCostUSD(
        providerID: String,
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheWriteInputTokens: Int,
        outputTokens: Int,
        pricingDate: Date?,
        catalog: ModelsDevCatalog,
        customPricing: CostUsageCustomPricing) -> Double?
    {
        let targets = ModelsDevPricingTargetResolver.targets(providerID: providerID, modelID: model)
        guard let target = targets.first else { return nil }
        let customRates = customPricing.rates(providerID: providerID, model: model)
            ?? targets.lazy.compactMap { customPricing.rates(providerID: $0.providerID, model: $0.modelID) }.first
        if let customRates {
            let uncachedInput = max(0, inputTokens - max(0, cachedInputTokens))
            return CostUsageCustomPricing.costUSD(
                rates: customRates,
                inputTokens: max(0, uncachedInput - max(0, cacheWriteInputTokens)),
                outputTokens: outputTokens,
                cacheReadTokens: max(0, cachedInputTokens),
                cacheWriteTokens: max(0, cacheWriteInputTokens))
        }

        // Only OpenAI's own route can use OpenAI's bundled and historical fallback tables.
        if target.providerID == self.codexModelsDevProviderID,
           !target.modelID.contains("/")
        {
            return self.codexCostUSD(
                model: target.modelID,
                inputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                outputTokens: outputTokens,
                cacheWriteInputTokens: cacheWriteInputTokens,
                pricingDate: pricingDate,
                modelsDevCatalog: catalog,
                customPricing: .empty)
        }

        for target in targets {
            guard let lookup = catalog.pricing(
                providerID: target.providerID,
                modelID: target.modelID,
                exactModelID: true)
            else { continue }
            let rate = lookup.pricing
            guard cachedInputTokens <= 0 || rate.cacheReadInputCostPerToken != nil,
                  cacheWriteInputTokens <= 0 || rate.cacheCreationInputCostPerToken != nil
            else { return nil }

            let (inputWithCache, cacheOverflow) = max(0, inputTokens)
                .addingReportingOverflow(max(0, cachedInputTokens))
            let (inclusiveInput, writeOverflow) = inputWithCache
                .addingReportingOverflow(max(0, cacheWriteInputTokens))
            guard !cacheOverflow, !writeOverflow else { return nil }

            let pricing = CodexPricing(
                inputCostPerToken: rate.inputCostPerToken,
                outputCostPerToken: rate.outputCostPerToken,
                cacheReadInputCostPerToken: rate.cacheReadInputCostPerToken,
                displayLabel: nil,
                cacheWriteInputCostPerToken: rate.cacheCreationInputCostPerToken,
                thresholdTokens: rate.thresholdTokens,
                inputCostPerTokenAboveThreshold: rate.inputCostPerTokenAboveThreshold,
                outputCostPerTokenAboveThreshold: rate.outputCostPerTokenAboveThreshold,
                cacheReadInputCostPerTokenAboveThreshold: rate.cacheReadInputCostPerTokenAboveThreshold,
                cacheWriteInputCostPerTokenAboveThreshold: rate.cacheCreationInputCostPerTokenAboveThreshold)
            return self.codexCostUSD(
                pricing: pricing,
                inputTokens: inclusiveInput,
                cachedInputTokens: cachedInputTokens,
                cacheWriteInputTokens: cacheWriteInputTokens,
                outputTokens: outputTokens)
        }
        return nil
    }
}
