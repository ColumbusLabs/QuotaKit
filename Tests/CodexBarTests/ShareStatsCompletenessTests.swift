import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ShareStatsCompletenessTests {
    private static let now = Date(timeIntervalSince1970: 1_789_779_600)

    @Test
    func `incomplete provider does not erase complete model history`() throws {
        let payload = try #require(ShareStatsBuilder.make(model: Self.model(incomplete: [.claude])))

        #expect(payload.hasPartialModels)
        #expect(payload.modelRankingDetail == "PARTIAL")
        #expect(payload.topModels.map(\.provider) == [.codex])
        #expect(ShareStatsFormatting.text(payload).contains("Top models (partial):"))
    }

    @Test
    func `selected day models do not claim full window ranking`() throws {
        let payload = try #require(ShareStatsBuilder.make(model: Self.model(selectedDay: Self.now)))

        #expect(payload.hasPartialModels)
        #expect(payload.topModels.isEmpty)
    }

    @Test
    func `complete history retains normal ranking`() throws {
        let payload = try #require(ShareStatsBuilder.make(model: Self.model()))

        #expect(!payload.hasPartialModels)
        #expect(payload.topModels.map(\.provider) == [.codex, .claude])
        #expect(payload.modelRankingDetail == "BY USAGE")
    }

    @Test
    func `builder excludes an incomplete account without losing another provider`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let inputs: [SpendDashboardModel.ProviderInput] = [
            Self.input(provider: .codex, name: "Codex A", tokens: 30, cost: 3),
            Self.input(provider: .codex, name: "Codex B", tokens: 10, cost: 1, incomplete: 1),
            Self.input(provider: .claude, name: "Claude", tokens: 20, cost: 2),
        ]
        let model = SpendDashboardModel.build(
            inputs: inputs, requestedDays: 7, now: Self.now, calendar: calendar)
        let group = try #require(model.groups.first)
        let payload = try #require(ShareStatsBuilder.make(model: model))

        #expect(group.incompleteModelProviders == [.codex])
        #expect(payload.hasPartialModels)
        #expect(payload.topModels.map(\.provider) == [.claude])
    }

    private static func input(
        provider: UsageProvider,
        name: String,
        tokens: Int,
        cost: Double,
        incomplete: Int = 0) -> SpendDashboardModel.ProviderInput
    {
        let modelName = provider == .codex ? "gpt-4o" : "claude-sonnet-4"
        return .init(
            id: name,
            provider: provider,
            displayName: name,
            snapshot: CostUsageTokenSnapshot(
                sessionTokens: nil,
                sessionCostUSD: nil,
                last30DaysTokens: nil,
                last30DaysCostUSD: nil,
                daily: [.init(
                    date: "2026-09-18",
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: tokens,
                    costUSD: cost,
                    modelsUsed: nil,
                    modelBreakdowns: [.init(
                        modelName: modelName,
                        costUSD: cost,
                        totalTokens: tokens,
                        incompleteRequestCount: incomplete)])],
                updatedAt: Self.now))
    }

    private static func model(
        incomplete: Set<UsageProvider> = [],
        selectedDay: Date? = nil) -> SpendDashboardModel
    {
        let providers = [
            SpendDashboardModel.ProviderRow(
                id: "codex",
                rank: 1,
                provider: .codex,
                displayName: "Codex",
                totalTokens: 30,
                totalCost: 3,
                coveredDayCount: 7),
            SpendDashboardModel.ProviderRow(
                id: "claude",
                rank: 2,
                provider: .claude,
                displayName: "Claude",
                totalTokens: 20,
                totalCost: 2,
                coveredDayCount: 7),
        ]
        let models = [
            SpendDashboardModel.ModelRow(
                rank: 1,
                provider: .codex,
                providerName: "Codex",
                modelName: "gpt-4o",
                totalTokens: 30,
                totalCost: 3),
            SpendDashboardModel.ModelRow(
                rank: 2,
                provider: .claude,
                providerName: "Claude",
                modelName: "claude-sonnet-4",
                totalTokens: 20,
                totalCost: 2),
        ]
        let group = SpendDashboardModel.CurrencyGroup(
            currencyCode: "USD",
            providers: providers,
            models: models,
            dailyPoints: [],
            totalTokens: 50,
            totalCost: 5,
            coveredDayCount: 7,
            chartDomain: Self.now.addingTimeInterval(-6 * 86400)...Self.now,
            modelHistoryCompleteness: incomplete.isEmpty ? .complete : .incomplete,
            incompleteModelProviders: incomplete,
            selectedDay: selectedDay)
        return SpendDashboardModel(requestedDays: 7, groups: [group])
    }
}
