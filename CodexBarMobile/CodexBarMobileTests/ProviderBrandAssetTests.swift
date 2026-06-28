import CodexBarSync
import Testing
@testable import CodexBarMobile

@Suite("Provider brand assets")
struct ProviderBrandAssetTests {
    @Test("Known providers resolve to provider icon assets")
    func knownProvidersResolveToAssets() {
        #expect(ProviderBrandAsset.assetName(for: "codex") == "ProviderIcon-codex")
        #expect(ProviderBrandAsset.assetName(for: "claude") == "ProviderIcon-claude")
        #expect(ProviderBrandAsset.assetName(for: "cursor") == "ProviderIcon-cursor")
        #expect(ProviderBrandAsset.assetName(for: "openrouter") == "ProviderIcon-openrouter")
        #expect(ProviderBrandAsset.assetName(for: "sakana") == "ProviderIcon-sakana")
    }

    @Test("Provider aliases reuse their canonical Mac icons")
    func aliasesResolveToCanonicalAssets() {
        #expect(ProviderBrandAsset.assetName(for: "openai") == "ProviderIcon-codex")
        #expect(ProviderBrandAsset.assetName(for: "azureopenai") == "ProviderIcon-codex")
        #expect(ProviderBrandAsset.assetName(for: "moonshot") == "ProviderIcon-kimi")
        #expect(ProviderBrandAsset.assetName(for: "kimik2") == "ProviderIcon-kimi")
        #expect(ProviderBrandAsset.assetName(for: "alibabatokenplan") == "ProviderIcon-alibaba")
    }

    @Test("Every synced quota provider has a brand mark mapping")
    func syncedQuotaProvidersResolveToAssets() {
        for provider in QuotaProviderList.providers {
            #expect(
                ProviderBrandAsset.assetName(for: provider.id) != nil,
                "\(provider.id) should map to a provider brand asset")
        }
    }

    @Test("Unknown providers use the fallback mark")
    func unknownProvidersUseFallback() {
        #expect(ProviderBrandAsset.assetName(for: "") == nil)
        #expect(ProviderBrandAsset.assetName(for: "brand-new-ai-tool") == nil)
    }
}
