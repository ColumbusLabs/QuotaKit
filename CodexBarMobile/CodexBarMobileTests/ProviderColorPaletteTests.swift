import Testing
@testable import CodexBarMobile

@Suite("Provider color palette")
struct ProviderColorPaletteTests {
    @Test
    func `Priority providers use QuotaKit-approved raw colors`() {
        expectColor("codex", red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        expectColor("claude", red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        expectColor("anthropic", red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        expectColor("cursor", red: 245 / 255, green: 78 / 255, blue: 0)
        expectColor("replicate", red: 160 / 255, green: 160 / 255, blue: 160 / 255)
    }

    @Test
    func `Palette mirrors Mac descriptor colors for known providers`() {
        let expected: [(String, Double, Double, Double)] = [
            ("openai", 0.06, 0.51, 0.43),
            ("azureopenai", 0, 120 / 255, 212 / 255),
            ("cursor", 245 / 255, 78 / 255, 0),
            ("opencode", 14 / 255, 165 / 255, 233 / 255),
            ("opencodego", 52 / 255, 211 / 255, 153 / 255),
            ("alibaba", 1, 106 / 255, 0),
            ("alibabatokenplan", 1, 176 / 255, 32 / 255),
            ("qwencloud", 147 / 255, 51 / 255, 234 / 255),
            ("factory", 255 / 255, 107 / 255, 53 / 255),
            ("gemini", 171 / 255, 135 / 255, 234 / 255),
            ("gitkraken", 23 / 255, 146 / 255, 135 / 255),
            ("bifrost", 51 / 255, 192 / 255, 158 / 255),
            ("devpass", 37 / 255, 99 / 255, 235 / 255),
            ("antigravity", 96 / 255, 186 / 255, 126 / 255),
            ("copilot", 168 / 255, 85 / 255, 247 / 255),
            ("zai", 232 / 255, 90 / 255, 106 / 255),
            ("minimax", 239 / 255, 68 / 255, 68 / 255),
            ("manus", 52 / 255, 50 / 255, 45 / 255),
            ("kimi", 244 / 255, 63 / 255, 94 / 255),
            ("kimik2", 76 / 255, 0, 255 / 255),
            ("kilo", 242 / 255, 112 / 255, 39 / 255),
            ("kiro", 144 / 255, 70 / 255, 255 / 255),
            ("vertexai", 66 / 255, 133 / 255, 244 / 255),
            ("augment", 26 / 255, 160 / 255, 73 / 255),
            ("jetbrains", 255 / 255, 51 / 255, 153 / 255),
            ("moonshot", 32 / 255, 93 / 255, 235 / 255),
            ("notion", 51 / 255, 126 / 255, 169 / 255),
            ("amp", 243 / 255, 78 / 255, 63 / 255),
            ("t3chat", 245 / 255, 102 / 255, 71 / 255),
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
            ("abacus", 129 / 255, 78 / 255, 232 / 255),
            ("mistral", 255 / 255, 82 / 255, 41 / 255),
            ("deepseek", 77 / 255, 107 / 255, 254 / 255),
            ("deepinfra", 42 / 255, 50 / 255, 117 / 255),
            ("sub2api", 20 / 255, 184 / 255, 166 / 255),
            ("devin", 49 / 255, 124 / 255, 255 / 255),
            ("codebuff", 0, 255 / 255, 149 / 255),
            ("coderabbit", 200 / 255, 60 / 255, 40 / 255),
            ("crof", 0.18, 0.67, 0.58),
            ("venice", 60 / 255, 143 / 255, 221 / 255),
            ("commandcode", 140 / 255, 78 / 255, 221 / 255),
            ("qoder", 16 / 255, 185 / 255, 129 / 255),
            ("stepfun", 0.13, 0.59, 0.95),
            ("crossmodel", 150 / 255, 65 / 255, 200 / 255),
            ("bedrock", 1 / 255, 168 / 255, 141 / 255),
            ("grok", 26 / 255, 26 / 255, 26 / 255),
            ("groq", 245 / 255, 104 / 255, 68 / 255),
            ("llmproxy", 36 / 255, 180 / 255, 126 / 255),
            ("litellm", 76 / 255, 137 / 255, 192 / 255),
            ("lithosai", 107 / 255, 114 / 255, 128 / 255),
            ("workbuddy", 13 / 255, 210 / 255, 166 / 255),
            ("langdock", 90 / 255, 74 / 255, 231 / 255),
            ("deepgram", 0.49, 0.23, 0.93),
            ("hyper", 1, 96 / 255, 1),
            ("aixy", 18 / 255, 54 / 255, 80 / 255),
            ("xkiro", 82 / 255, 201 / 255, 155 / 255),
            ("raycast", 1, 99 / 255, 99 / 255),
            ("aiand", 226 / 255, 92 / 255, 43 / 255),
            ("zenmux", 90 / 255, 40 / 255, 190 / 255),
            ("clinepass", 84 / 255, 135 / 255, 200 / 255),
            ("longcat", 41 / 255, 225 / 255, 84 / 255),
            ("neuralwatt", 213 / 255, 89 / 255, 52 / 255),
            ("devin", 49 / 255, 124 / 255, 255 / 255),
            ("sub2api", 20 / 255, 184 / 255, 166 / 255),
            ("zoommate", 64 / 255, 176 / 255, 255 / 255),
            ("v0", 17 / 255, 17 / 255, 17 / 255),
            ("xai", 142 / 255, 142 / 255, 160 / 255),
            ("nous", 214 / 255, 165 / 255, 92 / 255),
            ("muse", 6 / 255, 104 / 255, 225 / 255),
            ("museai", 6 / 255, 104 / 255, 225 / 255),
            ("pi", 124 / 255, 58 / 255, 237 / 255),
            ("huggingface", 1, 210 / 255, 30 / 255),
            ("replicate", 160 / 255, 160 / 255, 160 / 255),
        ]

        for (provider, red, green, blue) in expected {
            expectColor(provider, red: red, green: green, blue: blue)
        }
    }

    @Test
    func `Widgets retain prior colors for refreshed app accents`() {
        let expected: [(String, ProviderColorPalette.RawColor)] = [
            ("abacus", .init(red: 56 / 255, green: 189 / 255, blue: 248 / 255)),
            ("amp", .init(red: 220 / 255, green: 38 / 255, blue: 38 / 255)),
            ("augment", .init(red: 139 / 255, green: 92 / 255, blue: 246 / 255)),
            ("bedrock", .init(red: 1, green: 0.6, blue: 0)),
            ("clinepass", .init(red: 0.38, green: 0.64, blue: 0.98)),
            ("codebuff", .init(red: 68 / 255, green: 255 / 255, blue: 0)),
            ("commandcode", .init(red: 71 / 255, green: 85 / 255, blue: 105 / 255)),
            ("cursor", .init(red: 0, green: 0, blue: 0)),
            ("deepseek", .init(red: 0.32, green: 0.49, blue: 0.94)),
            ("devin", .init(red: 70 / 255, green: 180 / 255, blue: 130 / 255)),
            ("kiro", .init(red: 217 / 255, green: 119 / 255, blue: 6 / 255)),
            ("longcat", .init(red: 1, green: 209 / 255, blue: 0)),
            ("mistral", .init(red: 255 / 255, green: 80 / 255, blue: 15 / 255)),
            ("neuralwatt", .init(red: 0.12, green: 0.72, blue: 0.38)),
            ("sub2api", .init(red: 45 / 255, green: 198 / 255, blue: 216 / 255)),
            ("venice", .init(red: 0.2, green: 0.6, blue: 1)),
        ]

        for (provider, oldWidgetColor) in expected {
            let widgetColor = ProviderColorPalette.widgetRawColor(for: provider)
            #expect(widgetColor == oldWidgetColor, "\(provider) widget raw color changed")
            #expect(
                widgetColor?.adaptedComponents(forDarkMode: false) ==
                    oldWidgetColor.adaptedComponents(forDarkMode: false),
                "\(provider) light-mode widget color changed")
            #expect(
                widgetColor?.adaptedComponents(forDarkMode: true) ==
                    oldWidgetColor.adaptedComponents(forDarkMode: true),
                "\(provider) dark-mode widget color changed")
        }

        #expect(ProviderColorPalette.widgetRawColor(for: "ampcode") == ProviderColorPalette.widgetRawColor(for: "amp"))
        #expect(ProviderColorPalette.widgetRawColor(for: "kimi") == ProviderColorPalette.rawColor(for: "kimi"))
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
            ("Qwen Cloud", "qwencloud"),
            ("ZoomMate", "zoommate"),
            ("xAI", "xai"),
            ("GitKraken AI", "gitkraken"),
            ("Hugging Face", "huggingface"),
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
    "alibaba", "alibabatokenplan", "qwencloud", "factory", "gemini", "gitkraken", "antigravity", "copilot",
    "zai", "minimax", "manus", "kimi", "kilo", "kiro", "vertexai", "augment", "neuralwatt",
    "jetbrains", "kimik2", "moonshot", "amp", "t3chat", "ollama", "synthetic",
    "warp", "openrouter", "elevenlabs", "windsurf", "perplexity", "mimo",
    "doubao", "sakana", "abacus", "mistral", "deepseek", "codebuff", "crof", "venice",
    "commandcode", "qoder", "stepfun", "bedrock", "grok", "groq", "llmproxy", "litellm", "lithosai", "deepgram",
    "crossmodel", "clinepass", "longcat", "deepinfra", "aiand",
    "zenmux", "zoommate", "xai", "replicate", "hyper", "bifrost", "devpass", "workbuddy",
]

/// These pairs retain their providers' published brand colors. The mobile palette mirrors
/// the Mac descriptors; a small channel distance here is intentional, not an alias collision.
private let closeBrandColorMinimumDistances: [Set<String>: Double] = [
    ["opencodego", "bifrost"]: 0.04,
    ["moonshot", "devpass"]: 0.04,
    ["manus", "synthetic"]: 0.04,
    ["t3chat", "groq"]: 0.015,
    ["neuralwatt", "aiand"]: 0.05,
    ["minimax", "amp"]: 0.07,
    ["abacus", "commandcode"]: 0.08,
    ["litellm", "clinepass"]: 0.065,
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
            let minimumDistance = closeBrandColorMinimumDistances[[left, right]] ?? 0.10
            #expect(delta > minimumDistance, "\(left) and \(right) must stay visually distinct (delta: \(delta))")
        }
    }
}
