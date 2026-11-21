import Foundation

extension CostUsageScanner {
    struct CodexRowCostBreakdown {
        var standardCostUSD: Double = 0
        var priorityCostUSD: Double = 0
        var ultrafastCostUSD: Double = 0
        var ultrafastTokens = 0
        var sawUltrafastCost = false
        var standardTokens: Int = 0
        var priorityTokens: Int = 0
        var sawStandardCost = false
        var sawPriorityCost = false
        var hasUnstableTokenRows = false
        var hasTokenOverflow = false
        var hasIncompletePricing = false
        /// Requests with tokens whose cost is known; marked or unresolvable requests are counted separately.
        var pricedRequestCount = 0
        var unpricedRequestCount = 0

        var optionalStandardCostUSD: Double? {
            self.sawStandardCost ? self.standardCostUSD : nil
        }

        var optionalPriorityCostUSD: Double? {
            self.sawPriorityCost ? self.priorityCostUSD : nil
        }

        var optionalStandardTokens: Int? {
            self.standardTokens > 0 ? self.standardTokens : nil
        }

        var optionalPriorityTokens: Int? {
            self.priorityTokens > 0 ? self.priorityTokens : nil
        }

        var totalCostUSD: Double? {
            guard self.sawStandardCost || self.sawPriorityCost || self.sawUltrafastCost else { return nil }
            return self.standardCostUSD + self.priorityCostUSD + self.ultrafastCostUSD
        }

        var hasModeSplit: Bool {
            (self.sawPriorityCost || self.priorityTokens > 0)
                && !self.sawUltrafastCost && self.ultrafastTokens == 0
        }

        /// The rows account for exactly the group's billed tokens, so their per-request costs describe it.
        func coversGroup(canonicalTotalTokens: Int) -> Bool {
            !self.hasUnstableTokenRows && !self.hasTokenOverflow
                && CheckedSum.integers([self.standardTokens, self.priorityTokens, self.ultrafastTokens])
                == canonicalTotalTokens
        }
    }

    static func codexRowCostBreakdown(
        rows: [CodexUsageRow],
        priorityTurns: [String: CodexPriorityTurnMetadata],
        modelsDevCatalog: ModelsDevCatalog?,
        modelsDevCacheRoot: URL?,
        customPricing: CostUsageCustomPricing? = nil,
        pricingResolver: CostUsagePricing.CodexResolver? = nil) -> CodexRowCostBreakdown
    {
        var breakdown = CodexRowCostBreakdown()
        for row in rows {
            let (tokenCount, tokenOverflow) = max(0, row.input).addingReportingOverflow(max(0, row.output))
            let hasTokens = row.input > 0 || row.cached > 0 || row.output > 0
            if tokenOverflow {
                breakdown.hasTokenOverflow = true
            }
            if hasTokens, row.eventIndex == nil {
                breakdown.hasUnstableTokenRows = true
            }
            let isMarkedUnpriced = (row.unpricedTokens ?? 0) > 0
            if isMarkedUnpriced {
                breakdown.hasIncompletePricing = true
            }
            let priorityMetadata = row.turnID.flatMap { priorityTurns[$0] }
            let isPriority = priorityMetadata != nil || row.pricingMode == "priority"
            if row.pricingMode == "ultrafast" {
                let (total, overflow) = breakdown.ultrafastTokens.addingReportingOverflow(tokenCount)
                breakdown.ultrafastTokens = overflow ? breakdown.ultrafastTokens : total
                breakdown.hasTokenOverflow = breakdown.hasTokenOverflow || overflow
            } else if isPriority {
                let (total, overflow) = breakdown.priorityTokens.addingReportingOverflow(tokenCount)
                breakdown.priorityTokens = overflow ? breakdown.priorityTokens : total
                breakdown.hasTokenOverflow = breakdown.hasTokenOverflow || overflow
            } else {
                let (total, overflow) = breakdown.standardTokens.addingReportingOverflow(tokenCount)
                breakdown.standardTokens = overflow ? breakdown.standardTokens : total
                breakdown.hasTokenOverflow = breakdown.hasTokenOverflow || overflow
            }
            // Retained history without proven pricing stays unknown; current list prices are not its price.
            guard !isMarkedUnpriced, let cost = self.codexResolvedCostUSD(
                for: row,
                priorityTurns: priorityTurns,
                modelsDevCatalog: modelsDevCatalog,
                modelsDevCacheRoot: modelsDevCacheRoot,
                customPricing: customPricing,
                pricingResolver: pricingResolver)
            else {
                breakdown.hasIncompletePricing = breakdown.hasIncompletePricing || hasTokens
                if hasTokens { breakdown.unpricedRequestCount += 1 }
                continue
            }
            if hasTokens { breakdown.pricedRequestCount += 1 }
            if row.pricingMode == "ultrafast" {
                breakdown.ultrafastCostUSD += cost
                breakdown.sawUltrafastCost = true
            } else if isPriority {
                breakdown.priorityCostUSD += cost
                breakdown.sawPriorityCost = true
            } else {
                breakdown.standardCostUSD += cost
                breakdown.sawStandardCost = true
            }
        }
        return breakdown
    }
}
