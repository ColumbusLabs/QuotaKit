import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIProviderCredentialGuidanceTests {
    @Test(arguments: [
        (UsageProvider.gitkraken, "Set a GitKraken access token in Settings or GITKRAKEN_API_TOKEN."),
        (UsageProvider.v0, "v0 API key not configured. Create one at v0.app/settings/keys."),
    ])
    func `API only providers show missing token guidance when no strategy is available`(
        provider: UsageProvider,
        expectedMessage: String)
    {
        let error = CodexBarCLI.providerErrorWithCredentialGuidance(
            ProviderFetchError.noAvailableStrategy(provider),
            provider: provider,
            environment: [:])

        #expect(error.localizedDescription == expectedMessage)
        #expect((error as? ProviderFetchClassifiedError)?.kind == .missingCredential)
    }

    @Test(arguments: [
        (UsageProvider.gitkraken, GitKrakenProviderDescriptor.tokenKey),
        (UsageProvider.v0, V0SettingsReader.apiKeyEnvironmentKey),
    ])
    func `configured tokens do not turn unavailable strategies into missing credential errors`(
        provider: UsageProvider,
        environmentKey: String)
    {
        let original = ProviderFetchError.noAvailableStrategy(provider)
        let error = CodexBarCLI.providerErrorWithCredentialGuidance(
            original,
            provider: provider,
            environment: [environmentKey: "fixture-token"])

        #expect(error.localizedDescription == original.localizedDescription)
    }

    @Test
    func `unrelated strategy errors preserve their original guidance`() {
        let original = ProviderFetchError.noAvailableStrategy(.kiro)
        let error = CodexBarCLI.providerErrorWithCredentialGuidance(
            original,
            provider: .kiro,
            environment: [:])

        #expect(error.localizedDescription == original.localizedDescription)
    }
}
