import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct CLICostWindowTests {
    @Test(arguments: [false, true])
    func `long history JSON keeps thirty day totals separate`(openCodex: Bool) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let snapshot = Self.snapshot(rows: [
            Self.entry("2024-05-31", tokens: 800, cost: 8),
            Self.entry("2024-06-30", tokens: 200, cost: 2),
        ])
        let payload = openCodex
            ? CodexBarCLI.makeOpenCodexCostPayload(snapshot: snapshot, calendar: calendar)
            : CodexBarCLI.makeCostPayload(provider: .codex, snapshot: snapshot, error: nil, calendar: calendar)
        #expect(payload.last30DaysTokens == 200)
        #expect(payload.last30DaysCostUSD == 2)
        #expect(snapshot.last30DaysTokens == 1000)
    }

    @Test(arguments: [false, true])
    func `empty partially scanned long history window stays unknown`(openCodex: Bool) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let snapshot = Self.snapshot(
            rows: [Self.entry("2024-05-31", tokens: 1000, cost: 10)],
            historyScanIsPartial: true)
        let payload = openCodex
            ? CodexBarCLI.makeOpenCodexCostPayload(snapshot: snapshot, calendar: calendar)
            : CodexBarCLI.makeCostPayload(provider: .codex, snapshot: snapshot, error: nil, calendar: calendar)
        #expect(payload.last30DaysTokens == nil)
        #expect(payload.last30DaysCostUSD == nil)
    }

    @Test(arguments: [false, true])
    func `empty fully scanned window preserves per metric knownness`(openCodex: Bool) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let snapshot = Self.snapshot(
            rows: [Self.entry("2024-05-31", tokens: 1000, cost: 10)],
            last30DaysTokens: nil,
            last30DaysCostUSD: 10)
        let payload = openCodex
            ? CodexBarCLI.makeOpenCodexCostPayload(snapshot: snapshot, calendar: calendar)
            : CodexBarCLI.makeCostPayload(provider: .codex, snapshot: snapshot, error: nil, calendar: calendar)
        #expect(payload.last30DaysTokens == nil)
        #expect(payload.last30DaysCostUSD == 0)
    }

    @Test(arguments: [false, true])
    func `empty fully scanned long history reports known zero totals`(openCodex: Bool) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let snapshot = Self.snapshot(
            rows: [Self.entry("2024-05-31", tokens: 1000, cost: 10)],
            historyScanIsPartial: false)
        let payload = openCodex
            ? CodexBarCLI.makeOpenCodexCostPayload(snapshot: snapshot, calendar: calendar)
            : CodexBarCLI.makeCostPayload(provider: .codex, snapshot: snapshot, error: nil, calendar: calendar)
        #expect(payload.last30DaysTokens == 0)
        #expect(payload.last30DaysCostUSD == 0)
    }

    @Test(arguments: [false, true])
    func `empty partially scanned long history keeps totals unknown`(openCodex: Bool) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let snapshot = Self.snapshot(
            rows: [Self.entry("2024-05-31", tokens: 1000, cost: 10)],
            historyScanIsPartial: true)
        let payload = openCodex
            ? CodexBarCLI.makeOpenCodexCostPayload(snapshot: snapshot, calendar: calendar)
            : CodexBarCLI.makeCostPayload(provider: .codex, snapshot: snapshot, error: nil, calendar: calendar)
        #expect(payload.last30DaysTokens == nil)
        #expect(payload.last30DaysCostUSD == nil)
    }

    private static func snapshot(
        rows: [CostUsageDailyReport.Entry],
        last30DaysTokens: Int? = 1000,
        last30DaysCostUSD: Double? = 10,
        historyScanIsPartial: Bool = false) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: last30DaysTokens,
            last30DaysCostUSD: last30DaysCostUSD,
            historyDays: 365,
            historyCoverageIsEstablished: true,
            historyScanIsPartial: historyScanIsPartial,
            daily: rows,
            updatedAt: Date(timeIntervalSince1970: 1_719_793_800))
    }

    private static func entry(_ day: String, tokens: Int, cost: Double) -> CostUsageDailyReport.Entry {
        CostUsageDailyReport.Entry(
            date: day,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: tokens,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }
}
