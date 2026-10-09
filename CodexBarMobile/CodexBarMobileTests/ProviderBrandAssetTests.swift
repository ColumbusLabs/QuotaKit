import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Provider brand assets")
struct ProviderBrandAssetTests {
    @Test
    func `Known providers resolve to provider icon assets`() {
        #expect(ProviderBrandAsset.assetName(for: "codex") == "ProviderIcon-codex")
        #expect(ProviderBrandAsset.assetName(for: "claude") == "ProviderIcon-claude")
        #expect(ProviderBrandAsset.assetName(for: "cursor") == "ProviderIcon-cursor")
        #expect(ProviderBrandAsset.assetName(for: "openrouter") == "ProviderIcon-openrouter")
        #expect(ProviderBrandAsset.assetName(for: "sakana") == "ProviderIcon-sakana")
        #expect(ProviderBrandAsset.assetName(for: "zenmux") == "ProviderIcon-zenmux")
        #expect(ProviderBrandAsset.assetName(for: "clinepass") == "ProviderIcon-clinepass")
        #expect(ProviderBrandAsset.assetName(for: "longcat") == "ProviderIcon-longcat")
        #expect(ProviderBrandAsset.assetName(for: "neuralwatt") == "ProviderIcon-neuralwatt")
        #expect(ProviderBrandAsset.assetName(for: "qwencloud") == "ProviderIcon-qwencloud")
        #expect(ProviderBrandAsset.assetName(for: "zoommate") == "ProviderIcon-zoommate")
        #expect(ProviderBrandAsset.assetName(for: "xai") == "ProviderIcon-xai")
        #expect(ProviderBrandAsset.assetName(for: "notion") == "ProviderIcon-notion")
        #expect(ProviderBrandAsset.assetName(for: "coderabbit") == "ProviderIcon-coderabbit")
        #expect(ProviderBrandAsset.assetName(for: "fireworks") == "ProviderIcon-fireworks")
        #expect(ProviderBrandAsset.assetName(for: "ibmbob") == "ProviderIcon-ibmbob")
        #expect(ProviderBrandAsset.assetName(for: "museai") == "ProviderIcon-museai")
        #expect(ProviderBrandAsset.assetName(for: "gitkraken") == "ProviderIcon-gitkraken")
        #expect(ProviderBrandAsset.assetName(for: "GitKraken AI") == "ProviderIcon-gitkraken")
        #expect(ProviderBrandAsset.assetName(for: "v0") == "ProviderIcon-v0")
        #expect(ProviderBrandAsset.assetName(for: "huggingface") == "ProviderIcon-huggingface")
        #expect(ProviderBrandAsset.assetName(for: "bifrost") == "ProviderIcon-bifrost")
        #expect(ProviderBrandAsset.assetName(for: "devpass") == "ProviderIcon-devpass")
        #expect(ProviderBrandAsset.assetName(for: "hyper") == "ProviderIcon-hyper")
        #expect(ProviderBrandAsset.assetName(for: "aixy") == "ProviderIcon-aixy")
        #expect(ProviderBrandAsset.assetName(for: "xkiro") == "ProviderIcon-xkiro")
        #expect(ProviderBrandAsset.assetName(for: "raycast") == "ProviderIcon-raycast")
        #expect(ProviderBrandAsset.assetName(for: "atlascloud") == "ProviderIcon-atlascloud")
        #expect(ProviderBrandAsset.assetName(for: "vercel") == "ProviderIcon-vercel")
        #expect(ProviderBrandAsset.assetName(for: "llmman") == "ProviderIcon-llmman")
        #expect(ProviderBrandAsset.assetName(for: "lithosai") == "ProviderIcon-lithosai")
        #expect(ProviderBrandAsset.assetName(for: "workbuddy") == "ProviderIcon-workbuddy")
        #expect(ProviderBrandAsset.assetName(for: "tavily") == "ProviderIcon-tavily")
        #expect(ProviderBrandAsset.assetName(for: "linkup") == "ProviderIcon-linkup")
        #expect(ProviderBrandAsset.assetName(for: "tinyapi") == "ProviderIcon-tinyapi")
        #expect(ProviderBrandAsset.assetName(for: "exa") == "ProviderIcon-exa")
        #expect(ProviderBrandAsset.assetName(for: "cosmic") == "ProviderIcon-cosmic")
        #expect(ProviderBrandAsset.assetName(for: "aerostack") == "ProviderIcon-aerostack")
        #expect(ProviderBrandAsset.assetName(for: "sailresearch") == "ProviderIcon-sailresearch")
        #expect(ProviderBrandAsset.assetName(for: "sofya") == "ProviderIcon-sofya")
    }

    @Test
    func `Provider aliases reuse their canonical Mac icons`() {
        #expect(ProviderBrandAsset.assetName(for: "openai") == "ProviderIcon-codex")
        #expect(ProviderBrandAsset.assetName(for: "azureopenai") == "ProviderIcon-codex")
        #expect(ProviderBrandAsset.assetName(for: "moonshot") == "ProviderIcon-kimi")
        #expect(ProviderBrandAsset.assetName(for: "kimik2") == "ProviderIcon-kimi")
        #expect(ProviderBrandAsset.assetName(for: "alibabatokenplan") == "ProviderIcon-alibaba")
    }

    @Test
    func `Every synced quota provider has a brand mark mapping`() {
        for provider in QuotaProviderList.providers {
            #expect(
                ProviderBrandAsset.assetName(for: provider.id) != nil,
                "\(provider.id) should map to a provider brand asset")
        }
    }

    @Test
    func `Pi uses the same official adaptive mark on Mac and iPhone`() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryMarker = "Sources/CodexBar/Resources/ProviderIcon-pi.svg"
        while !FileManager.default.fileExists(atPath: root.appending(path: repositoryMarker).path) {
            let parent = root.deletingLastPathComponent()
            guard parent != root else { throw CocoaError(.fileNoSuchFile) }
            root = parent
        }
        let paths = [
            "Sources/CodexBar/Resources/ProviderIcon-pi.svg",
            "docs/logos/pi.svg",
            "CodexBarMobile/CodexBarMobile/ProviderIcons.xcassets/ProviderIcon-pi.imageset/ProviderIcon-pi.svg",
        ]
        let marks = try paths.map { path in
            try String(contentsOf: root.appending(path: path), encoding: .utf8)
        }
        #expect(marks.dropFirst().allSatisfy { $0 == marks[0] })
        #expect(marks[0].contains("viewBox=\"0 0 560 560\""))
        #expect(marks[0].contains("fill=\"currentColor\""))
        #expect(marks[0].components(separatedBy: "<path").count == 4)
    }

    @Test
    func `Unknown providers use the fallback mark`() {
        #expect(ProviderBrandAsset.assetName(for: "") == nil)
        #expect(ProviderBrandAsset.assetName(for: "brand-new-ai-tool") == nil)
    }
}
