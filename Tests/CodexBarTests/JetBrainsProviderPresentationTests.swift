import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct JetBrainsProviderPresentationTests {
    @Test
    func `JetBrains presentation uses its local source label`() throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(
            suite: "ProviderSettingsDescriptorTests-jetbrains-presentation")
        let metadata = try #require(ProviderDescriptorRegistry.metadata[.jetbrains])
        let context = fixture.presentationContext(provider: .jetbrains, metadata: metadata)

        let detailLine = JetBrainsProviderImplementation()
            .presentation(context: context)
            .detailLine(context)

        #expect(detailLine == "local")
    }
}
