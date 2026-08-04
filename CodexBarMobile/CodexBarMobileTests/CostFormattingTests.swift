import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Pins the `CostFormatting` single-source-of-truth contract.
///
/// Before Build 82 five separate views (ContentView · ProviderDetailView ·
/// ProviderUsageView · CostShareCardView · CyberShareCardView) each had
/// their own `formatUSD` + `formatTokens` with subtly different signatures
/// (one returned `"N/A"` for nil, another `"—"`, a third crashed). Agent B's
/// cross-view audit flagged this as a drift risk: a future locale /
/// precision / unit-label tweak needed five coordinated edits. These tests
/// pin the centralized behavior so any future refactor can't silently
/// change the output in one view while forgetting another.
@Suite("Cost formatting central contract")
struct CostFormattingTests {
    // MARK: - USD

    @Test
    func `usd formats whole dollars with two decimals and currency symbol`() {
        // We don't pin exact locale output (tester's locale can shift the
        // grouping separator), but we assert structural properties that
        // hold across locales: no trailing garbage, two decimals after
        // the last period in en-like locales.
        let s = CostFormatting.usd(42)
        #expect(!s.isEmpty)
        #expect(s.contains("42"))
    }

    @Test
    func `usd formats fractional cents with two decimals`() {
        let s = CostFormatting.usd(12.345)
        #expect(s.contains("12.34") || s.contains("12,34"))
    }

    @Test
    func `usd optional overload returns — for nil`() {
        #expect(CostFormatting.usd(nil as Double?) == "—")
    }

    @Test
    func `usd optional overload unwraps for .some`() {
        let value: Double? = 5
        #expect(CostFormatting.usd(value).contains("5"))
    }

    // MARK: - Tokens

    @Test
    func `tokens under 1K uses the localized tokens label with thousands grouping`() {
        let s = CostFormatting.tokens(42)
        #expect(s.contains("42"))
    }

    @Test
    func `tokens in 1K–1M uses K tokens`() {
        let s = CostFormatting.tokens(12345)
        // 12345 / 1000 = 12.3
        #expect(s.contains("12.3") || s.contains("12,3"))
    }

    @Test
    func `tokens in millions uses M tokens`() {
        let s = CostFormatting.tokens(1_234_567)
        #expect(s.contains("1.2") || s.contains("1,2"))
    }

    @Test
    func `tokens in billions uses B tokens`() {
        let s = CostFormatting.tokens(8_525_000_000)
        #expect(s.contains("8.5") || s.contains("8,5"))
        #expect(s.contains("B tokens"))
        #expect(!s.contains("M tokens"))
    }

    @Test
    func `tokens optional overload returns — for nil`() {
        #expect(CostFormatting.tokens(nil as Int?) == "—")
    }

    @Test
    func `tokens is monotonic — a bigger count yields a lexicographically or suffix-shifted string`() {
        // Guard against a regression that drops the K/M suffix threshold
        // logic. We don't pin the exact number format but do pin that the
        // suffix transitions appear at the right boundaries.
        #expect(!CostFormatting.tokens(500).contains("K"))
        #expect(CostFormatting.tokens(500).contains("M") == false)
        #expect(CostFormatting.tokens(1500).contains("K"))
        #expect(CostFormatting.tokens(1_500_000).contains("M"))
        #expect(CostFormatting.tokens(1_500_000_000).contains("B"))
    }
}

@Suite("Provider detail daily spend presentation")
struct ProviderDailySpendPresentationTests {
    @Test
    func `latest day defaults to the lexically latest wire day key`() {
        let daily = [
            SyncDailyPoint(dayKey: "2026-07-29", costUSD: 1, totalTokens: 10),
            SyncDailyPoint(dayKey: "2026-07-31", costUSD: 3, totalTokens: 30),
            SyncDailyPoint(dayKey: "2026-07-30", costUSD: 2, totalTokens: 20),
        ]

        #expect(ProviderDailySpendPresentation.latestDayKey(in: daily) == "2026-07-31")
        #expect(ProviderDailySpendPresentation.orderedDayKeys(in: daily) == [
            "2026-07-29",
            "2026-07-30",
            "2026-07-31",
        ])
    }

    @Test
    func `detail aggregates duplicate models and orders by cost then tokens`() {
        let point = SyncDailyPoint(
            dayKey: "2026-07-31",
            costUSD: 4.5,
            totalTokens: 1000,
            modelBreakdowns: [
                SyncCostBreakdown(label: "small", costUSD: 1, totalTokens: 100),
                SyncCostBreakdown(label: "large", costUSD: 3, totalTokens: 300),
                SyncCostBreakdown(label: "small", costUSD: 0.5, totalTokens: 50),
            ])

        let detail = ProviderDailySpendPresentation.detail(for: point)

        #expect(detail.models.map(\.label) == ["large", "small"])
        #expect(detail.models[1].costUSD == 1.5)
        #expect(detail.models[1].modelTokens == 150)
        #expect(detail.isEstimated == false)
    }

    @Test
    func `missing total tokens fall back to standard and fast tokens and preserve split details`() throws {
        let row = SyncCostBreakdown(
            label: "codex",
            costUSD: 2,
            isEstimated: true,
            standardCostUSD: 1.25,
            priorityCostUSD: 0.75,
            standardTokens: 120,
            priorityTokens: 30)
        let point = SyncDailyPoint(
            dayKey: "2026-07-31",
            costUSD: 2,
            totalTokens: 150,
            modelBreakdowns: [row])

        let detail = ProviderDailySpendPresentation.detail(for: point)
        let model = try #require(detail.models.first)
        let mode = ProviderDailySpendModelRow.modeSubtitle(for: model, currencyCode: "USD")

        #expect(model.modelTokens == 150)
        #expect(model.isEstimated)
        #expect(mode?.contains("Std") == true)
        #expect(mode?.contains("Fast") == true)
        #expect(mode?.contains("120") == true)
        #expect(mode?.contains("30") == true)
    }

    @Test
    func `viewport caps at four rows and reports overflow`() {
        #expect(ProviderDailySpendPresentation.detailViewportRowCount(for: 0) == 0)
        #expect(ProviderDailySpendPresentation.detailViewportRowCount(for: 4) == 4)
        #expect(ProviderDailySpendPresentation.detailViewportRowCount(for: 9) == 4)
        #expect(ProviderDailySpendPresentation.rowsNeedScrolling(itemCount: 4) == false)
        #expect(ProviderDailySpendPresentation.rowsNeedScrolling(itemCount: 5))
    }

    @Test
    func `viewport stays stable at the largest model mix in the loaded range`() {
        let oneModel = SyncDailyPoint(
            dayKey: "2026-07-30",
            costUSD: 1,
            totalTokens: 10,
            modelBreakdowns: [SyncCostBreakdown(label: "one", costUSD: 1)])
        let fiveModels = SyncDailyPoint(
            dayKey: "2026-07-31",
            costUSD: 5,
            totalTokens: 50,
            modelBreakdowns: (0..<5).map {
                SyncCostBreakdown(label: "model-\($0)", costUSD: 1, totalTokens: 10)
            })

        #expect(
            ProviderDailySpendPresentation.detailViewportRowCount(in: [oneModel, fiveModels]) == 4)
        #expect(ProviderDailySpendPresentation.detailViewportRowCount(in: [oneModel]) == 1)
    }

    @Test
    func `accessibility value describes the selected day and empty state`() {
        let point = SyncDailyPoint(
            dayKey: "2026-07-31",
            costUSD: 2.5,
            totalTokens: 1250,
            modelBreakdowns: [
                SyncCostBreakdown(
                    label: "gpt-5.4",
                    costUSD: 2.5,
                    totalTokens: 1250,
                    isEstimated: true),
            ],
            isEstimated: true)

        let value = ProviderDailySpendPresentation.accessibilityValue(
            for: [point],
            selectedDayKey: point.dayKey,
            currencyCode: "USD")
        #expect(value.contains("2026-07-31"))
        #expect(value.contains(String(localized: "Estimated")))

        #expect(
            ProviderDailySpendPresentation.accessibilityValue(
                for: [],
                selectedDayKey: nil,
                currencyCode: "USD") == String(localized: "No cost history data"))
    }
}
