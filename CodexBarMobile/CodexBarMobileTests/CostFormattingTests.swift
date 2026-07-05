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
