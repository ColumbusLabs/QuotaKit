import CodexBarCore
import Testing
@testable import CodexBar

struct ProviderRegistryTests {
    @Test
    func `descriptor and implementation registries contain exactly the supported providers`() {
        let expected: [UsageProvider] = [.codex, .claude, .cursor, .grok]

        #expect(UsageProvider.allCases == expected)
        #expect(ProviderDescriptorRegistry.all.map(\.id) == expected)
        #expect(ProviderImplementationRegistry.all.map(\.id) == expected)
        #expect(ProviderCatalog.all.map(\.id) == expected)
    }

    @Test
    func `icon styles derive from supported provider identifiers`() {
        #expect(IconStyle.allCases == UsageProvider.allCases.map(IconStyle.init(provider:)) + [.combined])
        for descriptor in ProviderDescriptorRegistry.all {
            #expect(descriptor.branding.iconStyle == IconStyle(provider: descriptor.id))
        }
    }

    @Test
    func `provider log categories derive stable names`() {
        #expect([
            LogCategories.provider(.codex),
            LogCategories.provider(.claude, scope: "usage"),
            LogCategories.provider(.cursor, scope: "login"),
            LogCategories.provider(.grok),
        ] == ["codex", "claude-usage", "cursor-login", "grok"])
    }

    @Test
    func `cursor supports total auto and api quota lanes`() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .cursor)

        #expect(descriptor.fetchPlan.sourceModes == [.auto, .cli, .web])
        #expect(descriptor.metadata.sessionLabel == "Total")
        #expect(descriptor.metadata.weeklyLabel == "Auto")
        #expect(descriptor.metadata.supportsOpus)
        #expect(descriptor.metadata.opusLabel == "API")
    }

    @Test
    func `supported provider brand colors match the QuotaKit palette`() {
        expectColor(.codex, red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        expectColor(.claude, red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        expectColor(.cursor, red: 0, green: 0, blue: 0)
        expectColor(.grok, red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    }

    @Test
    func `provider confetti palettes are complete`() {
        for descriptor in ProviderDescriptorRegistry.all {
            let palette = descriptor.branding.confettiPalette
            #expect((2...3).contains(palette.count), "Invalid palette for \(descriptor.id.rawValue).")
            #expect(
                palette.dropFirst().contains { $0 != palette[0] },
                "Palette for \(descriptor.id.rawValue) must contain distinct colors.")
        }
    }
}

private func expectColor(_ provider: UsageProvider, red: Double, green: Double, blue: Double) {
    let color = ProviderDescriptorRegistry.descriptor(for: provider).branding.color
    #expect(abs(color.red - red) < 0.001, "\(provider.rawValue) red channel changed")
    #expect(abs(color.green - green) < 0.001, "\(provider.rawValue) green channel changed")
    #expect(abs(color.blue - blue) < 0.001, "\(provider.rawValue) blue channel changed")
}
