import Testing
@testable import CodexBarMobile

@Suite("Provider color palette")
struct ProviderColorPaletteTests {
    @Test
    func `Priority providers use QuotaKit-approved raw colors`() {
        expectColor("codex", red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        expectColor("claude", red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        expectColor("anthropic", red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        expectColor("cursor", red: 0, green: 0, blue: 0)
    }

    @Test
    func `Palette mirrors Mac descriptor colors for known providers`() {
        let expected: [(String, Double, Double, Double)] = [
            ("openai", 0.06, 0.51, 0.43),
            ("azureopenai", 0, 120 / 255, 212 / 255),
            ("opencode", 14 / 255, 165 / 255, 233 / 255),
            ("opencodego", 52 / 255, 211 / 255, 153 / 255),
            ("alibaba", 1, 106 / 255, 0),
            ("alibabatokenplan", 1, 176 / 255, 32 / 255),
            ("factory", 255 / 255, 107 / 255, 53 / 255),
            ("gemini", 171 / 255, 135 / 255, 234 / 255),
            ("antigravity", 96 / 255, 186 / 255, 126 / 255),
            ("copilot", 168 / 255, 85 / 255, 247 / 255),
            ("zai", 232 / 255, 90 / 255, 106 / 255),
            ("minimax", 239 / 255, 68 / 255, 68 / 255),
            ("manus", 63 / 255, 58 / 255, 50 / 255),
            ("kimi", 244 / 255, 63 / 255, 94 / 255),
            ("kimik2", 76 / 255, 0, 255 / 255),
            ("kilo", 242 / 255, 112 / 255, 39 / 255),
            ("kiro", 217 / 255, 119 / 255, 6 / 255),
            ("vertexai", 66 / 255, 133 / 255, 244 / 255),
            ("augment", 139 / 255, 92 / 255, 246 / 255),
            ("jetbrains", 255 / 255, 51 / 255, 153 / 255),
            ("moonshot", 32 / 255, 93 / 255, 235 / 255),
            ("amp", 220 / 255, 38 / 255, 38 / 255),
            ("t3chat", 219 / 255, 39 / 255, 119 / 255),
            ("ollama", 136 / 255, 136 / 255, 136 / 255),
            ("synthetic", 42 / 255, 42 / 255, 42 / 255),
            ("warp", 147 / 255, 139 / 255, 180 / 255),
            ("openrouter", 100 / 255, 103 / 255, 242 / 255),
            ("elevenlabs", 0.92, 0.92, 0.90),
            ("windsurf", 52 / 255, 232 / 255, 187 / 255),
            ("perplexity", 32 / 255, 178 / 255, 170 / 255),
            ("mimo", 249 / 255, 115 / 255, 22 / 255),
            ("doubao", 51 / 255, 112 / 255, 255 / 255),
            ("sakana", 0.16, 0.46, 0.86),
            ("abacus", 56 / 255, 189 / 255, 248 / 255),
            ("mistral", 255 / 255, 80 / 255, 15 / 255),
            ("deepseek", 0.32, 0.49, 0.94),
            ("codebuff", 68 / 255, 255 / 255, 0),
            ("crof", 0.18, 0.67, 0.58),
            ("venice", 0.2, 0.6, 1),
            ("commandcode", 71 / 255, 85 / 255, 105 / 255),
            ("qoder", 16 / 255, 185 / 255, 129 / 255),
            ("stepfun", 0.13, 0.59, 0.95),
            ("crossmodel", 150 / 255, 65 / 255, 200 / 255),
            ("bedrock", 1, 0.6, 0),
            ("grok", 26 / 255, 26 / 255, 26 / 255),
            ("groq", 245 / 255, 104 / 255, 68 / 255),
            ("llmproxy", 36 / 255, 180 / 255, 126 / 255),
            ("litellm", 76 / 255, 137 / 255, 192 / 255),
            ("deepgram", 0.49, 0.23, 0.93),
            ("zenmux", 90 / 255, 40 / 255, 190 / 255),
        ]

        for (provider, red, green, blue) in expected {
            expectColor(provider, red: red, green: green, blue: blue)
        }
    }

    @Test
    func `Display names normalize to provider IDs`() {
        let pairs = [
            ("OpenCode Go", "opencodego"),
            ("Command Code", "commandcode"),
            ("Abacus AI", "abacus"),
            ("Moonshot / Kimi API", "moonshot"),
            ("Azure OpenAI", "azureopenai"),
            ("Alibaba Token Plan", "alibabatokenplan"),
            ("Xiaomi MiMo", "mimo"),
            ("GroqCloud", "groq"),
            ("Sakana AI", "sakana"),
            ("Qoder", "qoder"),
        ]

        for (displayName, providerID) in pairs {
            #expect(
                ProviderColorPalette.rawColor(for: displayName) == ProviderColorPalette.rawColor(for: providerID),
                "\(displayName) should match \(providerID)")
        }
    }

    @Test
    func `Substring matches do not steal unrelated provider names`() {
        #expect(ProviderColorPalette.rawColor(for: "example-provider") == nil)
        #expect(ProviderColorPalette.rawColor(for: "lamp") == nil)
        #expect(ProviderColorPalette.rawColor(for: "opencodegoose") == nil)
        #expect(ProviderColorPalette.rawColor(for: "chatgpt") == ProviderColorPalette.rawColor(for: "openai"))
    }

    @Test
    func `Known provider colors stay visually distinct`() {
        expectDistinctColors(
            providers: knownDistinctProviders,
            color: { ProviderColorPalette.rawColor(for: $0)! })
    }

    @Test
    func `Dark-mode adapted provider colors stay visually distinct`() {
        expectDistinctColors(
            providers: knownDistinctProviders,
            color: { ProviderColorPalette.rawColor(for: $0)!.adaptedComponents(forDarkMode: true) })
    }

    @Test
    func `Unknown and empty provider IDs still fall back at render time`() {
        #expect(ProviderColorPalette.rawColor(for: "") == nil)
        #expect(ProviderColorPalette.rawColor(for: "brand-new-ai-tool") == nil)
    }
}

private func expectColor(_ provider: String, red: Double, green: Double, blue: Double) {
    let color = ProviderColorPalette.rawColor(for: provider)
    #expect(color != nil, "\(provider) should have a raw palette entry")
    #expect(abs((color?.red ?? -1) - red) < 0.001, "\(provider) red channel did not match")
    #expect(abs((color?.green ?? -1) - green) < 0.001, "\(provider) green channel did not match")
    #expect(abs((color?.blue ?? -1) - blue) < 0.001, "\(provider) blue channel did not match")
}

private let knownDistinctProviders = [
    "codex", "openai", "azureopenai", "claude", "cursor", "opencode", "opencodego",
    "alibaba", "alibabatokenplan", "factory", "gemini", "antigravity", "copilot",
    "zai", "minimax", "manus", "kimi", "kilo", "kiro", "vertexai", "augment",
    "jetbrains", "kimik2", "moonshot", "amp", "t3chat", "ollama", "synthetic",
    "warp", "openrouter", "elevenlabs", "windsurf", "perplexity", "mimo",
    "doubao", "sakana", "abacus", "mistral", "deepseek", "codebuff", "crof", "venice",
    "commandcode", "qoder", "stepfun", "bedrock", "grok", "groq", "llmproxy", "litellm", "deepgram",
    "crossmodel",
    "zenmux",
]

private func expectDistinctColors(
    providers: [String],
    color: (String) -> ProviderColorPalette.RawColor)
{
    for leftIndex in providers.indices {
        for rightIndex in providers.index(after: leftIndex)..<providers.endIndex {
            let left = providers[leftIndex]
            let right = providers[rightIndex]
            let leftColor = color(left)
            let rightColor = color(right)
            let delta = abs(leftColor.red - rightColor.red)
                + abs(leftColor.green - rightColor.green)
                + abs(leftColor.blue - rightColor.blue)
            #expect(delta > 0.10, "\(left) and \(right) must stay visually distinct (delta: \(delta))")
        }
    }
}
