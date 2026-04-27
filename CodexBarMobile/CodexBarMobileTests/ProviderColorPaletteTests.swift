import SwiftUI
import Testing

@testable import CodexBarMobile

/// Pins the consolidated provider-tint palette introduced in iOS 1.3.0 (70).
///
/// Before Build 70 this logic was duplicated (with subtle drift) across 5
/// files. Any new provider (e.g. Perplexity / OpenCode Go) required touching
/// all 5, and the aggregate utilization view even had a different semantic
/// (exact-match + `.gray` default) than the rest. These tests pin:
///   - new upstream-0.20 providers get distinct brand-aligned tints
///   - pre-existing providers keep their established colors (no silent regression)
///   - specificity ordering: `opencodego` never collapses into the broader
///     `opencode` match
///   - normalization lets callers pass either `providerID` (`"opencodego"`)
///     or `providerName` (`"OpenCode Go"`) and get the same color
@Suite("Provider color palette")
struct ProviderColorPaletteTests {
    @Test("Perplexity resolves to its brand teal (#21808D)")
    func perplexityIsTeal() {
        let color = ProviderColorPalette.color(for: "perplexity")
        // Reconstruct the brand teal and compare. Use UIColor for RGBA
        // extraction because SwiftUI `Color` doesn't expose components
        // directly across platforms.
        let expected = UIColor(red: 0.13, green: 0.50, blue: 0.55, alpha: 1)
        #expect(UIColor(color).isApproximately(expected))
    }

    @Test("OpenCode Go resolves to mint (distinct from OpenCode Zen's blue)")
    func opencodeGoIsMint() {
        let go = ProviderColorPalette.color(for: "opencodego")
        let zen = ProviderColorPalette.color(for: "opencode")
        #expect(UIColor(go).isApproximately(UIColor(.mint)))
        #expect(UIColor(zen).isApproximately(UIColor(.blue)))
        // Sanity: the two colors are actually different.
        #expect(!UIColor(go).isApproximately(UIColor(zen)))
    }

    @Test("Specificity: `opencodego` is NOT collapsed into `opencode` rule")
    func opencodeGoDoesNotCollideWithOpencode() {
        // `"opencodego".contains("opencode") == true`, so the specificity
        // ordering in the palette matters. A naive reordering would regress
        // this test.
        let go = ProviderColorPalette.color(for: "opencodego")
        #expect(UIColor(go).isApproximately(UIColor(.mint)))
        #expect(!UIColor(go).isApproximately(UIColor(.blue)))
    }

    @Test("Claude keeps brand orange across ID and name inputs")
    func claudeIsBrandOrange() {
        let expected = UIColor(red: 0.82, green: 0.55, blue: 0.28, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "claude")).isApproximately(expected))
        #expect(UIColor(ProviderColorPalette.color(for: "Claude")).isApproximately(expected))
        #expect(UIColor(ProviderColorPalette.color(for: "anthropic")).isApproximately(expected))
    }

    @Test("Codex stays purple")
    func codexIsPurple() {
        #expect(
            UIColor(ProviderColorPalette.color(for: "codex"))
                .isApproximately(UIColor(.purple)))
    }

    @Test("Normalization: display name with spaces matches providerID")
    func displayNameMatchesID() {
        // `"opencodego".lowercased().replacingOccurrences(of: " ", with: "")` vs
        // `"OpenCode Go".lowercased().replacingOccurrences(of: " ", with: "")`
        // should resolve to the same color, so callers passing displayName
        // (e.g. CostShareService pre-refactor) don't silently fall to the
        // generic blue fallback.
        let byID = ProviderColorPalette.color(for: "opencodego")
        let byName = ProviderColorPalette.color(for: "OpenCode Go")
        #expect(UIColor(byID).isApproximately(UIColor(byName)))
    }

    @Test("Empty input falls to blue (not a crash)")
    func emptyFallsToBlue() {
        #expect(
            UIColor(ProviderColorPalette.color(for: ""))
                .isApproximately(UIColor(.blue)))
    }

    @Test("Unknown provider falls to blue")
    func unknownFallsToBlue() {
        #expect(
            UIColor(ProviderColorPalette.color(for: "brand-new-ai-tool"))
                .isApproximately(UIColor(.blue)))
    }

    @Test("Gemini stays cyan (was only in UtilizationAggregateView pre-consolidation)")
    func geminiIsCyan() {
        #expect(
            UIColor(ProviderColorPalette.color(for: "gemini"))
                .isApproximately(UIColor(.cyan)))
    }

    @Test("OpenRouter keeps its custom indigo")
    func openrouterIsIndigo() {
        let expected = UIColor(red: 0.42, green: 0.35, blue: 0.83, alpha: 1)
        #expect(
            UIColor(ProviderColorPalette.color(for: "openrouter"))
                .isApproximately(expected))
    }

    // MARK: - iOS 1.5.0 · Abacus + Mistral additions

    @Test("Abacus AI resolves to its warm brown tone")
    func abacusIsBrown() {
        let expected = UIColor(red: 0.55, green: 0.37, blue: 0.24, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "abacus")).isApproximately(expected))
    }

    @Test("Mistral resolves to its vibrant red")
    func mistralIsRed() {
        let expected = UIColor(red: 0.90, green: 0.22, blue: 0.27, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "mistral")).isApproximately(expected))
    }

    /// Cause-oriented: Abacus's brown is in the same warm-tone family as
    /// Claude's brand orange-tan. A naive future palette change that
    /// shifts Abacus closer to Claude would silently regress the visual
    /// distinguishability that's the whole point of T2. Pin the delta.
    @Test("Cause: Abacus brown is visually distinct from Claude orange")
    func abacusDistinctFromClaude() {
        let abacus = UIColor(ProviderColorPalette.color(for: "abacus"))
        let claude = UIColor(ProviderColorPalette.color(for: "claude"))
        // Components in [0,1]; require > 0.10 cumulative L1 delta across RGB
        // (perceptual distinguishability rule of thumb on neutral cards).
        var aR: CGFloat = 0; var aG: CGFloat = 0; var aB: CGFloat = 0; var aA: CGFloat = 0
        var cR: CGFloat = 0; var cG: CGFloat = 0; var cB: CGFloat = 0; var cA: CGFloat = 0
        _ = abacus.getRed(&aR, green: &aG, blue: &aB, alpha: &aA)
        _ = claude.getRed(&cR, green: &cG, blue: &cB, alpha: &cA)
        let delta = abs(aR - cR) + abs(aG - cG) + abs(aB - cB)
        #expect(delta > 0.10, "Abacus and Claude must stay perceptually distinct (Δ=\(delta))")
    }

    /// Cause-oriented: Mistral's brand color is fire-orange (#FF7A00) —
    /// we deliberately shifted to red to avoid clashing with Claude's
    /// orange-tan. If anyone "restores" the brand orange, this test
    /// catches the collision before it ships.
    @Test("Cause: Mistral red is visually distinct from Claude orange")
    func mistralDistinctFromClaude() {
        let mistral = UIColor(ProviderColorPalette.color(for: "mistral"))
        let claude = UIColor(ProviderColorPalette.color(for: "claude"))
        var mR: CGFloat = 0; var mG: CGFloat = 0; var mB: CGFloat = 0; var mA: CGFloat = 0
        var cR: CGFloat = 0; var cG: CGFloat = 0; var cB: CGFloat = 0; var cA: CGFloat = 0
        _ = mistral.getRed(&mR, green: &mG, blue: &mB, alpha: &mA)
        _ = claude.getRed(&cR, green: &cG, blue: &cB, alpha: &cA)
        let delta = abs(mR - cR) + abs(mG - cG) + abs(mB - cB)
        #expect(delta > 0.10, "Mistral and Claude must stay perceptually distinct (Δ=\(delta))")
    }

    /// Cause-oriented: Abacus and Mistral are both "new" so they could
    /// have been picked too close to each other. Pin the delta so a
    /// future palette tuning of one doesn't accidentally walk into the
    /// other.
    @Test("Cause: Abacus and Mistral are distinct from each other")
    func abacusDistinctFromMistral() {
        let abacus = UIColor(ProviderColorPalette.color(for: "abacus"))
        let mistral = UIColor(ProviderColorPalette.color(for: "mistral"))
        var aR: CGFloat = 0; var aG: CGFloat = 0; var aB: CGFloat = 0; var aA: CGFloat = 0
        var mR: CGFloat = 0; var mG: CGFloat = 0; var mB: CGFloat = 0; var mA: CGFloat = 0
        _ = abacus.getRed(&aR, green: &aG, blue: &aB, alpha: &aA)
        _ = mistral.getRed(&mR, green: &mG, blue: &mB, alpha: &mA)
        let delta = abs(aR - mR) + abs(aG - mG) + abs(aB - mB)
        #expect(delta > 0.10, "Abacus and Mistral must stay perceptually distinct (Δ=\(delta))")
    }

    /// Cause-oriented: the palette uses substring `contains` matching.
    /// Mac's provider IDs are kebab-case ASCII (`abacus`, `mistral`),
    /// but a display name like `"Abacus AI"` (with space) is normalized
    /// to `"abacusai"` and must still resolve to brown. Without this
    /// test, a future provider with substring `aba` could silently
    /// inherit Abacus's color.
    @Test("Abacus matches both providerID and displayName (normalization)")
    func abacusNormalization() {
        let byID = UIColor(ProviderColorPalette.color(for: "abacus"))
        let byName = UIColor(ProviderColorPalette.color(for: "Abacus AI"))
        #expect(byID.isApproximately(byName))
    }

    @Test("Mistral matches both providerID and displayName (normalization)")
    func mistralNormalization() {
        let byID = UIColor(ProviderColorPalette.color(for: "mistral"))
        let byName = UIColor(ProviderColorPalette.color(for: "Mistral"))
        #expect(byID.isApproximately(byName))
    }

    /// Cause-oriented: the existing fallback for unknown providers is
    /// `.blue`. Adding new specific entries (Abacus, Mistral) must NOT
    /// shift the unknown fallback. Pin it.
    @Test("Cause: unknown provider unchanged at .blue after Abacus/Mistral additions")
    func unknownStillBlueAfter150() {
        #expect(
            UIColor(ProviderColorPalette.color(for: "future-llm-provider"))
                .isApproximately(UIColor(.blue)))
    }
}

// MARK: - Test helpers

extension UIColor {
    /// Tolerance-based RGBA comparison. Two SwiftUI `Color`s round-trip through
    /// `UIColor` and pick up tiny float drift; a hard `==` would fail.
    fileprivate func isApproximately(_ other: UIColor, tolerance: CGFloat = 0.02) -> Bool {
        var lhsR: CGFloat = 0; var lhsG: CGFloat = 0
        var lhsB: CGFloat = 0; var lhsA: CGFloat = 0
        var rhsR: CGFloat = 0; var rhsG: CGFloat = 0
        var rhsB: CGFloat = 0; var rhsA: CGFloat = 0
        guard
            getRed(&lhsR, green: &lhsG, blue: &lhsB, alpha: &lhsA),
            other.getRed(&rhsR, green: &rhsG, blue: &rhsB, alpha: &rhsA)
        else {
            return false
        }
        return abs(lhsR - rhsR) < tolerance
            && abs(lhsG - rhsG) < tolerance
            && abs(lhsB - rhsB) < tolerance
            && abs(lhsA - rhsA) < tolerance
    }
}
