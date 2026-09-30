import Foundation
import Testing
@testable import CodexBarCore

struct DevinProviderCLITests {
    @Test
    func `credential settings map the configured token and workspace`() throws {
        let config = ProviderConfig(
            id: .devin,
            cookieHeader: "Bearer fixture-token",
            workspaceID: "team/workspace-fixture")
        let context = ProviderCredentialSettingsContext(config: config, account: nil)
        let contribution = try #require(
            DevinProviderDescriptor.descriptor.settingsSection.credentialContribution(context: context))
        var builder = ProviderSettingsSnapshotBuilder()
        builder.apply(contribution)
        let settings = try #require(builder.build().devin)

        #expect(settings.cookieSource == .manual)
        #expect(settings.manualBearerToken == "Bearer fixture-token")
        #expect(settings.organization == "team/workspace-fixture")
    }

    @Test
    func `bearer token resolution prefers environment values then saved settings`() {
        let settings = DevinProviderSettings(
            cookieSource: .manual,
            manualBearerToken: "saved-token",
            organization: nil)

        #expect(
            settings.bearerToken(environment: ["DEVIN_BEARER_TOKEN": "primary-token"]) == "primary-token")
        #expect(
            settings.bearerToken(environment: ["DEVIN_AUTHORIZATION": "authorization-token"])
                == "authorization-token")
        #expect(settings.bearerToken(environment: [:]) == "saved-token")
    }

    @Test
    func `Linux browser exemption requires usable manual credentials`() {
        let cli = DevinProviderDescriptor.descriptor.cli
        let manualSettings = ProviderSettingsSnapshot.make(
            devin: DevinProviderSettings(
                cookieSource: .manual,
                manualBearerToken: "saved-token",
                organization: nil))
        let automaticSettings = ProviderSettingsSnapshot.make(
            devin: DevinProviderSettings(
                cookieSource: .auto,
                manualBearerToken: "saved-token",
                organization: nil))

        #if os(Linux)
        #expect(
            cli.isBrowserSupportExempt(
                sourceMode: .auto,
                environment: ["DEVIN_BEARER_TOKEN": "environment-token"],
                settings: manualSettings))
        #expect(
            cli.isBrowserSupportExempt(
                sourceMode: .auto,
                environment: [:],
                settings: manualSettings))
        #expect(
            !cli.isBrowserSupportExempt(
                sourceMode: .auto,
                environment: ["DEVIN_BEARER_TOKEN": "  "],
                settings: manualSettings))
        #expect(
            !cli.isBrowserSupportExempt(
                sourceMode: .auto,
                environment: [:],
                settings: automaticSettings))
        #else
        #expect(
            !cli.isBrowserSupportExempt(
                sourceMode: .auto,
                environment: ["DEVIN_BEARER_TOKEN": "environment-token"],
                settings: manualSettings))
        #endif
    }
}
