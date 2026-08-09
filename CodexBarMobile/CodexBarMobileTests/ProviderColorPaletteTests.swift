import Testing
@testable import CodexBarMobile

@Suite("Provider color palette")
struct ProviderColorPaletteTests {
    @Test
    func `Supported providers use QuotaKit-approved raw colors`() {
        expectColor("codex", red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        expectColor("claude", red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        expectColor("cursor", red: 0, green: 0, blue: 0)
        expectColor("grok", red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    }

    @Test
    func `Retired and unknown providers use the fallback mark`() {
        #expect(ProviderColorPalette.rawColor(for: "gemini") == nil)
        #expect(ProviderColorPalette.rawColor(for: "perplexity") == nil)
        #expect(ProviderColorPalette.rawColor(for: "") == nil)
        #expect(ProviderColorPalette.rawColor(for: "brand-new-ai-tool") == nil)
    }

    @Test
    func `Supported provider colors stay visually distinct`() throws {
        let providers = ["codex", "claude", "cursor", "grok"]
        for leftIndex in providers.indices {
            for rightIndex in providers.index(after: leftIndex)..<providers.endIndex {
                let left = try #require(ProviderColorPalette.rawColor(for: providers[leftIndex]))
                let right = try #require(ProviderColorPalette.rawColor(for: providers[rightIndex]))
                let delta = abs(left.red - right.red)
                    + abs(left.green - right.green)
                    + abs(left.blue - right.blue)
                #expect(delta > 0.10)
            }
        }
    }
}

private func expectColor(_ provider: String, red: Double, green: Double, blue: Double) {
    let color = ProviderColorPalette.rawColor(for: provider)
    #expect(color != nil, "\(provider) should have a raw palette entry")
    #expect(abs((color?.red ?? -1) - red) < 0.001)
    #expect(abs((color?.green ?? -1) - green) < 0.001)
    #expect(abs((color?.blue ?? -1) - blue) < 0.001)
}
