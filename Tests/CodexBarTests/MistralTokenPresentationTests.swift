import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct MistralTokenPresentationTests {
    private static let now = Date(timeIntervalSince1970: 1_789_200_000)

    @Test
    func `unrepresentable token totals leave valid costs visible`() throws {
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let snapshot = try Self.snapshot(input: Int.max, cached: 1, daily: [
                .init(
                    day: "2026-09-02",
                    cost: 9.25,
                    inputTokens: Int.max,
                    cachedTokens: 1,
                    outputTokens: 0,
                    models: [.init(
                        name: "fixture-overflow",
                        cost: 9.25,
                        inputTokens: Int.max,
                        cachedTokens: 1,
                        outputTokens: 0)]),
            ])

            #expect(Self.summary(snapshot) == ["Latest: $9.25", "Month: $9.25"])
            let dashboard = try #require(UsageMenuCardView.Model.inlineUsageDashboard(input: Self.input(snapshot)))
            #expect(dashboard.kpis.contains { $0.value == "$9.25" })
            #expect(snapshot.toCostUsageTokenSnapshot().daily.first?.modelBreakdowns?.first?.costUSD == 9.25)
        }
    }

    @Test
    func `an overflowing named model total omits its ranking and keeps spend`() throws {
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let snapshot = try Self.snapshot(input: 3, daily: [
                .init(
                    day: "2026-09-01",
                    cost: 3.25,
                    inputTokens: 1,
                    cachedTokens: 0,
                    outputTokens: 0,
                    models: [.init(
                        name: "fixture-overflow",
                        cost: 3.25,
                        inputTokens: Int.max,
                        cachedTokens: 0,
                        outputTokens: 0)]),
                .init(
                    day: "2026-09-02",
                    cost: 9.25,
                    inputTokens: 2,
                    cachedTokens: 0,
                    outputTokens: 0,
                    models: [
                        .init(name: "fixture-overflow", cost: 9, inputTokens: 1, cachedTokens: 0, outputTokens: 0),
                        .init(name: "fixture-other", cost: 0.25, inputTokens: 1, cachedTokens: 0, outputTokens: 0),
                    ]),
            ])

            #expect(Self.summary(snapshot) == [
                "Latest: $9.25 · 2 tokens",
                "Month: $12.50 · 3 tokens",
            ])
            let dashboard = try #require(UsageMenuCardView.Model.inlineUsageDashboard(input: Self.input(snapshot)))
            #expect(!dashboard.detailLines.contains { $0.hasPrefix("Top model:") })
            #expect(dashboard.kpis.contains { $0.value == "$12.50" })
        }
    }

    private static func snapshot(
        input: Int,
        cached: Int = 0,
        output: Int = 0,
        daily: [MistralDailyUsageBucket]) throws -> MistralUsageSnapshot
    {
        let dateFormatter = ISO8601DateFormatter()
        let startDate = try #require(dateFormatter.date(from: "2026-09-01T00:00:00Z"))
        let endDate = try #require(dateFormatter.date(from: "2026-09-30T23:59:59Z"))
        return MistralUsageSnapshot(
            totalCost: daily.reduce(0) { $0 + $1.cost },
            currency: "USD",
            currencySymbol: "$",
            totalInputTokens: input,
            totalOutputTokens: output,
            totalCachedTokens: cached,
            modelCount: 2,
            daily: daily,
            startDate: startDate,
            endDate: endDate,
            updatedAt: self.now)
    }

    private static func summary(_ snapshot: MistralUsageSnapshot) -> [String] {
        var entries: [MenuDescriptor.Entry] = []
        MenuDescriptor.appendMistralUsageSummary(entries: &entries, usage: snapshot)
        return entries.compactMap { entry in
            guard case let .text(text, _) = entry else { return nil }
            return text
        }
    }

    private static func input(
        _ snapshot: MistralUsageSnapshot,
        historyDays: Int = 30,
        tokenOnly: Bool = false) throws -> UsageMenuCardView.Model.Input
    {
        try .init(
            provider: .mistral,
            metadata: #require(ProviderDefaults.metadata[.mistral]),
            snapshot: tokenOnly ? nil : snapshot.toUsageSnapshot(),
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: snapshot.toCostUsageTokenSnapshot(historyDays: historyDays),
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: true,
            costSummaryInlineEnabled: true,
            showOptionalCreditsAndExtraUsage: false,
            hidePersonalInfo: true,
            now: self.now)
    }
}
