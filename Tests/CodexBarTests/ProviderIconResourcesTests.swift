import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ProviderIconResourcesTests {
    @Test
    func `provider brand icons are cached after first load`() throws {
        ProviderBrandIcon.resetCacheForTesting()
        defer { ProviderBrandIcon.resetCacheForTesting() }

        let first = try #require(ProviderBrandIcon.image(for: .codex))
        let second = try #require(ProviderBrandIcon.image(for: .codex))

        #expect(first === second)
        #expect(first.size == NSSize(width: 16, height: 16))
        #expect(first.isTemplate)
    }

    @Test
    func `registered providers resolve bundled brand icons`() {
        ProviderBrandIcon.resetCacheForTesting()
        defer { ProviderBrandIcon.resetCacheForTesting() }

        for provider in UsageProvider.allCases {
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            #expect(
                ProviderBrandIcon.image(for: provider) != nil,
                "Missing icon resource \(descriptor.branding.iconResourceName).svg for \(provider.rawValue)")
        }
    }
}
