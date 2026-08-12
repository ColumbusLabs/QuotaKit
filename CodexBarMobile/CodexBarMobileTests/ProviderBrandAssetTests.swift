import CodexBarSync
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
        #expect(ProviderBrandAsset.assetName(for: "fireworks") == "ProviderIcon-fireworks")
        #expect(ProviderBrandAsset.assetName(for: "ibmbob") == "ProviderIcon-ibmbob")
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
    func `Unknown providers use the fallback mark`() {
        #expect(ProviderBrandAsset.assetName(for: "") == nil)
        #expect(ProviderBrandAsset.assetName(for: "brand-new-ai-tool") == nil)
    }
}
