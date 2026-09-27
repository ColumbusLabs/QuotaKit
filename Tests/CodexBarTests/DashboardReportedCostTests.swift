import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct DashboardReportedCostTests {
    private static let now = Date(timeIntervalSince1970: 1_789_779_600)

    @Test(arguments: [0.0, 12.5])
    func `reported USD history keeps known zero and does not invent local Today`(amount: Double) throws {
        let cost = try #require(Self.dashboard(history: Self.history(cost: amount)).providers.first?.cost)
        #expect(cost.last30DaysUSD == amount)
        #expect(cost.todayUSD == nil)
    }

    @Test
    func `unsupported currency or window is not relabeled as thirty day USD`() {
        #expect(Self.dashboard(history: Self.history(cost: 12.5, currency: "EUR")).providers.first?.cost == nil)
        #expect(Self.dashboard(history: Self.history(cost: 12.5, days: 7)).providers.first?.cost == nil)
    }

    @Test
    func `local cost retains precedence over reported history`() throws {
        let local = CostPayload(
            provider: "openrouter", source: "local", updatedAt: Self.now,
            sessionTokens: nil, sessionCostUSD: nil, historyDays: 30,
            last30DaysTokens: nil, last30DaysCostUSD: 4,
            daily: [], totals: nil, error: nil)
        let cost = try #require(Self.dashboard(history: Self.history(cost: 99), local: local).providers.first?.cost)
        #expect(cost.last30DaysUSD == 4)
    }

    @Test
    func `incomplete reported history preserves unknown spend and excluded count`() throws {
        let breakdown = CostUsageDailyReport.ModelBreakdown(
            modelName: "openrouter-test", costUSD: nil, incompleteRequestCount: 2)
        let history = Self.history(cost: nil, breakdowns: [breakdown])
        let cost = try #require(Self.dashboard(history: history).providers.first?.cost)
        #expect(cost.last30DaysUSD == nil)
        #expect(cost.last30DaysIncompleteRequestCount == 2)
        #expect(cost.todayUSD == nil)
    }

    private static func history(
        cost: Double?,
        currency: String = "USD",
        days: Int = 30,
        breakdowns: [CostUsageDailyReport.ModelBreakdown] = []) -> CostUsageTokenSnapshot
    {
        let entry = CostUsageDailyReport.Entry(
            date: "2026-09-18", inputTokens: nil, outputTokens: nil,
            totalTokens: nil, costUSD: nil, modelsUsed: nil, modelBreakdowns: breakdowns)
        return CostUsageTokenSnapshot(
            sessionTokens: nil, sessionCostUSD: nil,
            last30DaysTokens: nil, last30DaysCostUSD: cost,
            currencyCode: currency, historyDays: days,
            daily: [entry], updatedAt: Self.now)
    }

    private static func dashboard(
        history: CostUsageTokenSnapshot?,
        local: CostPayload? = nil) -> DashboardSnapshotPayload
    {
        DashboardSnapshotBuilder.makeSnapshot(
            usagePayloads: [ProviderPayload(
                provider: .openrouter, account: nil, version: nil, source: "api", status: nil,
                usage: UsageSnapshot(primary: nil, secondary: nil, costUsage: history, updatedAt: self.now),
                credits: nil, antigravityPlanInfo: nil, openaiDashboard: nil, error: nil)],
            costPayloads: local.map { [$0] } ?? [],
            config: CodexBarConfig(providers: [ProviderConfig(id: .openrouter, enabled: true)]),
            identityMode: .redacted,
            generatedAt: self.now,
            refreshInterval: 60,
            codexBarVersion: nil)
    }
}
