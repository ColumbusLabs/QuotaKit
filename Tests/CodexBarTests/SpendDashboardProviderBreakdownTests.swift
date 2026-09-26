import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct SpendDashboardProviderBreakdownTests {
    @Test
    func `groups provider sources and models without losing partial cost evidence`() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = [
            SpendDashboardModel.ProviderRow(
                id: "codex-account", rank: 1, provider: .codex, displayName: "Codex Account",
                totalTokens: 120, totalCost: 2, coveredDayCount: 1,
                sourceKind: .native, incompleteRequestCount: 1, hasPartialCost: true),
            SpendDashboardModel.ProviderRow(
                id: "codex-opencodex", rank: 2, provider: .codex, displayName: "OpenCodex",
                totalTokens: 40, totalCost: nil, coveredDayCount: 1,
                sourceKind: .openCodex),
            SpendDashboardModel.ProviderRow(
                id: "claude", rank: 3, provider: .claude, displayName: "Claude",
                totalTokens: 30, totalCost: 1, coveredDayCount: 1),
        ]
        let model = SpendDashboardModel.ModelRow(
            rank: 1, provider: .codex, providerName: "Codex", modelName: "example-model",
            totalTokens: 160, totalCost: 2)
        let group = SpendDashboardModel.CurrencyGroup(
            currencyCode: "USD",
            providers: rows,
            models: [model],
            dailyPoints: [],
            totalTokens: 190,
            totalCost: 3,
            coveredDayCount: 1,
            chartDomain: now...now.addingTimeInterval(86400),
            modelHistoryCompleteness: .incomplete,
            incompleteModelProviders: [.codex])

        let grouped = spendDashboardProviderBreakdowns(group)
        let codex = try #require(grouped.first { $0.provider == .codex })
        #expect(grouped.count == 2)
        #expect(codex.subscriptions.map(\.id) == ["codex-account", "codex-opencodex"])
        #expect(codex.models.map(\.modelName) == ["example-model"])
        #expect(codex.totalTokens == 160)
        #expect(codex.totalCost == 2)
        #expect(codex.hasPartialCost)
        #expect(codex.hasPartialModelHistory)
        #expect(codex.incompleteRequestCount == 1)
        #expect(grouped.first?.provider == .codex)
    }

    @Test
    func `unknown provider costs stay unknown instead of becoming zero`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let group = SpendDashboardModel.CurrencyGroup(
            currencyCode: "USD",
            providers: [SpendDashboardModel.ProviderRow(
                id: "claude", rank: 1, provider: .claude, displayName: "Claude",
                totalTokens: 12, totalCost: nil, coveredDayCount: 1)],
            models: [],
            dailyPoints: [],
            totalTokens: 12,
            totalCost: nil,
            coveredDayCount: 1,
            chartDomain: now...now.addingTimeInterval(86400),
            modelHistoryCompleteness: .incomplete)
        let row = spendDashboardProviderBreakdowns(group).first
        #expect(row?.totalCost == nil)
        #expect(row?.totalTokens == 12)
        #expect(row?.hasPartialCost == true)
    }
}
