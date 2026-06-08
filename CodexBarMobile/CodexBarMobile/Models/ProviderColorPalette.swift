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

        // Mirrors the Mac ProviderDescriptorRegistry branding colors for
        // customer-facing provider UI. Keep narrow matches before broad ones.
        //
        // Specific new providers from upstream v0.20 — these come first
        // because `opencodego.contains("opencode")` would otherwise grab the
        // more general rule below and collapse Go into Zen's blue.
        if normalized.contains("perplexity") {
            return Color(red: 32 / 255, green: 178 / 255, blue: 170 / 255)
        }
        if normalized.contains("opencodego") {
            return Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
        }

        // Specific new providers from upstream v0.21 / v0.23 (iOS 1.5.0).
        if normalized.contains("abacus") {
            return Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)
        }
        if normalized.contains("mistral") {
            return Color(red: 255 / 255, green: 80 / 255, blue: 15 / 255)
        }

        // Specific new providers from upstream v0.24 / v0.25 (iOS 1.6.0).
        // 10 picks; the 11th catch-up provider (`openai`, OpenAI API balance
        // from v0.25) inherits the existing ChatGPT-green rule below since
        // both share the `openai` providerID.
        //
        if normalized.contains("windsurf") {
            return Color(red: 52 / 255, green: 232 / 255, blue: 187 / 255)
        }
        if normalized.contains("codebuff") {
            return Color(red: 68 / 255, green: 255 / 255, blue: 0 / 255)
        }
        if normalized.contains("deepseek") {
            return Color(red: 0.32, green: 0.49, blue: 0.94)
        }
        if normalized.contains("manus") {
            return Color(red: 52 / 255, green: 50 / 255, blue: 45 / 255)
        }
        if normalized.contains("mimo") {
            return Color(red: 1.0, green: 105 / 255, blue: 0)
        }
        if normalized.contains("doubao") {
            return Color(red: 51 / 255, green: 112 / 255, blue: 255 / 255)
        }
        if normalized.contains("commandcode") {
            return Color(red: 0, green: 0, blue: 0)
        }
        if normalized.contains("stepfun") {
            return Color(red: 0.13, green: 0.59, blue: 0.95)
        }
        if normalized.contains("crof") {
            return Color(red: 0.18, green: 0.67, blue: 0.58)
        }
        if normalized.contains("venice") {
            return Color(red: 0.2, green: 0.6, blue: 1.0)
        }

        // iOS 1.8.0 — upstream v0.27.0 new providers (5 picks).
        // Color choices avoid the existing palette zones; new entries
        // sit beside their conceptual cluster (Grok/Groq both "warm"
        // brand-aligned shades distinct from Mistral red, ElevenLabs
        // pure-voice teal, Deepgram brand purple, LLM Proxy neutral
        // slate since it's a meta-provider).
        if normalized.contains("grok") {
            return Color(red: 16 / 255, green: 163 / 255, blue: 127 / 255)
        }
        if normalized.contains("groq") {
            return Color(red: 245 / 255, green: 104 / 255, blue: 68 / 255)
        }
        if normalized.contains("elevenlabs") {
            return Color(red: 0.92, green: 0.92, blue: 0.90)
        }
        if normalized.contains("deepgram") {
            // Deepgram — brand purple (#7C3AED). Distinct from
            // codex/cursor `.purple` (~#800080) by being more
            // saturated and bluer; sits between codex and openrouter
            // in the purple cluster without collapsing into either.
            return Color(red: 0.49, green: 0.23, blue: 0.93)
        }
        if normalized.contains("llmproxy") || normalized.contains("llm-proxy") {
            return Color(red: 36 / 255, green: 180 / 255, blue: 126 / 255)
        }

        // iOS 1.9.0 — upstream v0.28.0+v0.29.0 new providers (3 picks).
        // Checked BEFORE the generic `openai`/`opencode` rules below:
        // `"azureopenai".contains("openai")` is true, so Azure OpenAI must
        // match here first or it would collapse into the ChatGPT-green rule.
        if normalized.contains("azureopenai") {
            // Azure OpenAI — Microsoft Azure blue (#0078D4). Distinct from
            // the opencode `.blue` fallback and deepseek royal blue by being
            // a cleaner mid cyan-blue tied to the Azure brand.
            return Color(red: 0.0, green: 0.47, blue: 0.83)
        }
        if normalized.contains("alibabatokenplan") {
            return Color(red: 1.0, green: 106 / 255, blue: 0)
        }
        if normalized.contains("alibaba") {
            return Color(red: 1.0, green: 106 / 255, blue: 0)
        }
        if normalized.contains("t3chat") {
            return Color(red: 245 / 255, green: 102 / 255, blue: 71 / 255)
        }

        // iOS 1.7.0 — upstream v0.26.0 new providers.
        if normalized.contains("moonshot") || normalized.contains("kimi-api") {
            return Color(red: 32 / 255, green: 93 / 255, blue: 235 / 255)
        }
        if normalized.contains("bedrock") {
            // AWS Bedrock — AWS-orange (#FF9900). The most recognizable
            // AWS brand tint; reads cleanly against the cost-budget
            // gradient on the dedicated card.
            return Color(red: 1.00, green: 0.60, blue: 0.00)
        }
        // Earlier upstream providers without explicit entries (falls
        // back to .blue otherwise). Adding distinct tints so the
        // multi-card grid stays legible.
        if normalized.contains("kiro") {
            return Color(red: 255 / 255, green: 153 / 255, blue: 0 / 255)
        }
        if normalized.contains("zai") || normalized.contains("z.ai") {
            return Color(red: 232 / 255, green: 90 / 255, blue: 106 / 255)
        }
        if normalized.contains("antigravity") {
            return Color(red: 96 / 255, green: 186 / 255, blue: 126 / 255)
        }
        if normalized.contains("factory") || normalized.contains("droid") {
            return Color(red: 255 / 255, green: 107 / 255, blue: 53 / 255)
        }
        if normalized.contains("copilot") {
            return Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)
        }
        if normalized.contains("kimik2") || normalized.contains("kimik2unofficial") {
            return Color(red: 76 / 255, green: 0 / 255, blue: 255 / 255)
        }
        if normalized.contains("kimi") {
            return Color(red: 254 / 255, green: 96 / 255, blue: 60 / 255)
        }
        if normalized.contains("minimax") {
            return Color(red: 254 / 255, green: 96 / 255, blue: 60 / 255)
        }
        if normalized.contains("kilo") {
            return Color(red: 242 / 255, green: 112 / 255, blue: 39 / 255)
        }
        if normalized.contains("vertexai") || normalized.contains("vertex") {
            return Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)
        }
        if normalized.contains("augment") {
            return Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)
        }
        if normalized.contains("jetbrains") {
            return Color(red: 255 / 255, green: 51 / 255, blue: 153 / 255)
        }
        if normalized.contains("amp") {
            return Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
        }
        if normalized.contains("ollama") {
            return Color(red: 136 / 255, green: 136 / 255, blue: 136 / 255)
        }
        if normalized.contains("synthetic") {
            return Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
        }
        if normalized.contains("warp") {
            return Color(red: 147 / 255, green: 139 / 255, blue: 180 / 255)
        }

        // Existing provider mappings — preserved from pre-1.3.0 behavior.
        if normalized.contains("claude") || normalized.contains("anthropic") {
            return Color(red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        }
        if normalized.contains("codex") {
            return Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        }
        if normalized.contains("cursor") {
            return Color(red: 0, green: 0, blue: 0)
        }
        if normalized.contains("openai") || normalized.contains("chatgpt") {
            return Color(red: 0.06, green: 0.51, blue: 0.43)
        }
        if normalized.contains("gemini") {
            return Color(red: 171 / 255, green: 135 / 255, blue: 234 / 255)
        }
        if normalized.contains("openrouter") {
            return Color(red: 100 / 255, green: 103 / 255, blue: 242 / 255)
        }
        if normalized.contains("opencode") {
            return Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
        }
        return .blue
    }
}
