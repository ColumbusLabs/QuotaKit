import SwiftUI

/// Single source of truth for provider-card tint colors.
///
/// Before iOS 1.3.0 / Build 70 this logic was duplicated (with subtle
/// drift) across 5 call sites: `ProviderUsageView.providerColor`,
/// `ProviderDetailView.providerColor`, `UtilizationAggregateView.providerColor(for:)`,
/// `ContentView.providerTint(for:)`, and `CostShareService.providerColor(for:)`.
/// Any new provider (e.g. Perplexity / OpenCode Go from upstream 0.20) had to
/// be added in 5 places or face color collisions across tabs.
///
/// Pass the `providerID` (the lowercase canonical ID like `"perplexity"` or
/// `"opencodego"`) — not the display name. The function lowercases + strips
/// spaces defensively so passing a display name still works, but prefer ID.
enum ProviderColorPalette {
    /// Returns the brand-aligned tint color for a provider.
    ///
    /// New provider additions MUST check the specificity ordering — narrower
    /// matches (`opencodego`) go **before** broader substrings (`opencode`)
    /// so we don't accidentally collapse two distinct providers back into the
    /// same color.
    static func color(for providerIdentifier: String) -> Color {
        let normalized = providerIdentifier
            .lowercased()
            .replacingOccurrences(of: " ", with: "")

        // Specific new providers from upstream v0.20 — these come first
        // because `opencodego.contains("opencode")` would otherwise grab the
        // more general rule below and collapse Go into Zen's blue.
        if normalized.contains("perplexity") {
            // Perplexity brand teal (#21808D) — distinct from Claude orange
            // and Codex purple.
            return Color(red: 0.13, green: 0.50, blue: 0.55)
        }
        if normalized.contains("opencodego") {
            // Mint — visually distinct from OpenCode Zen's blue so a user
            // with both products enabled can tell the cards apart at a glance.
            return .mint
        }

        // Specific new providers from upstream v0.21 / v0.23 (iOS 1.5.0).
        if normalized.contains("abacus") {
            // Abacus AI — brown/amber (#8B5E3C). Distinct from Claude's
            // orange-tan (warmer hue) and from any of the existing colors.
            // Picked to evoke the wooden-bead-counter abacus association
            // while staying readable in dark mode against neutral cards.
            return Color(red: 0.55, green: 0.37, blue: 0.24)
        }
        if normalized.contains("mistral") {
            // Mistral — vibrant red (#E63946). Mistral's official brand
            // color is fire-orange (#FF7A00) but that collides with
            // Claude's orange-tan; shifting to red preserves the warm-tone
            // brand intent while staying visually distinct in the card
            // grid and the 30-day utilization stacked bar chart.
            return Color(red: 0.90, green: 0.22, blue: 0.27)
        }

        // Existing provider mappings — preserved from pre-1.3.0 behavior.
        if normalized.contains("claude") || normalized.contains("anthropic") {
            return Color(red: 0.82, green: 0.55, blue: 0.28)
        }
        if normalized.contains("codex") || normalized.contains("cursor") {
            return .purple
        }
        if normalized.contains("openai") || normalized.contains("chatgpt") {
            return .green
        }
        if normalized.contains("gemini") {
            return .cyan
        }
        if normalized.contains("openrouter") {
            return Color(red: 0.42, green: 0.35, blue: 0.83)
        }
        if normalized.contains("opencode") {
            // OpenCode Zen (the original `opencode` ID). Kept at blue which
            // is also the implicit fallback, but making it explicit keeps
            // the matrix readable when a future provider claims the fallback.
            return .blue
        }
        return .blue
    }
}
