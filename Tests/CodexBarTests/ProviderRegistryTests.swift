import CodexBarCore
import Testing
@testable import CodexBar

struct ProviderRegistryTests {
    @Test
    func `descriptor registry is complete and deterministic`() {
        let descriptors = ProviderDescriptorRegistry.all
        let ids = descriptors.map(\.id)

        #expect(!descriptors.isEmpty, "ProviderDescriptorRegistry must not be empty.")
        #expect(Set(ids).count == ids.count, "ProviderDescriptorRegistry contains duplicate IDs.")

        let missing = Set(UsageProvider.allCases).subtracting(ids)
        #expect(missing.isEmpty, "Missing descriptors for providers: \(missing).")

        let secondPass = ProviderDescriptorRegistry.all.map(\.id)
        #expect(ids == secondPass, "ProviderDescriptorRegistry order changed between reads.")
    }

    @Test
    func `implementation registry is complete and deterministic`() {
        let implementations = ProviderImplementationRegistry.all
        let ids = implementations.map(\.id)

        #expect(!implementations.isEmpty, "ProviderImplementationRegistry must not be empty.")
        #expect(Set(ids).count == ids.count, "ProviderImplementationRegistry contains duplicate IDs.")

        let missing = Set(UsageProvider.allCases).subtracting(ids)
        #expect(missing.isEmpty, "Missing implementations for providers: \(missing).")

        let secondPass = ProviderImplementationRegistry.all.map(\.id)
        #expect(ids == secondPass, "ProviderImplementationRegistry order changed between reads.")
    }

    @Test
    func `minimax sorts after zai in registry`() {
        let ids = ProviderDescriptorRegistry.all.map(\.id)
        guard let zaiIndex = ids.firstIndex(of: .zai),
              let minimaxIndex = ids.firstIndex(of: .minimax)
        else {
            Issue.record("Missing z.ai or MiniMax provider in registry order.")
            return
        }

        #expect(zaiIndex < minimaxIndex)
    }

    @Test
    func `cursor supports auto api and web source modes`() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .cursor)

        #expect(descriptor.fetchPlan.sourceModes == [.auto, .api, .web])
        #expect(descriptor.metadata.sessionLabel == "Auto")
        #expect(descriptor.metadata.weeklyLabel == "API")
        #expect(!descriptor.metadata.supportsOpus)
        #expect(descriptor.metadata.opusLabel == nil)
    }

    @Test
    func `priority provider brand colors match QuotaKit palette`() {
        expectColor(.codex, red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        expectColor(.claude, red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        expectColor(.cursor, red: 0, green: 0, blue: 0)
        expectColor(.grok, red: 26 / 255, green: 26 / 255, blue: 26 / 255)
        expectColor(.commandcode, red: 71 / 255, green: 85 / 255, blue: 105 / 255)
        expectColor(.opencodego, red: 52 / 255, green: 211 / 255, blue: 153 / 255)
    }

    @Test
    func `provider brand colors stay visually distinct`() {
        let descriptors = ProviderDescriptorRegistry.all

        for leftIndex in descriptors.indices {
            for rightIndex in descriptors.index(after: leftIndex)..<descriptors.endIndex {
                let left = descriptors[leftIndex]
                let right = descriptors[rightIndex]
                let delta = abs(left.branding.color.red - right.branding.color.red)
                    + abs(left.branding.color.green - right.branding.color.green)
                    + abs(left.branding.color.blue - right.branding.color.blue)
                #expect(delta > 0.10, "\(left.id.rawValue) and \(right.id.rawValue) colors are too close")
            }
        }
    }
}

private func expectColor(_ provider: UsageProvider, red: Double, green: Double, blue: Double) {
    let color = ProviderDescriptorRegistry.descriptor(for: provider).branding.color
    #expect(abs(color.red - red) < 0.001, "\(provider.rawValue) red channel changed")
    #expect(abs(color.green - green) < 0.001, "\(provider.rawValue) green channel changed")
    #expect(abs(color.blue - blue) < 0.001, "\(provider.rawValue) blue channel changed")
}
