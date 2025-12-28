import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
public enum GeminiProviderDescriptor {
    public static let descriptor: ProviderDescriptor = .init(
        id: .gemini,
        metadata: ProviderMetadata(
            id: .gemini,
            displayName: "Gemini",
            sessionLabel: "Pro",
            weeklyLabel: "Flash",
            opusLabel: nil,
            supportsOpus: false,
            supportsCredits: false,
            creditsHint: "",
            toggleTitle: "Show Gemini usage",
            cliName: "gemini",
            defaultEnabled: false,
            dashboardURL: "https://gemini.google.com",
            statusPageURL: nil,
            statusLinkURL: "https://www.google.com/appsstatus/dashboard/products/npdyhgECDJ6tB66MxXyo/history",
            statusWorkspaceProductID: "npdyhgECDJ6tB66MxXyo"),
        branding: ProviderBranding(
            iconStyle: .gemini,
            iconResourceName: "ProviderIcon-gemini",
            color: ProviderColor(red: 171 / 255, green: 135 / 255, blue: 234 / 255)),
        tokenCost: ProviderTokenCostConfig(
            supportsTokenCost: false,
            noDataMessage: { "Gemini cost summary is not supported." }),
        sourceLabel: "api",
        cli: ProviderCLIConfig(
            name: "gemini",
            sourceLabel: "gemini-cli",
            versionDetector: { ProviderVersionDetector.geminiVersion() },
            sourceModes: [.auto, .cli]),
        fetchPipeline: ProviderFetchPipeline(resolveStrategies: { _ in [GeminiStatusFetchStrategy()] }))
}

struct GeminiStatusFetchStrategy: ProviderFetchStrategy {
    let id: String = "gemini.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_: ProviderFetchContext) async -> Bool { true }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let probe = GeminiStatusProbe()
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
