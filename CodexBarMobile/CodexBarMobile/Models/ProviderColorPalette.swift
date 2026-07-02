import SwiftUI

/// Single source of truth for provider-card tint colors.
///
/// The raw swatches mirror the Mac `ProviderDescriptorRegistry` branding
/// colors. `color(for:)` returns an appearance-adaptive tint so very dark or
/// very light brand colors stay visible on iOS surfaces.
enum ProviderColorPalette {
    struct RawColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(uiColor: UIColor { traits in
                let adapted = self.adaptedComponents(forDarkMode: traits.userInterfaceStyle == .dark)
                return UIColor(
                    red: adapted.red,
                    green: adapted.green,
                    blue: adapted.blue,
                    alpha: 1)
            })
        }

        private var luminance: Double {
            0.2126 * self.red + 0.7152 * self.green + 0.0722 * self.blue
        }

        func adaptedComponents(forDarkMode isDarkMode: Bool) -> RawColor {
            if isDarkMode {
                if self.luminance < 0.08 {
                    return self.mixed(with: RawColor(red: 1, green: 1, blue: 1), amount: 0.40)
                }
                if self.luminance < 0.14 {
                    return self.mixed(with: RawColor(red: 1, green: 1, blue: 1), amount: 0.44)
                }
                if self.luminance < 0.22 {
                    return self.mixed(with: RawColor(red: 1, green: 1, blue: 1), amount: 0.21)
                }
            }
            if !isDarkMode, self.luminance > 0.82 {
                return self.mixed(with: RawColor(red: 0, green: 0, blue: 0), amount: 0.42)
            }
            return self
        }

        private func mixed(with other: RawColor, amount: Double) -> RawColor {
            RawColor(
                red: self.red + (other.red - self.red) * amount,
                green: self.green + (other.green - self.green) * amount,
                blue: self.blue + (other.blue - self.blue) * amount)
        }
    }

    static func color(for providerIdentifier: String) -> Color {
        (self.rawColor(for: providerIdentifier) ?? self.fallback).color
    }

    static func rawColor(for providerIdentifier: String) -> RawColor? {
        self.palette[self.normalized(providerIdentifier)]
    }

    static func normalized(_ value: String) -> String {
        String(value
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static let fallback = RawColor(red: 0, green: 122 / 255, blue: 1)

    private static let palette: [String: RawColor] = {
        let entries: [(aliases: [String], color: RawColor)] = [
            (["codex"], RawColor(red: 73 / 255, green: 163 / 255, blue: 176 / 255)),
            (["openai", "chatgpt"], RawColor(red: 0.06, green: 0.51, blue: 0.43)),
            (["azureopenai"], RawColor(red: 0, green: 120 / 255, blue: 212 / 255)),
            (["claude", "anthropic"], RawColor(red: 204 / 255, green: 124 / 255, blue: 94 / 255)),
            (["cursor"], RawColor(red: 0, green: 0, blue: 0)),
            (["opencode"], RawColor(red: 14 / 255, green: 165 / 255, blue: 233 / 255)),
            (["opencodego"], RawColor(red: 52 / 255, green: 211 / 255, blue: 153 / 255)),
            (["alibaba", "bailian"], RawColor(red: 1, green: 106 / 255, blue: 0)),
            (
                ["alibabatokenplan", "alibabatoken", "bailiantokenplan"],
                RawColor(red: 1, green: 176 / 255, blue: 32 / 255)),
            (["factory", "droid"], RawColor(red: 255 / 255, green: 107 / 255, blue: 53 / 255)),
            (["gemini"], RawColor(red: 171 / 255, green: 135 / 255, blue: 234 / 255)),
            (["antigravity"], RawColor(red: 96 / 255, green: 186 / 255, blue: 126 / 255)),
            (["zed"], RawColor(red: 8 / 255, green: 78 / 255, blue: 255 / 255)),
            (["poe"], RawColor(red: 0.15, green: 0.68, blue: 0.38)),
            (["chutes"], RawColor(red: 0, green: 184 / 255, blue: 255 / 255)),
            (["qoder"], RawColor(red: 16 / 255, green: 185 / 255, blue: 129 / 255)),
            (["copilot"], RawColor(red: 168 / 255, green: 85 / 255, blue: 247 / 255)),
            (["zai"], RawColor(red: 232 / 255, green: 90 / 255, blue: 106 / 255)),
            (["minimax"], RawColor(red: 239 / 255, green: 68 / 255, blue: 68 / 255)),
            (["manus"], RawColor(red: 63 / 255, green: 58 / 255, blue: 50 / 255)),
            (["kimi"], RawColor(red: 244 / 255, green: 63 / 255, blue: 94 / 255)),
            (["kilo"], RawColor(red: 242 / 255, green: 112 / 255, blue: 39 / 255)),
            (["kiro"], RawColor(red: 217 / 255, green: 119 / 255, blue: 6 / 255)),
            (["vertexai", "vertex"], RawColor(red: 66 / 255, green: 133 / 255, blue: 244 / 255)),
            (["augment"], RawColor(red: 139 / 255, green: 92 / 255, blue: 246 / 255)),
            (["jetbrains"], RawColor(red: 255 / 255, green: 51 / 255, blue: 153 / 255)),
            (["kimik2", "kimik2unofficial"], RawColor(red: 76 / 255, green: 0, blue: 255 / 255)),
            (["moonshot", "moonshotkimiapi", "kimiapi"], RawColor(red: 32 / 255, green: 93 / 255, blue: 235 / 255)),
            (["amp", "ampcode"], RawColor(red: 220 / 255, green: 38 / 255, blue: 38 / 255)),
            (["t3chat", "t3"], RawColor(red: 219 / 255, green: 39 / 255, blue: 119 / 255)),
            (["ollama"], RawColor(red: 136 / 255, green: 136 / 255, blue: 136 / 255)),
            (["synthetic", "syntheticnew"], RawColor(red: 42 / 255, green: 42 / 255, blue: 42 / 255)),
            (["warp"], RawColor(red: 147 / 255, green: 139 / 255, blue: 180 / 255)),
            (["openrouter"], RawColor(red: 100 / 255, green: 103 / 255, blue: 242 / 255)),
            (["elevenlabs", "11labs", "eleven"], RawColor(red: 0.92, green: 0.92, blue: 0.90)),
            (["windsurf"], RawColor(red: 52 / 255, green: 232 / 255, blue: 187 / 255)),
            (["perplexity"], RawColor(red: 32 / 255, green: 178 / 255, blue: 170 / 255)),
            (["mimo", "xiaomimimo"], RawColor(red: 249 / 255, green: 115 / 255, blue: 22 / 255)),
            (["doubao"], RawColor(red: 51 / 255, green: 112 / 255, blue: 255 / 255)),
            (["sakana", "sakanaai"], RawColor(red: 0.16, green: 0.46, blue: 0.86)),
            (["abacus", "abacusai"], RawColor(red: 56 / 255, green: 189 / 255, blue: 248 / 255)),
            (["mistral"], RawColor(red: 255 / 255, green: 80 / 255, blue: 15 / 255)),
            (["deepseek"], RawColor(red: 0.32, green: 0.49, blue: 0.94)),
            (["codebuff"], RawColor(red: 68 / 255, green: 255 / 255, blue: 0)),
            (["crof"], RawColor(red: 0.18, green: 0.67, blue: 0.58)),
            (["venice"], RawColor(red: 0.2, green: 0.6, blue: 1)),
            (["commandcode"], RawColor(red: 71 / 255, green: 85 / 255, blue: 105 / 255)),
            (["stepfun"], RawColor(red: 0.13, green: 0.59, blue: 0.95)),
            (["crossmodel"], RawColor(red: 88 / 255, green: 86 / 255, blue: 214 / 255)),
            (["bedrock"], RawColor(red: 1, green: 0.6, blue: 0)),
            (["grok"], RawColor(red: 26 / 255, green: 26 / 255, blue: 26 / 255)),
            (["groq", "groqcloud", "groqapi"], RawColor(red: 245 / 255, green: 104 / 255, blue: 68 / 255)),
            (["llmproxy"], RawColor(red: 36 / 255, green: 180 / 255, blue: 126 / 255)),
            (["litellm"], RawColor(red: 76 / 255, green: 137 / 255, blue: 192 / 255)),
            (["deepgram"], RawColor(red: 0.49, green: 0.23, blue: 0.93)),
            (["devin"], RawColor(red: 70 / 255, green: 180 / 255, blue: 130 / 255)),
        ]

        var table: [String: RawColor] = [:]
        for entry in entries {
            for alias in entry.aliases {
                table[Self.normalized(alias)] = entry.color
            }
        }
        return table
    }()
}
