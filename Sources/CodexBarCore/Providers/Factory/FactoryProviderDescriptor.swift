import CodexBarMacroSupport
import Foundation
import SweetCookieKit

@ProviderDescriptorRegistration
public enum FactoryProviderDescriptor {
    public static let descriptor: ProviderDescriptor = .init(
        id: .factory,
        metadata: ProviderMetadata(
            id: .factory,
            displayName: "Droid",
            sessionLabel: "Standard",
            weeklyLabel: "Premium",
            opusLabel: nil,
            supportsOpus: false,
            supportsCredits: false,
            creditsHint: "",
            toggleTitle: "Show Droid usage",
            cliName: "factory",
            defaultEnabled: false,
            browserCookieOrder: Browser.defaultImportOrder,
            dashboardURL: "https://app.factory.ai/settings/billing",
            statusPageURL: "https://status.factory.ai",
            statusLinkURL: nil),
        branding: ProviderBranding(
            iconStyle: .factory,
            iconResourceName: "ProviderIcon-factory",
            color: ProviderColor(red: 255 / 255, green: 107 / 255, blue: 53 / 255)),
        tokenCost: ProviderTokenCostConfig(
            supportsTokenCost: false,
            noDataMessage: { "Droid cost summary is not supported." }),
        sourceLabel: "web",
        cli: ProviderCLIConfig(
            name: "factory",
            sourceLabel: "factory",
            versionDetector: nil,
            sourceModes: [.auto, .cli]),
        fetchPipeline: ProviderFetchPipeline(resolveStrategies: { _ in [FactoryStatusFetchStrategy()] }))
}

struct FactoryStatusFetchStrategy: ProviderFetchStrategy {
    let id: String = "factory.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_: ProviderFetchContext) async -> Bool { true }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let probe = FactoryStatusProbe()
        let snap = try await probe.fetch()
        return ProviderFetchResult(
            usage: snap.toUsageSnapshot(),
            credits: nil,
            dashboard: nil,
            sourceOverride: nil)
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
