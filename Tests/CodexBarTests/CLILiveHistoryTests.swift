import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct CLILiveHistoryTests {
    private static let updatedAt = Date(timeIntervalSince1970: 1_787_616_000)

    @Test
    func `live history preserves supplied period cost provenance and unknown totals`() {
        let snapshot = Self.usageSnapshot(
            label: "Billing period",
            tokens: nil,
            cost: 2.5,
            provenance: .vendorMetered,
            dailyTokens: 999)
        let text = Self.renderText(snapshot)
        let card = Self.card(snapshot)
        let expected = "Billing period: $2.50 (reported)"

        #expect(text.contains(expected))
        #expect(!text.contains("999 tokens"))
        #expect(card.historySummary == expected)
    }

    @Test
    func `live history retains explicit zero and singular token totals`() {
        let snapshot = Self.usageSnapshot(
            label: nil,
            days: 1,
            tokens: 1,
            cost: 0,
            provenance: .mixed)
        let expected = "Last 1 day: $0.00 (includes estimates) · 1 token"

        #expect(Self.renderText(snapshot).contains(expected))
        #expect(Self.card(snapshot).historySummary == expected)
    }

    @Test
    func `history card wraps the complete provider summary`() {
        let label = "A custom billing period with a deliberately long provider supplied label"
        let snapshot = Self.usageSnapshot(label: label, tokens: 15, cost: nil, provenance: .unknown)
        let card = Self.card(snapshot)
        let rows = CLICardsRenderer.renderCard(card, width: 38, useColor: false)
        let content = rows
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "│ ")) }
            .joined(separator: " ")

        #expect(card.historySummary == "\(label): 15 tokens")
        #expect(content.contains("\(label): 15 tokens"))
    }

    @Test
    func `missing provider totals do not become zero or fall back to daily rows`() {
        let snapshot = Self.usageSnapshot(
            label: "Unreported window",
            tokens: nil,
            cost: nil,
            provenance: .unknown,
            dailyTokens: 12)

        #expect(!Self.renderText(snapshot).contains("Unreported window"))
        #expect(Self.card(snapshot).historySummary == nil)
    }

    private static func renderText(_ snapshot: UsageSnapshot) -> String {
        CLIRenderer.renderText(
            provider: .openrouter,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(
                header: "OpenRouter",
                status: nil,
                useColor: false,
                resetStyle: .countdown),
            now: self.updatedAt.addingTimeInterval(90 * 24 * 60 * 60))
    }

    private static func card(_ snapshot: UsageSnapshot) -> CLICardModel {
        CLICardsRenderer.makeCard(CLICardBuildInput(
            provider: .openrouter,
            snapshot: snapshot,
            credits: nil,
            source: "fixture",
            status: nil,
            notes: [],
            useColor: false,
            resetStyle: .countdown,
            weeklyWorkDays: nil,
            now: self.updatedAt.addingTimeInterval(90 * 24 * 60 * 60)))
    }

    private static func usageSnapshot(
        label: String?,
        days: Int = 30,
        tokens: Int?,
        cost: Double?,
        provenance: CostProvenance,
        dailyTokens: Int? = nil) -> UsageSnapshot
    {
        let daily = [CostUsageDailyReport.Entry(
            date: "2026-08-17",
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: dailyTokens,
            costUSD: 9.99,
            modelsUsed: nil,
            modelBreakdowns: nil)]
        let history = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: tokens,
            last30DaysCostUSD: cost,
            currencyCode: "USD",
            historyDays: days,
            historyLabel: label,
            costProvenance: provenance,
            daily: daily,
            updatedAt: Self.updatedAt)
        return UsageSnapshot(primary: nil, secondary: nil, costUsage: history, updatedAt: Self.updatedAt)
    }
}
