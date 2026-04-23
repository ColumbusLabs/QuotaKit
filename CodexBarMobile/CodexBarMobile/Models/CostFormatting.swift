import Foundation

/// Single source of truth for cost + token number formatting across the iOS app.
///
/// Before this file: `formatUSD` was duplicated in 5 views (ContentView,
/// ProviderDetailView, ProviderUsageView, CostShareCardView, CyberShareCardView)
/// and `formatTokens` in 4+ call sites with three subtly different signatures
/// (`Int`, `Int?`, with/without unit suffix). Agent B's cross-view audit
/// flagged this as a drift risk: any future locale / precision / unit-label
/// change would need coordinated edits to keep the views in lockstep, and
/// nothing was guarding that. Centralizing here collapses the risk into a
/// single function to test and review.
enum CostFormatting {
    /// Format a USD cost with two fractional digits, using the current
    /// locale's currency display style. Matches the `value.formatted(.currency(...))`
    /// API every pre-unified view was using.
    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// Optional variant so `LabeledContent(...)` call sites (which already pass
    /// `Int?`) don't each invent their own nil-guard.
    static func usd(_ value: Double?) -> String {
        value.map { Self.usd($0) } ?? "—"
    }

    /// Format a raw token count into a compact labeled string:
    /// `1,234 tokens` · `45.6K tokens` · `12.3M tokens`.
    /// Labels pass through the app's localized `tokens` / `K tokens` / `M tokens`
    /// string keys (en / zh-Hans / zh-Hant / ja already defined in
    /// `Localizable.xcstrings`).
    static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return "\(Self.compactNumber(Double(count) / 1_000_000)) \(String(localized: "M tokens"))"
        } else if count >= 1000 {
            return "\(Self.compactNumber(Double(count) / 1000)) \(String(localized: "K tokens"))"
        }
        return "\(count.formatted()) \(String(localized: "tokens"))"
    }

    /// Optional variant for `LabeledContent`-style call sites.
    static func tokens(_ count: Int?) -> String {
        count.map { Self.tokens($0) } ?? "—"
    }

    private static func compactNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
