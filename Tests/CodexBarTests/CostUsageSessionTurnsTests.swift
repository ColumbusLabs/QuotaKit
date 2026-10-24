import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageSessionTurnsTests {
    @Test
    func `priced rows reconcile into turns requests and summary totals`() throws {
        let rows = [Self.row(0, turn: "a"), Self.row(1, turn: "a"), Self.row(2, turn: "b")]
        let session = try Self.session(rows)
        #expect(session.totalTokens == 330)
        #expect(session.reasoningTokens == 12)
        #expect(session.turns.map(\.turnID) == ["a", "b"])
        let first = try #require(session.turns.first)
        #expect(first.inputTokens == 200)
        #expect(first.cachedInputTokens == 160)
        #expect(first.outputTokens == 20)
        #expect(first.reasoningTokens == 8)
        #expect(first.totalTokens == 220)
        #expect(first.requestCount == 2)
        #expect(abs((first.costUSD ?? -1) - 0.2) < 1e-12)
        #expect(first.requests.count == 2)
        #expect(first.requests.map(\.inputTokens) == [100, 100])
        #expect(first.requests.map(\.cachedInputTokens) == [80, 80])
        #expect(first.requests.map(\.totalTokens) == [110, 110])
        #expect(first.requests.map(\.costUSD) == [0.1, 0.1])
        #expect(abs(session.turns.compactMap(\.costUSD).reduce(0, +) - (session.costUSD ?? -1)) < 1e-12)
    }

    @Test
    func `requests without turn ownership stay visibly unattributed`() throws {
        let session = try Self.session([Self.row(0, turn: "a"), Self.row(1, turn: nil)])
        let remainder = try #require(session.turns.last)
        #expect(remainder.turnID == nil)
        #expect(remainder.totalTokens == 110)
        #expect(remainder.requestCount == nil)
        #expect(remainder.requests.count == 1)
        #expect(abs((remainder.costUSD ?? -1) - 0.1) < 1e-12)
        #expect(session.turns.compactMap(\.totalTokens).reduce(0, +) == session.totalTokens)
    }

    @Test
    func `incomplete price or reasoning remains unavailable without dropping tokens`() throws {
        let session = try Self.session([
            Self.row(0, turn: "a"),
            Self.row(1, turn: "a", cost: nil, reasoning: nil),
        ])
        let turn = try #require(session.turns.first)
        #expect(turn.totalTokens == 220)
        #expect(turn.costUSD == nil)
        #expect(turn.reasoningTokens == nil)
        #expect(turn.requests.first?.costUSD == 0.1)
        #expect(turn.requests.last?.costUSD == nil)
        #expect(turn.requests.last?.reasoningTokens == nil)
    }

    @Test
    func `canonical summary reconciles ambiguous retained rows as unattributed`() throws {
        let session = try Self.session(
            [Self.row(0, turn: "a"), Self.row(1, turn: "b")],
            canonical: [100, 80, 10])
        #expect(session.totalTokens == 110)
        #expect(session.turns.compactMap(\.totalTokens).reduce(0, +) == 110)
        #expect(session.turns.allSatisfy { $0.turnID == nil })
    }

    @Test
    func `stored pricing mode survives selected request reconstruction`() throws {
        let row = Self.row(0, turn: "priority", cost: nil, model: "gpt-5.4", pricingMode: "priority")
        let session = try Self.session([row])
        #expect(try #require(session.costUSD) > 0)
        #expect(session.turns.first?.costUSD == session.costUSD)
        #expect(session.turns.first?.requests.first?.costUSD == session.costUSD)
    }

    private static func row(
        _ index: Int,
        turn: String?,
        day: String = "2026-10-21",
        model: String = "fictional-ledger-model",
        cost: Int64? = 100_000_000,
        reasoning: Int? = 4,
        pricingMode: String = "standard") -> CostUsageScanner.CodexUsageRow
    {
        CostUsageScanner.CodexUsageRow(
            day: day,
            model: model,
            turnID: turn,
            eventIndex: index,
            timestampUnixMs: (day == "2026-10-20" ? 1_792_476_000_000 : 1_792_562_400_000) + Int64(index * 1000),
            input: 100,
            cached: 80,
            output: 10,
            reasoning: reasoning,
            knownCostNanos: cost,
            pricingModel: model,
            pricingMode: pricingMode)
    }

    private static func session(
        _ rows: [CostUsageScanner.CodexUsageRow],
        canonical: [Int]? = nil) throws -> CostUsageSessionBreakdown
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 15)))
        var days: [String: [String: [Int]]] = [:]
        for row in rows {
            var counts = days[row.day]?[row.model] ?? [0, 0, 0]
            for (index, value) in [row.input, row.cached, row.output].enumerated() {
                counts[index] += value
            }
            days[row.day, default: [:]][row.model] = counts
        }
        if let canonical, let row = rows.first { days[row.day]?[row.model] = canonical }
        let usage = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: Int64(now.timeIntervalSince1970 * 1000),
            size: 1,
            days: days,
            parsedBytes: 1,
            sessionId: "synthetic-session",
            codexRows: rows,
            codexScanComplete: true)
        var cache = CostUsageCache()
        cache.files = ["/synthetic/session.jsonl": usage]
        cache.days = days
        let range = CostUsageScanner.CostUsageDayRange(since: now, until: now, calendar: calendar)
        let summary = try #require(CostUsageScanner.buildCodexSessionBreakdownsFromCache(
            cache: cache,
            range: range,
            modelsDevCatalog: ModelsDevCatalog(providers: [:])).first)
        #expect(summary.turns.isEmpty)
        var turns = CostUsageScanner.SessionTurns()
        let report = CostUsageScanner.buildCodexReportFromCache(
            cache: cache,
            range: range,
            modelsDevCatalog: ModelsDevCatalog(providers: [:]),
            onPricedRow: { row, cost, complete in turns.add(row, cost: cost, isComplete: complete) })
        return summary.withRequestDetails(turns.build(report: report))
    }
}
