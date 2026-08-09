import CodexBarSync
import Testing
@testable import CodexBarMobile

@Suite("Provider brand assets")
struct ProviderBrandAssetTests {
    @Test
    func `Supported providers resolve to provider icon assets`() {
        #expect(ProviderBrandAsset.assetName(for: "codex") == "ProviderIcon-codex")
        #expect(ProviderBrandAsset.assetName(for: "claude") == "ProviderIcon-claude")
        #expect(ProviderBrandAsset.assetName(for: "cursor") == "ProviderIcon-cursor")
        #expect(ProviderBrandAsset.assetName(for: "grok") == "ProviderIcon-grok")
    }

    @Test
    func `Every synced quota provider has a brand mark mapping`() {
        for provider in QuotaProviderList.providers {
            #expect(ProviderBrandAsset.assetName(for: provider.id) != nil)
        }
    }

    @Test
    func `Retired and unknown providers use the fallback mark`() {
        #expect(ProviderBrandAsset.assetName(for: "gemini") == nil)
        #expect(ProviderBrandAsset.assetName(for: "perplexity") == nil)
        #expect(ProviderBrandAsset.assetName(for: "") == nil)
        #expect(ProviderBrandAsset.assetName(for: "brand-new-ai-tool") == nil)
    }
}
