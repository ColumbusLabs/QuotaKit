import Foundation

struct CostUsageCodexProjectedReport: Sendable {
    var report: CostUsageDailyReport
    var projects: [CostUsageProjectBreakdown]
    var sessions: [CostUsageSessionBreakdown]
}

enum CostUsageCodexReportProjectionBuilder {
    private struct DayModelKey: Hashable {
        var day: String
        var model: String
    }

    static func build(
        projection: CostUsageStoreCodexReportProjection,
        roots: [URL],
        range: CostUsageScanner.CostUsageDayRange,
        cacheRoot: URL?,
        includeBreakdowns: Bool) -> CostUsageCodexProjectedReport
    {
        let paths = Set(projection.cache.files.keys.filter {
            CostUsageScanner.isWithinCodexRoots(fileURL: URL(fileURLWithPath: $0), roots: roots)
        })
        let aggregatesByPath = Dictionary(grouping: projection.fileDayAggregates.filter {
            paths.contains($0.path)
        }, by: \.path)
        let scopedCache = CostUsageScanner.codexCache(projection.cache, scopedTo: roots)
        let report = self.report(
            aggregates: projection.fileDayAggregates.lazy
                .filter { paths.contains($0.path) }
                .map(\.aggregate),
            cache: scopedCache,
            range: range,
            cacheRoot: cacheRoot)
        guard includeBreakdowns else {
            return CostUsageCodexProjectedReport(report: report, projects: [], sessions: [])
        }
        return CostUsageCodexProjectedReport(
            report: report,
            projects: self.projects(
                aggregatesByPath: aggregatesByPath,
                cache: scopedCache,
                range: range,
                cacheRoot: cacheRoot),
            sessions: self.sessions(
                aggregatesByPath: aggregatesByPath,
                cache: scopedCache,
                range: range,
                cacheRoot: cacheRoot))
    }

    static func buildReport(
        projection: CostUsageStoreCodexReportProjection,
        range: CostUsageScanner.CostUsageDayRange,
        cacheRoot: URL?) -> CostUsageDailyReport
    {
        self.report(
            aggregates: projection.fileDayAggregates.map(\.aggregate),
            cache: projection.cache,
            range: range,
            cacheRoot: cacheRoot)
    }

    private static func report(
        aggregates: some Sequence<CostUsageStoreDayAggregate>,
        cache: CostUsageCache,
        range: CostUsageScanner.CostUsageDayRange,
        cacheRoot: URL?) -> CostUsageDailyReport
    {
        var grouped: [DayModelKey: CostUsageStoreDayAggregate] = [:]
        for aggregate in aggregates where CostUsageScanner.CostUsageDayRange.isInRange(
            dayKey: aggregate.day,
            since: range.sinceKey,
            until: range.untilKey)
        {
            let key = DayModelKey(day: aggregate.day, model: aggregate.model)
            var value = grouped[key] ?? .zero(day: key.day, model: key.model)
            value.add(aggregate)
            grouped[key] = value
        }
        _ = cacheRoot
        let unmeteredByDay = CostUsageScanner.unresolvedForkUnmeteredCounts(cache: cache, range: range)
        let days = Set(grouped.keys.map(\.day)).union(unmeteredByDay.keys).sorted()
        var entries: [CostUsageDailyReport.Entry] = []
        for day in days {
            let models = grouped.filter { $0.key.day == day }.map { ($0.key.model, $0.value) }
                .filter { OpenCodexRouteDispatcher.countsTowardCodexSubscription(modelName: $0.0) }
                .sorted { $0.0 < $1.0 }
            if models.isEmpty {
                if let entry = CostUsageScanner.unmeteredForkReportEntry(
                    day: day,
                    unmetered: unmeteredByDay[day] ?? 0)
                {
                    entries.append(entry)
                }
                continue
            }
            let modelBreakdowns = models.map { model, aggregate in
                self.modelBreakdown(model: model, aggregate: aggregate)
            }
            let input = modelBreakdowns.compactMap(\.inputTokens).reduce(0, +)
            let cached = modelBreakdowns.compactMap(\.cacheReadTokens).reduce(0, +)
            let output = modelBreakdowns.compactMap(\.outputTokens).reduce(0, +)
            let reasoning = modelBreakdowns.compactMap(\.reasoningTokens).reduce(0, +)
            let requestCount = modelBreakdowns.compactMap(\.requestCount).reduce(0, +)
            let costs = modelBreakdowns.compactMap(\.costUSD)
            let allPriced = costs.count == modelBreakdowns.count
            let unpricedRequests = zip(models, modelBreakdowns).reduce(into: 0) { count, pair in
                let aggregate = pair.0.1
                if aggregate.unpricedRequestCount > 0 {
                    count += Self.int(aggregate.unpricedRequestCount)
                } else if pair.1.costUSD == nil {
                    count += max(0, pair.1.requestCount ?? 0)
                }
            }
            entries.append(CostUsageDailyReport.Entry(
                date: day,
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cached > 0 ? cached : nil,
                reasoningTokens: reasoning > 0 ? reasoning : nil,
                totalTokens: input + output,
                requestCount: requestCount > 0 ? requestCount : nil,
                costUSD: allPriced ? costs.reduce(0, +) : nil,
                modelsUsed: models.map(\.0),
                modelBreakdowns: CostUsageScanner.sortedModelBreakdowns(modelBreakdowns),
                unpricedRequestCount: unpricedRequests > 0 ? unpricedRequests : nil,
                unmeteredRequestCount: (unmeteredByDay[day] ?? 0) > 0 ? unmeteredByDay[day] : nil))
        }
        let totalInput = entries.compactMap(\.inputTokens).reduce(0, +)
        let totalCached = entries.compactMap(\.cacheReadTokens).reduce(0, +)
        let totalOutput = entries.compactMap(\.outputTokens).reduce(0, +)
        let totalReasoning = entries.compactMap(\.reasoningTokens).reduce(0, +)
        let costs = entries.compactMap(\.costUSD)
        let summary = entries.isEmpty ? nil : CostUsageDailyReport.Summary(
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            cacheReadTokens: totalCached > 0 ? totalCached : nil,
            reasoningTokens: totalReasoning > 0 ? totalReasoning : nil,
            totalTokens: totalInput + totalOutput,
            totalCostUSD: costs.count == entries.count ? costs.reduce(0, +) : nil)
        return CostUsageDailyReport(data: entries, summary: summary)
    }

    // Compact row construction stays aligned with the scanner's persisted row shape.
    // swiftlint:disable multiline_arguments
    private static func modelBreakdown(
        model: String,
        aggregate: CostUsageStoreDayAggregate) -> CostUsageDailyReport.ModelBreakdown
    {
        let standardKnown = Double(aggregate.standardAuthoritativeCostNanos) / 1_000_000_000
        let priorityKnown = Double(aggregate.priorityAuthoritativeCostNanos) / 1_000_000_000
        let standardResolved = Double(aggregate.standardResolvedCostNanos) / 1_000_000_000
        let priorityResolved = Double(aggregate.priorityResolvedCostNanos) / 1_000_000_000
        let standardHasEvidence = aggregate.standardTokens > 0
            || aggregate.standardCachedTokens > 0
            || aggregate.standardAuthoritativeCostNanos != 0
            || aggregate.standardResolvedCostNanos != 0
            || aggregate.standardUnresolvedPricingCount > 0
        let priorityHasEvidence = aggregate.priorityTokens > 0
            || aggregate.priorityCachedTokens > 0
            || aggregate.priorityAuthoritativeCostNanos != 0
            || aggregate.priorityResolvedCostNanos != 0
            || aggregate.priorityUnresolvedPricingCount > 0
        let pricingComplete = aggregate.unpricedRequestCount == 0
            && aggregate.standardUnresolvedPricingCount == 0
            && aggregate.priorityUnresolvedPricingCount == 0
        let standardCost = pricingComplete ? standardKnown + standardResolved : nil
        let priorityCost = pricingComplete ? priorityKnown + priorityResolved : nil
        let totalCost = pricingComplete ? (standardCost ?? 0) + (priorityCost ?? 0) : nil
        let hasModeSplit = priorityHasEvidence
        return CostUsageDailyReport.ModelBreakdown(
            modelName: model,
            costUSD: totalCost,
            totalTokens: Self.int(aggregate.inputTokens + aggregate.outputTokens),
            requestCount: Self.int(aggregate.requestCount),
            inputTokens: Self.int(aggregate.inputTokens),
            outputTokens: Self.int(aggregate.outputTokens),
            cacheReadTokens: aggregate.cachedTokens > 0 ? Self.int(aggregate.cachedTokens) : nil,
            reasoningTokens: aggregate.reasoningTokens > 0 ? Self.int(aggregate.reasoningTokens) : nil,
            standardCostUSD: hasModeSplit && standardHasEvidence ? standardCost : nil,
            priorityCostUSD: hasModeSplit && priorityHasEvidence ? priorityCost : nil,
            standardTokens: hasModeSplit && aggregate.standardTokens > 0 ? Self.int(aggregate.standardTokens) : nil,
            priorityTokens: hasModeSplit && aggregate.priorityTokens > 0 ? Self.int(aggregate.priorityTokens) : nil)
    }

    private static func projects(
        aggregatesByPath: [String: [CostUsageStoreFileDayAggregate]],
        cache: CostUsageCache,
        range: CostUsageScanner.CostUsageDayRange,
        cacheRoot: URL?) -> [CostUsageProjectBreakdown]
    {
        let projectPathResolver = CostUsageScanner.CodexCanonicalProjectPathResolver()
        var pathsByProject: [String: [String]] = [:]
        var sourceByPath: [String: String] = [:]
        for (path, usage) in cache.files where aggregatesByPath[path] != nil {
            let project = usage.canonicalProjectPath
                ?? projectPathResolver.canonicalProjectPath(for: usage.projectPath)
                ?? ""
            pathsByProject[project, default: []].append(path)
            sourceByPath[path] = usage.projectPath ?? ""
        }
        return pathsByProject.compactMap { projectPath, paths in
            let report = self.report(
                aggregates: paths.flatMap { aggregatesByPath[$0] ?? [] }.map(\.aggregate),
                cache: self.cache(cache, paths: Set(paths)),
                range: range,
                cacheRoot: cacheRoot)
            guard !report.data.isEmpty else { return nil }
            let sources = Dictionary(grouping: paths, by: { sourceByPath[$0] ?? "" }).map { source, paths in
                let sourceReport = self.report(
                    aggregates: paths.flatMap { aggregatesByPath[$0] ?? [] }.map(\.aggregate),
                    cache: self.cache(cache, paths: Set(paths)),
                    range: range,
                    cacheRoot: cacheRoot)
                return CostUsageProjectSourceBreakdown(
                    name: self.projectName(source), path: source.isEmpty ? nil : source,
                    totalTokens: sourceReport.summary?.totalTokens,
                    totalCostUSD: sourceReport.summary?.totalCostUSD,
                    daily: sourceReport.data,
                    modelBreakdowns: self.mergedModelBreakdowns(sourceReport.data))
            }
            return CostUsageProjectBreakdown(
                name: self.projectName(projectPath), path: projectPath.isEmpty ? nil : projectPath,
                totalTokens: report.summary?.totalTokens, totalCostUSD: report.summary?.totalCostUSD,
                daily: report.data, modelBreakdowns: self.mergedModelBreakdowns(report.data),
                sources: sources.sorted(by: self.projectSourcePrecedes))
        }.sorted(by: self.projectPrecedes)
    }

    private static func sessions(
        aggregatesByPath: [String: [CostUsageStoreFileDayAggregate]],
        cache: CostUsageCache,
        range: CostUsageScanner.CostUsageDayRange,
        cacheRoot: URL?) -> [CostUsageSessionBreakdown]
    {
        var latest: [String: (String, CostUsageFileUsage)] = [:]
        for (path, usage) in cache.files where aggregatesByPath[path] != nil {
            let id = usage.sessionId ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if let existing = latest[id],
               existing.1.mtimeUnixMs > usage.mtimeUnixMs
               || (existing.1.mtimeUnixMs == usage.mtimeUnixMs && existing.0 <= path)
            {
                continue
            }
            if !id.isEmpty {
                latest[id] = (path, usage)
            }
        }
        return latest.compactMap { id, value in
            let report = self.report(
                aggregates: (aggregatesByPath[value.0] ?? []).map(\.aggregate),
                cache: self.cache(cache, paths: [value.0]), range: range, cacheRoot: cacheRoot)
            guard !report.data.isEmpty else { return nil }
            return CostUsageSessionBreakdown(
                sessionID: id, lastActivity: Date(timeIntervalSince1970: Double(value.1.mtimeUnixMs) / 1000),
                inputTokens: report.summary?.totalInputTokens,
                cachedInputTokens: report.summary?.cacheReadTokens,
                outputTokens: report.summary?.totalOutputTokens,
                reasoningTokens: report.summary?.reasoningTokens,
                totalTokens: report.summary?.totalTokens,
                requestCount: report.data.compactMap(\.requestCount).reduce(0, +),
                costUSD: report.summary?.totalCostUSD,
                modelBreakdowns: self.mergedModelBreakdowns(report.data) ?? [])
        }.sorted { lhs, rhs in
            if lhs.lastActivity != rhs.lastActivity {
                return lhs.lastActivity > rhs.lastActivity
            }
            return lhs.sessionID > rhs.sessionID
        }
    }

    // swiftlint:enable multiline_arguments
    private static func cache(_ source: CostUsageCache, paths: Set<String>) -> CostUsageCache {
        var value = source
        value.files = source.files.filter { paths.contains($0.key) }
        return value
    }

    private static func mergedModelBreakdowns(
        _ entries: [CostUsageDailyReport.Entry]) -> [CostUsageDailyReport.ModelBreakdown]?
    {
        let groups = Dictionary(grouping: entries.flatMap { $0.modelBreakdowns ?? [] }, by: \.modelName)
        guard !groups.isEmpty else { return nil }
        return CostUsageScanner.sortedModelBreakdowns(groups.map { name, values in
            CostUsageDailyReport.ModelBreakdown(
                modelName: name,
                costUSD: Self.sumOptional(values.map(\.costUSD)),
                totalTokens: Self.sumOptional(values.map(\.totalTokens)),
                requestCount: Self.sumOptional(values.map(\.requestCount)),
                inputTokens: Self.sumOptional(values.map(\.inputTokens)),
                outputTokens: Self.sumOptional(values.map(\.outputTokens)),
                cacheReadTokens: Self.sumOptional(values.map(\.cacheReadTokens)),
                reasoningTokens: Self.sumOptional(values.map(\.reasoningTokens)),
                standardCostUSD: Self.sumOptional(values.map(\.standardCostUSD)),
                priorityCostUSD: Self.sumOptional(values.map(\.priorityCostUSD)),
                standardTokens: Self.sumOptional(values.map(\.standardTokens)),
                priorityTokens: Self.sumOptional(values.map(\.priorityTokens)))
        })
    }

    private static func projectName(_ path: String) -> String {
        guard !path.isEmpty else { return CostUsageProjectBreakdown.unknownProjectName }
        let name = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func projectPrecedes(_ lhs: CostUsageProjectBreakdown, _ rhs: CostUsageProjectBreakdown) -> Bool {
        if lhs.totalCostUSD != rhs.totalCostUSD {
            return (lhs.totalCostUSD ?? -1) > (rhs.totalCostUSD ?? -1)
        }
        if lhs.totalTokens != rhs.totalTokens {
            return (lhs.totalTokens ?? -1) > (rhs.totalTokens ?? -1)
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func projectSourcePrecedes(
        _ lhs: CostUsageProjectSourceBreakdown,
        _ rhs: CostUsageProjectSourceBreakdown) -> Bool
    {
        if lhs.totalCostUSD != rhs.totalCostUSD {
            return (lhs.totalCostUSD ?? -1) > (rhs.totalCostUSD ?? -1)
        }
        if lhs.totalTokens != rhs.totalTokens {
            return (lhs.totalTokens ?? -1) > (rhs.totalTokens ?? -1)
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func sumOptional<T: AdditiveArithmetic>(_ values: [T?]) -> T? {
        let present = values.compactMap(\.self)
        return present.isEmpty ? nil : present.reduce(.zero, +)
    }

    private static func int(_ value: Int64) -> Int {
        Int(exactly: value) ?? (value < 0 ? Int.min : Int.max)
    }
}

extension CostUsageStoreDayAggregate {
    fileprivate mutating func add(_ other: Self) {
        self.inputTokens += other.inputTokens
        self.cachedTokens += other.cachedTokens
        self.outputTokens += other.outputTokens
        self.reasoningTokens += other.reasoningTokens
        self.requestCount += other.requestCount
        self.unpricedRequestCount += other.unpricedRequestCount
        self.authoritativeCostNanos += other.authoritativeCostNanos
        self.standardAuthoritativeCostNanos += other.standardAuthoritativeCostNanos
        self.priorityAuthoritativeCostNanos += other.priorityAuthoritativeCostNanos
        self.standardInputTokens += other.standardInputTokens
        self.standardCachedTokens += other.standardCachedTokens
        self.standardOutputTokens += other.standardOutputTokens
        self.priorityInputTokens += other.priorityInputTokens
        self.priorityCachedTokens += other.priorityCachedTokens
        self.priorityOutputTokens += other.priorityOutputTokens
        self.standardTokens += other.standardTokens
        self.priorityTokens += other.priorityTokens
        self.standardResolvedCostNanos += other.standardResolvedCostNanos
        self.priorityResolvedCostNanos += other.priorityResolvedCostNanos
        self.standardUnresolvedPricingCount += other.standardUnresolvedPricingCount
        self.priorityUnresolvedPricingCount += other.priorityUnresolvedPricingCount
    }
}
