import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct CostUsageCoverageAggregationTests {
    enum OverflowKind: CaseIterable {
        case sameCategory
        case combinedCategories
        case inferredRequests
    }

    @Test(arguments: [false, true], OverflowKind.allCases)
    func `separate day coverage overflow keeps snapshot and dashboard usable`(
        dashboard: Bool,
        kind: OverflowKind) throws
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-08-30T12:00:00Z"))
        let entries = [Int.max, 1, 1].enumerated().map { index, count in
            CostUsageDailyReport.Entry(
                date: "2026-08-\(28 + index)",
                inputTokens: 8,
                outputTokens: 2,
                totalTokens: 10,
                requestCount: kind == .inferredRequests ? count : nil,
                costUSD: 1,
                modelsUsed: nil,
                modelBreakdowns: nil,
                unmeteredRequestCount: kind == .combinedCategories && index == 1 ? 1 : nil,
                pricedRequestCount: kind == .inferredRequests ? nil :
                    (kind == .combinedCategories && index == 1 ? 0 : count))
        }
        let merged = CostUsageDailyReport.merged([.init(data: entries, summary: nil)])
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: 1,
            last30DaysTokens: 30,
            last30DaysCostUSD: 3,
            costProvenance: .listPriceEstimate,
            daily: merged.data,
            updatedAt: now)
        let expectedMix = CostUsageTokenMix(inputTokens: 24, outputTokens: 6)
        let coverage: CostUsageCoverageCounts
        if dashboard {
            let model = SpendDashboardModel.build(
                inputs: [.init(provider: .codex, displayName: "Codex", snapshot: snapshot)],
                requestedDays: 30,
                now: now,
                calendar: calendar)
            let group = try #require(model.groups.first)
            #expect(group.totalCost == 3)
            #expect(group.totalTokens == 30)
            #expect(group.tokenMix == expectedMix)
            #expect(group.provenance == .listPriceEstimate)
            coverage = group.coverage
        } else {
            let summary = snapshot.summary(forLastDays: 30, calendar: calendar)
            #expect(summary.totalCostUSD == 3)
            #expect(summary.totalTokens == 30)
            #expect(summary.totalRequests == nil)
            #expect(summary.tokenMix == expectedMix)
            #expect(summary.provenance == .listPriceEstimate)
            coverage = summary.coverage
        }
        #expect(coverage == CostUsageCoverageCounts(priced: 3))
        #expect(coverage.total == 3)
        #expect(coverage.coverageRatio == 1)
    }

    @Test(arguments: [false, true])
    func `account and currency grouping retain coverage fallbacks for overview`(_ separateCurrencies: Bool) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-08-30T12:00:00Z"))
        let inputs = [Int.max, 1, 1].enumerated().map { index, count in
            SpendDashboardModel.ProviderInput(
                id: "synthetic-source-\(index)",
                provider: .codex,
                displayName: "Synthetic source \(index)",
                snapshot: CostUsageTokenSnapshot(
                    sessionTokens: 10,
                    sessionCostUSD: 1,
                    last30DaysTokens: 10,
                    last30DaysCostUSD: 1,
                    currencyCode: separateCurrencies && index > 0 ? "EUR" : "USD",
                    daily: [.init(
                        date: "2026-08-30",
                        inputTokens: 8,
                        outputTokens: 2,
                        totalTokens: 10,
                        requestCount: count,
                        costUSD: 1,
                        modelsUsed: nil,
                        modelBreakdowns: nil,
                        pricedRequestCount: count)],
                    updatedAt: now))
        }
        let model = SpendDashboardModel.build(inputs: inputs, requestedDays: 30, now: now, calendar: calendar)
        #expect(model.groups.count == (separateCurrencies ? 2 : 1))
        #expect(model.groups.flatMap(\.providers).count == 3)
        #expect(model.groups.compactMap(\.totalTokens).reduce(0, +) == 30)
        if separateCurrencies {
            #expect(model.groups.first { $0.currencyCode == "USD" }?.totalCost == 1)
            #expect(model.groups.first { $0.currencyCode == "EUR" }?.totalCost == 2)
        } else {
            #expect(model.groups.first?.totalCost == 3)
        }
        let overview = OverviewSpendSummary(model: model, providerCount: 3)
        #expect(overview.pricingCoverageText == spendDashboardCoverageChipText(.init(priced: 3)))
        #expect(overview.tokenText == "30 tokens")
        #expect(overview.provenanceText == spendDashboardProvenanceText(.listPriceEstimate))
    }

    @Test
    func `invalid categories retain valid request inference in direct window consumers`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-08-30T12:00:00Z"))
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: 1,
            last30DaysTokens: 10,
            last30DaysCostUSD: 1,
            costProvenance: .listPriceEstimate,
            daily: [.init(
                date: "2026-08-30",
                inputTokens: 8,
                outputTokens: 2,
                totalTokens: 10,
                requestCount: 7,
                costUSD: 1,
                modelsUsed: nil,
                modelBreakdowns: nil,
                unpricedRequestCount: Int.max,
                unmeteredRequestCount: 1)],
            updatedAt: now)
        let summary = snapshot.summary(forLastDays: 30, calendar: calendar)
        #expect(summary.coverage == CostUsageCoverageCounts(priced: 7))
        #expect(summary.totalRequests == 7)
        #expect(summary.totalCostUSD == 1)
        let model = SpendDashboardModel.build(
            inputs: [.init(provider: .codex, displayName: "Codex", snapshot: snapshot)],
            requestedDays: 30,
            now: now,
            calendar: calendar)
        let group = try #require(model.groups.first)
        #expect(group.coverage == summary.coverage)
        #expect(group.totalCost == 1)
    }

    @Test
    func `representable boundary retains original coverage classifications`() {
        var accumulator = CostUsageCoverageAccumulator()
        for counts in [
            CostUsageCoverageCounts(priced: Int.max - 3),
            CostUsageCoverageCounts(unpriced: 1, unmetered: 1, estimated: 1),
        ] {
            accumulator.add(.init(
                date: "2026-08-30",
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: nil,
                costUSD: 1,
                modelsUsed: nil,
                modelBreakdowns: nil,
                unpricedRequestCount: counts.unpriced,
                unmeteredRequestCount: counts.unmetered,
                estimatedRequestCount: counts.estimated,
                pricedRequestCount: counts.priced))
        }
        #expect(accumulator.counts == CostUsageCoverageCounts(
            priced: Int.max - 3, unpriced: 1, unmetered: 1, estimated: 1))
        #expect(accumulator.counts.total == Int.max)
        #expect(accumulator.counts.coverageRatio != nil)
    }

    @Test
    func `estimates unpriced rows tokens and provenance survive currency aggregation`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-08-30T12:00:00Z"))
        let usd = Self.input(
            provider: .codex,
            currency: "USD",
            provenance: .mixed,
            entry: .init(
                date: "2026-08-30",
                inputTokens: 8,
                outputTokens: 2,
                totalTokens: 10,
                costUSD: 2,
                modelsUsed: nil,
                modelBreakdowns: nil,
                unpricedRequestCount: 1,
                estimatedRequestCount: 1,
                pricedRequestCount: 2),
            now: now)
        let eur = Self.input(
            provider: .claude,
            currency: "EUR",
            provenance: .vendorMetered,
            entry: .init(
                date: "2026-08-30",
                inputTokens: 15,
                outputTokens: 5,
                totalTokens: 20,
                costUSD: 4,
                modelsUsed: nil,
                modelBreakdowns: nil,
                unmeteredRequestCount: 3),
            now: now)
        let model = SpendDashboardModel.build(inputs: [usd, eur], requestedDays: 30, now: now, calendar: calendar)
        let groups = Dictionary(uniqueKeysWithValues: model.groups.map { ($0.currencyCode, $0) })
        #expect(groups["USD"]?.coverage == CostUsageCoverageCounts(priced: 2, unpriced: 1, estimated: 1))
        #expect(groups["EUR"]?.coverage == CostUsageCoverageCounts(unmetered: 3))
        #expect(groups["USD"]?.tokenMix == CostUsageTokenMix(inputTokens: 8, outputTokens: 2))
        #expect(groups["EUR"]?.tokenMix == CostUsageTokenMix(inputTokens: 15, outputTokens: 5))
        #expect(groups["USD"]?.provenance == .mixed)
        #expect(groups["EUR"]?.provenance == .vendorMetered)

        let overview = OverviewSpendSummary(model: model, providerCount: 2)
        #expect(overview.pricingCoverageText == spendDashboardCoverageChipText(
            .init(priced: 2, unpriced: 1, unmetered: 3, estimated: 1)))
        #expect(overview.tokenText == "30 tokens")
        #expect(overview.provenanceText.contains(spendDashboardProvenanceText(.mixed)))
        #expect(overview.provenanceText.contains(spendDashboardProvenanceText(.vendorMetered)))
    }

    private static func input(
        provider: UsageProvider,
        currency: String,
        provenance: CostProvenance,
        entry: CostUsageDailyReport.Entry,
        now: Date) -> SpendDashboardModel.ProviderInput
    {
        SpendDashboardModel.ProviderInput(
            provider: provider,
            displayName: provider.rawValue,
            snapshot: CostUsageTokenSnapshot(
                sessionTokens: entry.totalTokens,
                sessionCostUSD: entry.costUSD,
                last30DaysTokens: entry.totalTokens,
                last30DaysCostUSD: entry.costUSD,
                currencyCode: currency,
                costProvenance: provenance,
                daily: [entry],
                updatedAt: now))
    }
}
