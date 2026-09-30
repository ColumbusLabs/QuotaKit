import Testing
@testable import CodexBarCore

struct ProviderDescriptorReplacementTests {
    @Test
    func `replacement updates ordered descriptor without changing insertion order`() {
        let store = ProviderDescriptorRegistry.Store()
        let amp = ProviderDescriptorRegistry.descriptor(for: .amp)
        let claude = ProviderDescriptorRegistry.descriptor(for: .claude)
        let replacementName = "amp-registry-replacement-test"
        let replacement = ProviderDescriptor(
            id: amp.id,
            metadata: amp.metadata,
            branding: amp.branding,
            tokenCost: amp.tokenCost,
            fetchPlan: amp.fetchPlan,
            cli: ProviderCLIConfig(name: replacementName, versionDetector: nil))

        store.register(amp)
        store.register(claude)
        let originalOrder = store.all.map(\.id)

        store.register(replacement)

        #expect(store.all.map(\.id) == originalOrder)
        #expect(store.all.filter { $0.id == .amp }.count == 1)
        #expect(store.all.first(where: { $0.id == .amp })?.cli.name == replacementName)
        #expect(store.descriptor(for: .amp)?.cli.name == replacementName)

        store.register(ProviderDescriptorRegistry.descriptor(for: .kilo))
        #expect(store.all.map(\.id) == [.amp, .claude, .kilo])
    }
}
