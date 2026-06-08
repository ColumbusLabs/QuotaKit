import SwiftUI
import Testing

@testable import CodexBarMobile

@Suite("Provider color palette")
struct ProviderColorPaletteTests {
    @Test("Priority providers use QuotaKit-approved brand colors")
    func priorityProviderColors() {
        expectColor("codex", red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        expectColor("claude", red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        expectColor("anthropic", red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        expectColor("cursor", red: 0, green: 0, blue: 0)
    }

    @Test("Codex and Cursor no longer collide")
    func codexAndCursorAreDistinct() {
        let codex = UIColor(ProviderColorPalette.color(for: "codex"))
        let cursor = UIColor(ProviderColorPalette.color(for: "cursor"))
        #expect(!codex.isApproximately(cursor))
        #expect(!codex.isApproximately(UIColor(.purple)))
        #expect(!cursor.isApproximately(UIColor(.purple)))
    }

    @Test("Palette mirrors Mac descriptor colors for known providers")
    func knownProviderColors() {
        let expected: [(String, CGFloat, CGFloat, CGFloat)] = [
            ("openai", 0.06, 0.51, 0.43),
            ("azureopenai", 0, 120 / 255, 212 / 255),
            ("opencode", 59 / 255, 130 / 255, 246 / 255),
            ("opencodego", 59 / 255, 130 / 255, 246 / 255),
            ("alibaba", 1.0, 106 / 255, 0),
            ("alibabatokenplan", 1.0, 106 / 255, 0),
            ("factory", 255 / 255, 107 / 255, 53 / 255),
            ("gemini", 171 / 255, 135 / 255, 234 / 255),
            ("antigravity", 96 / 255, 186 / 255, 126 / 255),
            ("copilot", 168 / 255, 85 / 255, 247 / 255),
            ("zai", 232 / 255, 90 / 255, 106 / 255),
            ("minimax", 254 / 255, 96 / 255, 60 / 255),
            ("manus", 52 / 255, 50 / 255, 45 / 255),
            ("kimi", 254 / 255, 96 / 255, 60 / 255),
            ("kimik2", 76 / 255, 0, 255 / 255),
            ("kilo", 242 / 255, 112 / 255, 39 / 255),
            ("kiro", 255 / 255, 153 / 255, 0),
            ("vertexai", 66 / 255, 133 / 255, 244 / 255),
            ("augment", 99 / 255, 102 / 255, 241 / 255),
            ("jetbrains", 255 / 255, 51 / 255, 153 / 255),
            ("moonshot", 32 / 255, 93 / 255, 235 / 255),
            ("amp", 220 / 255, 38 / 255, 38 / 255),
            ("t3chat", 245 / 255, 102 / 255, 71 / 255),
            ("ollama", 136 / 255, 136 / 255, 136 / 255),
            ("synthetic", 20 / 255, 20 / 255, 20 / 255),
            ("warp", 147 / 255, 139 / 255, 180 / 255),
            ("openrouter", 100 / 255, 103 / 255, 242 / 255),
            ("elevenlabs", 0.92, 0.92, 0.90),
            ("windsurf", 52 / 255, 232 / 255, 187 / 255),
            ("perplexity", 32 / 255, 178 / 255, 170 / 255),
            ("mimo", 1.0, 105 / 255, 0),
            ("doubao", 51 / 255, 112 / 255, 255 / 255),
            ("abacus", 56 / 255, 189 / 255, 248 / 255),
            ("mistral", 255 / 255, 80 / 255, 15 / 255),
            ("deepseek", 0.32, 0.49, 0.94),
            ("codebuff", 68 / 255, 255 / 255, 0),
            ("crof", 0.18, 0.67, 0.58),
            ("venice", 0.2, 0.6, 1.0),
            ("commandcode", 0, 0, 0),
            ("stepfun", 0.13, 0.59, 0.95),
            ("bedrock", 1.0, 0.6, 0),
            ("grok", 16 / 255, 163 / 255, 127 / 255),
            ("groq", 245 / 255, 104 / 255, 68 / 255),
            ("llmproxy", 36 / 255, 180 / 255, 126 / 255),
            ("deepgram", 0.49, 0.23, 0.93),
        ]

        for (provider, red, green, blue) in expected {
            expectColor(provider, red: red, green: green, blue: blue)
        }
    }

    @Test("Display names normalize to provider IDs")
    func displayNameMatchesID() {
        let pairs = [
            ("OpenCode Go", "opencodego"),
            ("Command Code", "commandcode"),
            ("Abacus AI", "abacus"),
            ("Moonshot / Kimi API", "moonshot"),
            ("Azure OpenAI", "azureopenai"),
            ("Alibaba Token Plan", "alibabatokenplan"),
        ]

        for (displayName, providerID) in pairs {
            let byName = UIColor(ProviderColorPalette.color(for: displayName))
            let byID = UIColor(ProviderColorPalette.color(for: providerID))
            #expect(byName.isApproximately(byID), "\(displayName) should match \(providerID)")
        }
    }

    @Test("Unknown and empty provider IDs still fall back to blue")
    func unknownFallsToBlue() {
        #expect(UIColor(ProviderColorPalette.color(for: "")).isApproximately(UIColor(.blue)))
        #expect(UIColor(ProviderColorPalette.color(for: "brand-new-ai-tool")).isApproximately(UIColor(.blue)))
    }
}

private func expectColor(_ provider: String, red: CGFloat, green: CGFloat, blue: CGFloat) {
    let color = UIColor(ProviderColorPalette.color(for: provider))
    let expected = UIColor(red: red, green: green, blue: blue, alpha: 1)
    #expect(color.isApproximately(expected), "\(provider) color did not match expected swatch")
}

extension UIColor {
    fileprivate func isApproximately(_ other: UIColor, tolerance: CGFloat = 0.02) -> Bool {
        var lhsR: CGFloat = 0
        var lhsG: CGFloat = 0
        var lhsB: CGFloat = 0
        var lhsA: CGFloat = 0
        var rhsR: CGFloat = 0
        var rhsG: CGFloat = 0
        var rhsB: CGFloat = 0
        var rhsA: CGFloat = 0
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
