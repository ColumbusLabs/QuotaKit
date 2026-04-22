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
