import Foundation

extension CostUsageScanner {
    static func canResumeCodexForkAccounting(
        _ cached: CostUsageFileUsage,
        context: CodexFileScanContext) throws -> Bool
    {
        guard let parentID = cached.forkedFromId,
              let saved = cached.codexForkAccountingState,
              !saved.metadata.isSubagentThread,
              saved.metadata.sessionId == cached.sessionId,
              saved.metadata.forkedFromId == parentID,
              let dependency = cached.forkBaselineDependencyKey
        else { return false }
        return try dependency == context.resources.inheritedResolver.currentDependencyKey(for: parentID)
    }

    /// Missing-parent forks stay out of priced totals. Count them as unmetered so Spend
    /// coverage can show the gap instead of silently dropping the session.
    static func unresolvedForkUnmeteredCounts(
        cache: CostUsageCache,
        range: CostUsageDayRange) -> [String: Int]
    {
        var counts: [String: Int] = [:]
        for usage in cache.files.values {
            guard self.isUnresolvedMissingParentFork(usage),
                  !self.codexFileHasBilledTokens(usage)
            else { continue }
            let unixMs = usage.codexSession?.startedAtUnixMs
                ?? usage.codexSession?.latestActivityUnixMs
                ?? usage.mtimeUnixMs
            guard unixMs > 0 else { continue }
            let dayKey = CostUsageDayRange.dayKey(
                from: Date(timeIntervalSince1970: TimeInterval(unixMs) / 1000),
                calendar: range.calendar)
            guard CostUsageDayRange.isInRange(dayKey: dayKey, since: range.sinceKey, until: range.untilKey)
            else { continue }
            counts[dayKey, default: 0] += 1
        }
        return counts
    }

    static func isUnresolvedMissingParentFork(_ usage: CostUsageFileUsage) -> Bool {
        usage.forkedFromId != nil
            && (usage.forkBaselineDependencyKey.map(self.codexDependencyIsMissing) ?? true)
    }

    static func codexDependencyIsMissing(_ key: String) -> Bool {
        key.hasPrefix("missing|") || key.contains("|inherited|missing|")
    }

    static func codexHistoryRangeHasUnsettledMissingParentFork(
        cache: CostUsageCache,
        range: CostUsageDayRange) -> Bool
    {
        cache.files.values.contains { usage in
            guard self.isUnresolvedMissingParentFork(usage) else { return false }
            guard usage.codexScanComplete == true, usage.hasCurrentCodexParser else { return true }
            return usage.touchesCodexScanWindow(
                sinceKey: range.sinceKey,
                untilKey: range.untilKey,
                calendar: range.calendar)
        }
    }

    static func codexFileHasBilledTokens(_ usage: CostUsageFileUsage) -> Bool {
        if (usage.codexRows ?? []).contains(where: { $0.input > 0 || $0.cached > 0 || $0.output > 0 }) {
            return true
        }
        return usage.days.values.contains { models in
            models.values.contains { packed in packed.contains { $0 > 0 } }
        }
    }

    struct CodexReportDayPricingContext {
        var rowsByDayModel: [String: [String: [CodexUsageRow]]]
        var unresolvedRowGroups: Set<CodexDayModelKey>
        var unresolvedPersistedRowGroups: Set<CodexDayModelKey>
        var modeOwnershipMismatchGroups: Set<CodexDayModelKey>
        var requestPricingEvidenceGroups: Set<CodexDayModelKey>
        var incompletePricingEvidenceGroups: Set<CodexDayModelKey>
        var priorityTurns: [String: CodexPriorityTurnMetadata]
        var modelsDevCatalog: ModelsDevCatalog
        var modelsDevCacheRoot: URL?
        var customPricing: CostUsageCustomPricing
        var pricingResolver: CostUsagePricing.CodexResolver
    }

    static func unmeteredForkReportEntry(day: String, unmetered: Int) -> CostUsageDailyReport.Entry? {
        guard unmetered > 0 else { return nil }
        return CostUsageDailyReport.Entry(
            date: day,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: nil,
            costUSD: nil,
            modelsUsed: nil,
            modelBreakdowns: nil,
            unmeteredRequestCount: unmetered)
    }

    static func makeCodexBilledDayEntry(
        day: String,
        models: [String: [Int]],
        unmetered: Int,
        pricing: CodexReportDayPricingContext) -> CostUsageDailyReport.Entry?
    {
        let modelNames = models.keys
            .filter { OpenCodexRouteDispatcher.countsTowardCodexSubscription(modelName: $0) }
            .sorted()
        if modelNames.isEmpty {
            return Self.unmeteredForkReportEntry(day: day, unmetered: unmetered)
        }
        var dayInput = CostUsageDailyReport.OptionalCountAccumulator(0)
        var dayCacheRead = CostUsageDailyReport.OptionalCountAccumulator(0)
        var dayOutput = CostUsageDailyReport.OptionalCountAccumulator(0)
        var dayReasoning = CostUsageDailyReport.OptionalCountAccumulator(0)
        var dayRequestCount = 0
        var dayUnpricedRequestCount = 0
        var breakdown: [CostUsageDailyReport.ModelBreakdown] = []
        var dayCost: Double = 0
        var dayCostSeen = false

        for model in modelNames {
            guard OpenCodexRouteDispatcher.countsTowardCodexSubscription(modelName: model) else { continue }
            let packed = models[model] ?? [0, 0, 0]
            let input = packed[safe: 0] ?? 0
            let cached = packed[safe: 1] ?? 0
            let output = packed[safe: 2] ?? 0
            let totalTokens = CheckedSum.integers([input, output])
            let rows = pricing.rowsByDayModel[day]?[model] ?? []
            let reasoning = CheckedSum.integers(rows.compactMap(\.reasoning))
            let requestCount = rows.count
            let unpricedRequestCount = rows.count { ($0.unpricedTokens ?? 0) > 0 }

            dayInput.add(input)
            dayCacheRead.add(cached)
            dayOutput.add(output)
            for row in rows {
                dayReasoning.add(row.reasoning)
            }
            dayRequestCount += requestCount
            dayUnpricedRequestCount += unpricedRequestCount

            let rowCost = rows.isEmpty ? nil : Self.codexRowCostBreakdown(
                rows: rows,
                priorityTurns: pricing.priorityTurns,
                modelsDevCatalog: pricing.modelsDevCatalog,
                modelsDevCacheRoot: pricing.modelsDevCacheRoot,
                customPricing: pricing.customPricing,
                pricingResolver: pricing.pricingResolver)
            let group = CodexDayModelKey(day: day, model: model)
            // A combined token counter can overflow while each source class and its supplied
            // monetary amount remain valid. Never replace authoritative dollars with repricing.
            let authoritativeOverflowCost = totalTokens == nil && !rows.isEmpty
                && rows.allSatisfy { $0.knownCostNanos != nil && ($0.unpricedTokens ?? 0) == 0 }
                && CheckedSum.integers(rows.map(\.input)) == input
                && CheckedSum.integers(rows.map(\.cached)) == cached
                && CheckedSum.integers(rows.map(\.output)) == output
            let rowCostIsTrusted = !pricing.unresolvedRowGroups.contains(group)
                && !pricing.modeOwnershipMismatchGroups.contains(group)
                && (authoritativeOverflowCost
                    || totalTokens.map { rowCost?.isTrusted(canonicalTotalTokens: $0) == true } == true)
            let aggregateCost = pricing.requestPricingEvidenceGroups.contains(group)
                || pricing.incompletePricingEvidenceGroups.contains(group)
                || pricing.unresolvedPersistedRowGroups.contains(group)
                || rowCost?.hasIncompletePricing == true
                ? nil
                : CostUsagePricing.codexAggregateCostUSD(
                    model: model,
                    inputTokens: input,
                    cachedInputTokens: cached,
                    outputTokens: output,
                    modelsDevCatalog: pricing.modelsDevCatalog,
                    modelsDevCacheRoot: pricing.modelsDevCacheRoot,
                    customPricing: pricing.customPricing)
            let cost = rowCostIsTrusted
                ? rowCost?.totalCostUSD ?? aggregateCost
                : aggregateCost
            let hasModeSplit = rowCostIsTrusted && rowCost?.hasModeSplit == true
            breakdown.append(
                CostUsageDailyReport.ModelBreakdown(
                    modelName: model,
                    costUSD: cost,
                    totalTokens: totalTokens,
                    requestCount: requestCount > 0 ? requestCount : nil,
                    inputTokens: input,
                    outputTokens: output,
                    cacheReadTokens: cached > 0 ? cached : nil,
                    reasoningTokens: reasoning.flatMap { $0 > 0 ? $0 : nil },
                    standardCostUSD: hasModeSplit ? rowCost?.optionalStandardCostUSD : nil,
                    priorityCostUSD: hasModeSplit ? rowCost?.optionalPriorityCostUSD : nil,
                    standardTokens: hasModeSplit ? rowCost?.optionalStandardTokens : nil,
                    priorityTokens: hasModeSplit ? rowCost?.optionalPriorityTokens : nil))
            if let cost {
                dayCost += cost
                dayCostSeen = true
            }
        }

        var dayTokens = dayInput
        dayTokens.merge(dayOutput)
        let dayTotal = dayTokens.value
        let entryCost = dayCostSeen && dayCost.isFinite ? dayCost : nil
        return CostUsageDailyReport.Entry(
            date: day,
            inputTokens: dayInput.value,
            outputTokens: dayOutput.value,
            cacheReadTokens: dayCacheRead.value.flatMap { $0 > 0 ? $0 : nil },
            reasoningTokens: dayReasoning.value.flatMap { $0 > 0 ? $0 : nil },
            totalTokens: dayTotal,
            requestCount: dayRequestCount > 0 ? dayRequestCount : nil,
            costUSD: entryCost,
            modelsUsed: modelNames,
            modelBreakdowns: Self.sortedModelBreakdowns(breakdown),
            unpricedRequestCount: dayUnpricedRequestCount > 0
                ? dayUnpricedRequestCount
                : (entryCost == nil && (dayTotal ?? 1) > 0 ? 1 : nil),
            unmeteredRequestCount: unmetered > 0 ? unmetered : nil)
    }
}

extension CostUsageFileUsage {
    func touchesCodexScanWindow(
        sinceKey: String,
        untilKey: String,
        calendar: Calendar = CostUsageScanner.CostUsageDayRange.localGregorianCalendar()) -> Bool
    {
        if self.days.keys.contains(where: {
            CostUsageScanner.CostUsageDayRange.isInRange(dayKey: $0, since: sinceKey, until: untilKey)
        }) {
            return true
        }

        // Billed days are empty for unresolved forks. Use the entire observed event span,
        // not just the start date: an old fork can contain current usage.
        let isIncompleteFork = self.codexBufferedUnresolvedForkLines != nil
            || CostUsageScanner.isUnresolvedMissingParentFork(self)
        guard isIncompleteFork else { return false }
        guard let first = self.codexSession?.startedAtUnixMs,
              let last = self.codexSession?.latestActivityUnixMs else { return true }
        let firstDay = CostUsageScanner.CostUsageDayRange.dayKey(
            from: Date(timeIntervalSince1970: TimeInterval(first) / 1000), calendar: calendar)
        let lastDay = CostUsageScanner.CostUsageDayRange.dayKey(
            from: Date(timeIntervalSince1970: TimeInterval(last) / 1000), calendar: calendar)
        return firstDay <= untilKey && lastDay >= sinceKey
    }
}
