import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
@MainActor
struct HuggingFaceProviderSettingsTests {
    @Test
    func `browser cookies default off and provider settings reach the runtime snapshot`() throws {
        let settings = testSettingsStore(suiteName: "HuggingFaceProviderSettingsTests")
        let implementation = HuggingFaceProviderImplementation()

        #expect(settings.huggingFaceCookieSource == .off)
        let defaultContribution = try #require(implementation.settingsSnapshot(
            context: ProviderSettingsSnapshotContext(settings: settings, tokenOverride: nil)))
        let defaultSnapshot = ProviderSettingsSnapshot(contributions: [defaultContribution])
        #expect(defaultSnapshot.huggingface?.cookieSource == .off)

        settings.huggingFaceCookieSource = .manual
        settings.huggingFaceCookieHeader = "session=synthetic-cookie"
        let manualContribution = try #require(implementation.settingsSnapshot(
            context: ProviderSettingsSnapshotContext(settings: settings, tokenOverride: nil)))
        let manualSnapshot = ProviderSettingsSnapshot(contributions: [manualContribution])
        #expect(manualSnapshot.huggingface?.cookieSource == .manual)
        #expect(manualSnapshot.huggingface?.manualCookieHeader == "session=synthetic-cookie")
    }

    @Test
    func `CLI credential projection defaults off and preserves configured cookie modes`() throws {
        func project(_ config: ProviderConfig?) throws -> HuggingFaceProviderSettings {
            let context = ProviderCredentialSettingsContext(config: config, account: nil)
            let contribution = try #require(
                HuggingFaceProviderDescriptor.descriptor.settingsSection.credentialContribution(context: context))
            var builder = ProviderSettingsSnapshotBuilder()
            builder.apply(contribution)
            return try #require(builder.build().huggingface)
        }

        #expect(HuggingFaceProviderSettings().cookieSource == .off)
        #expect(try project(nil).cookieSource == .off)

        let automatic = try project(ProviderConfig(id: .huggingface, cookieSource: .auto))
        #expect(automatic.cookieSource == .auto)

        let manual = try project(ProviderConfig(
            id: .huggingface,
            cookieHeader: "session=synthetic-cookie",
            cookieSource: .manual))
        #expect(manual.cookieSource == .manual)
        #expect(manual.manualCookieHeader == "session=synthetic-cookie")

        let inferredManual = try project(ProviderConfig(id: .huggingface, cookieHeader: "session=legacy-cookie"))
        #expect(inferredManual.cookieSource == .manual)
        #expect(inferredManual.manualCookieHeader == "session=legacy-cookie")
    }
}
