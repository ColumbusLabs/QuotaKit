import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageStoreAggregateTests {
    @Test
    func `file aggregates preserve packed and per-row accounting semantics`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-cost-aggregate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CostUsageStore(cacheRoot: root)
        let path = "/sessions/aggregate-parity.jsonl"
        let day = "2026-08-01"
        let packedOnlyDay = "2026-08-02"
        let metadataOnlyDay = "2026-08-03"
        let rows = [
            Self.row(
                day: day,
                model: "gpt-5.5",
                eventIndex: 0,
                input: 90,
                cached: 8,
                output: 15,
                reasoning: 4,
                knownCostNanos: 1000,
                pricingMode: "standard"),
            Self.row(
                day: day,
                model: "gpt-5.5",
                eventIndex: 1,
                input: 10,
                cached: 2,
                output: 5,
                reasoning: 1,
                knownCostNanos: 2000,
                pricingMode: "priority"),
            Self.row(
                day: day,
                model: "gpt-5.5",
                eventIndex: 2,
                input: 20,
                cached: 5,
                output: 3,
                reasoning: 2,
                pricingMode: "standard"),
            Self.row(
                day: day,
                model: "unknown-model",
                eventIndex: 3,
                input: 7,
                cached: 2,
                output: 4,
                reasoning: 1,
                pricingMode: "standard"),
            Self.row(
                day: day,
                model: "unknown-model",
                eventIndex: 4,
                input: 3,
                cached: 1,
                output: 2,
                unpricedTokens: 5,
                pricingMode: "priority"),
            Self.row(
                day: packedOnlyDay,
                model: "row-only-model",
                eventIndex: 5,
                input: 11,
                cached: 1,
                output: 6,
                pricingMode: "standard"),
        ]
        var usage = CostUsageFileUsage(
            mtimeUnixMs: 1_754_046_000_000,
            size: 512,
            days: [
                day: ["gpt-5.5": [100, 10, 20]],
                packedOnlyDay: ["packed-only-model": [7, 2, 1]],
            ])
        usage.parsedBytes = 512
        usage.codexRows = rows
        usage.codexCostNanos = [metadataOnlyDay: ["cost-only-model": 12]]
        usage.codexPrioritySurchargeNanos = [metadataOnlyDay: ["surcharge-only-model": 13]]
        usage.codexStandardTokens = [metadataOnlyDay: ["metadata-only-model": 14]]

        let expectedFileAggregates = Self.legacyFileAggregates(usage)
        let measured = CostUsageStore.fileAggregatesForTesting(usage)
        #expect(measured == expectedFileAggregates)
        #expect(measured.map { ($0.day, $0.model) }.map { "\($0.0)/\($0.1)" } == [
            "2026-08-01/gpt-5.5",
            "2026-08-01/unknown-model",
            "2026-08-02/packed-only-model",
            "2026-08-02/row-only-model",
            "2026-08-03/cost-only-model",
            "2026-08-03/metadata-only-model",
            "2026-08-03/surcharge-only-model",
        ])

        var cache = CostUsageCache()
        cache.scanSinceKey = day
        cache.scanUntilKey = metadataOnlyDay
        cache.days = usage.days
        cache.files[path] = usage
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let saved = store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: day, untilKey: metadataOnlyDay))
        #expect(!saved.catchUpRequired)

        let persistedFile = await store.fetchFileDayAggregates(path: path)
        #expect(persistedFile == expectedFileAggregates)
        let global = await store.fetchDayAggregates(sinceDay: day, untilDay: metadataOnlyDay)
        #expect(global.map { "\($0.day)/\($0.model)" } == [
            "2026-08-01/gpt-5.5",
            "2026-08-02/packed-only-model",
        ])
        let packed = try #require(global.first)
        #expect(packed.inputTokens == 100)
        #expect(packed.cachedTokens == 10)
        #expect(packed.outputTokens == 20)
        #expect(packed.requestCount == 3)
        #expect(packed.unpricedRequestCount == 0)
        #expect(packed.authoritativeCostNanos == 3000)
        #expect(packed.standardAuthoritativeCostNanos == 1000)
        #expect(packed.priorityAuthoritativeCostNanos == 2000)
        #expect(packed.standardResolvedCostNanos > 0)
        #expect(packed.standardUnresolvedPricingCount == 0)
    }

    @Test
    func `aggregate row visits stay constant as key cardinality grows`() {
        let rowCount = 64
        let pricing = CostUsageCustomPricing(
            entries: Dictionary(uniqueKeysWithValues: (0..<rowCount).map { index in
                ("priced-\(index)", .init(input: 1, output: 2))
            }),
            fingerprint: "aggregate-test")
        func measuredVisits(uniqueKeys: Bool) -> (rows: [CostUsageStoreDayAggregate], visits: Int) {
            var usage = CostUsageFileUsage(mtimeUnixMs: 1, size: 0, days: [:])
            usage.codexRows = (0..<rowCount).map { index in
                Self.row(
                    day: "2026-08-01",
                    model: "priced-\(uniqueKeys ? index : 0)",
                    eventIndex: index,
                    input: 20,
                    cached: 3,
                    output: 5,
                    pricingMode: "standard")
            }
            var visits = 0
            let rows = CostUsageStore.fileAggregatesForTesting(
                usage,
                customPricing: pricing,
                onRowVisit: { visits += 1 })
            return (rows, visits)
        }

        let lowCardinality = measuredVisits(uniqueKeys: false)
        let highCardinality = measuredVisits(uniqueKeys: true)
        #expect(lowCardinality.rows.count == 1)
        #expect(highCardinality.rows.count == rowCount)
        #expect(lowCardinality.visits == rowCount)
        #expect(highCardinality.visits == rowCount)
    }

    // Keep fixture fields named so each synthetic pricing/accounting case remains readable.
    // swiftlint:disable:next function_parameter_count
    private static func row(
        day: String,
        model: String,
        eventIndex: Int,
        input: Int,
        cached: Int,
        output: Int,
        reasoning: Int? = nil,
        knownCostNanos: Int64? = nil,
        unpricedTokens: Int? = nil,
        pricingMode: String?) -> CostUsageScanner.CodexUsageRow
    {
        CostUsageScanner.CodexUsageRow(
            day: day,
            model: model,
            turnID: nil,
            eventIndex: eventIndex,
            input: input,
            cached: cached,
            output: output,
            reasoning: reasoning,
            knownCostNanos: knownCostNanos,
            unpricedTokens: unpricedTokens,
            pricingModel: model,
            pricingMode: pricingMode)
    }

    private static func legacyFileAggregates(_ usage: CostUsageFileUsage) -> [CostUsageStoreDayAggregate] {
        struct Key: Hashable {
            var day: String
            var model: String
        }
        var keys = Set<Key>()
        func addKeys(_ map: [String: [String: some Any]]?) {
            for (day, models) in map ?? [:] {
                for model in models.keys {
                    keys.insert(Key(day: day, model: model))
                }
            }
        }
        addKeys(usage.days)
        addKeys(usage.codexCostNanos)
        addKeys(usage.codexPrioritySurchargeNanos)
        addKeys(usage.codexStandardCostNanos)
        addKeys(usage.codexPriorityCostNanos)
        addKeys(usage.codexStandardTokens)
        addKeys(usage.codexPriorityTokens)
        let rowsByKey = Dictionary(grouping: usage.codexRows ?? []) { Key(day: $0.day, model: $0.model) }
        keys.formUnion(rowsByKey.keys)
        return keys.map { key in
            let packed = usage.days[key.day]?[key.model] ?? []
            let rows = rowsByKey[key] ?? []
            var aggregate = CostUsageStoreDayAggregate.zero(day: key.day, model: key.model)
            aggregate.inputTokens = Int64(packed[safe: 0] ?? 0)
            aggregate.cachedTokens = Int64(packed[safe: 1] ?? 0)
            aggregate.outputTokens = Int64(packed[safe: 2] ?? 0)
            aggregate.reasoningTokens = Int64(rows.compactMap(\.reasoning).reduce(0, +))
            aggregate.requestCount = Int64(rows.count)
            aggregate.unpricedRequestCount = Int64(rows.count { ($0.unpricedTokens ?? 0) > 0 })
            for row in rows {
                let isPriority = row.pricingMode == "priority"
                let total = Int64(max(0, row.input) + max(0, row.output))
                if isPriority {
                    aggregate.priorityTokens += total
                } else {
                    aggregate.standardTokens += total
                }
                if let cost = row.knownCostNanos {
                    aggregate.authoritativeCostNanos += cost
                    if isPriority {
                        aggregate.priorityAuthoritativeCostNanos += cost
                    } else {
                        aggregate.standardAuthoritativeCostNanos += cost
                    }
                } else {
                    let resolved = CostUsageScanner.codexResolvedCostNanos(
                        for: row,
                        modelsDevCatalog: nil,
                        modelsDevCacheRoot: nil,
                        customPricing: .empty)
                    if isPriority {
                        aggregate.priorityInputTokens += Int64(row.input)
                        aggregate.priorityCachedTokens += Int64(row.cached)
                        aggregate.priorityOutputTokens += Int64(row.output)
                        if let resolved {
                            aggregate.priorityResolvedCostNanos += resolved
                        } else {
                            aggregate.priorityUnresolvedPricingCount += 1
                        }
                    } else {
                        aggregate.standardInputTokens += Int64(row.input)
                        aggregate.standardCachedTokens += Int64(row.cached)
                        aggregate.standardOutputTokens += Int64(row.output)
                        if let resolved {
                            aggregate.standardResolvedCostNanos += resolved
                        } else {
                            aggregate.standardUnresolvedPricingCount += 1
                        }
                    }
                }
            }
            return aggregate
        }.sorted { ($0.day, $0.model) < ($1.day, $1.model) }
    }
}
