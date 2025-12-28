import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
public enum AntigravityProviderDescriptor {
    public static let descriptor: ProviderDescriptor = .init(
        id: .antigravity,
        metadata: ProviderMetadata(
            id: .antigravity,
            displayName: "Antigravity",
            sessionLabel: "Claude",
            weeklyLabel: "Gemini Pro",
            opusLabel: "Gemini Flash",
            supportsOpus: true,
            supportsCredits: false,
            creditsHint: "",
            toggleTitle: "Show Antigravity usage (experimental)",
            cliName: "antigravity",
            defaultEnabled: false,
            dashboardURL: nil,
            statusPageURL: nil,
            statusLinkURL: "https://www.google.com/appsstatus/dashboard/products/npdyhgECDJ6tB66MxXyo/history",
            statusWorkspaceProductID: "npdyhgECDJ6tB66MxXyo"),
        branding: ProviderBranding(
            iconStyle: .antigravity,
            iconResourceName: "ProviderIcon-antigravity",
            color: ProviderColor(red: 96 / 255, green: 186 / 255, blue: 126 / 255)),
        tokenCost: ProviderTokenCostConfig(
            supportsTokenCost: false,
            noDataMessage: { "Antigravity cost summary is not supported." }),
        sourceLabel: "local",
        cli: ProviderCLIConfig(
            name: "antigravity",
            sourceLabel: "antigravity",
            versionDetector: nil,
            sourceModes: [.auto, .cli]),
        fetchPipeline: ProviderFetchPipeline(resolveStrategies: { _ in [AntigravityStatusFetchStrategy()] }))
}

struct AntigravityStatusFetchStrategy: ProviderFetchStrategy {
    let id: String = "antigravity.local"
    let kind: ProviderFetchKind = .localProbe

    func isAvailable(_: ProviderFetchContext) async -> Bool { true }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let probe = AntigravityStatusProbe()
        let snap = try await probe.fetch()
        return try ProviderFetchResult(
            usage: snap.toUsageSnapshot(),
            credits: nil,
            dashboard: nil,
            sourceOverride: nil)
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
