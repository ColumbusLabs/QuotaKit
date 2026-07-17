import SwiftUI
import UIKit

enum ProviderBrandAsset {
    private static let assetPrefix = "ProviderIcon-"

    private static let canonicalIconIDs: Set<String> = [
        "abacus",
        "alibaba",
        "amp",
        "antigravity",
        "augment",
        "bedrock",
        "chutes",
        "clinepass",
        "claude",
        "codebuff",
        "codex",
        "commandcode",
        "copilot",
        "crof",
        "cursor",
        "deepgram",
        "deepseek",
        "devin",
        "doubao",
        "elevenlabs",
        "factory",
        "gemini",
        "grok",
        "groq",
        "jetbrains",
        "kilo",
        "kimi",
        "kiro",
        "litellm",
        "llmproxy",
        "longcat",
        "manus",
        "mimo",
        "minimax",
        "mistral",
        "neuralwatt",
        "ollama",
        "opencode",
        "opencodego",
        "openrouter",
        "perplexity",
        "poe",
        "qoder",
        "sakana",
        "stepfun",
        "sub2api",
        "synthetic",
        "t3chat",
        "venice",
        "vertexai",
        "warp",
        "windsurf",
        "zai",
        "zed",
        "zenmux",
    ]

    private static let aliases: [String: String] = [
        "11labs": "elevenlabs",
        "abacusai": "abacus",
        "alibabatoken": "alibaba",
        "alibabatokenplan": "alibaba",
        "ampcode": "amp",
        "anthropic": "claude",
        "azureopenai": "codex",
        "bailian": "alibaba",
        "bailiantokenplan": "alibaba",
        "chatgpt": "codex",
        "droid": "factory",
        "eleven": "elevenlabs",
        "groqapi": "groq",
        "groqcloud": "groq",
        "kimiapi": "kimi",
        "kimik2": "kimi",
        "kimik2unofficial": "kimi",
        "moonshot": "kimi",
        "moonshotkimiapi": "kimi",
        "openai": "codex",
        "openaiapi": "codex",
        "t3": "t3chat",
        "vertex": "vertexai",
        "xiaomimimo": "mimo",
    ]

    static func assetName(for providerIdentifier: String) -> String? {
        let normalized = ProviderColorPalette.normalized(providerIdentifier)
        guard !normalized.isEmpty else { return nil }

        if self.canonicalIconIDs.contains(normalized) {
            return "\(self.assetPrefix)\(normalized)"
        }

        guard let canonical = self.aliases[normalized] else { return nil }
        return "\(self.assetPrefix)\(canonical)"
    }

    static func image(for providerIdentifier: String, in bundle: Bundle = .main) -> UIImage? {
        guard let assetName = self.assetName(for: providerIdentifier) else { return nil }
        return UIImage(named: assetName, in: bundle, compatibleWith: nil)
    }
}

struct ProviderBrandMark: View {
    let providerID: String
    var size: CGFloat = 18
    var tint: Color?
    var accessibilityLabel: String?

    var body: some View {
        self.mark
            .frame(width: self.size, height: self.size)
            .accessibilityHidden(self.accessibilityLabel == nil)
            .accessibilityLabel(Text(self.accessibilityLabel ?? ""))
    }

    @ViewBuilder
    private var mark: some View {
        let color = self.tint ?? ProviderColorPalette.color(for: self.providerID)
        if let image = ProviderBrandAsset.image(for: self.providerID) {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(color)
        } else {
            Image(systemName: "circle.dotted")
                .font(.system(size: self.size, weight: .regular))
                .foregroundStyle(color)
        }
    }
}
