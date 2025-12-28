import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
public enum ZaiProviderDescriptor {
    public static let descriptor: ProviderDescriptor = .init(
        id: .zai,
        metadata: ProviderMetadata(
            id: .zai,
            displayName: "z.ai",
            sessionLabel: "Tokens",
            weeklyLabel: "MCP",
            opusLabel: nil,
            supportsOpus: false,
            supportsCredits: false,
            creditsHint: "",
            toggleTitle: "Show z.ai usage",
            cliName: "zai",
            defaultEnabled: false,
            dashboardURL: "https://z.ai/manage-apikey/subscription",
            statusPageURL: nil),
        branding: ProviderBranding(
            iconStyle: .zai,
            iconResourceName: "ProviderIcon-zai",
            color: ProviderColor(red: 232 / 255, green: 90 / 255, blue: 106 / 255)),
        tokenCost: ProviderTokenCostConfig(
            supportsTokenCost: false,
            noDataMessage: { "z.ai cost summary is not supported." }),
        sourceLabel: "api",
        cli: ProviderCLIConfig(
            name: "zai",
            aliases: ["z.ai"],
            sourceLabel: "zai",
            versionDetector: nil,
            sourceModes: [.auto, .cli]),
        fetchPipeline: ProviderFetchPipeline(resolveStrategies: { _ in [ZaiAPIFetchStrategy()] }))
}

struct ZaiAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "zai.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(context) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveToken(context) else {
            throw ZaiSettingsError.missingToken
        }
        let usage = try await ZaiUsageFetcher.fetchUsage(apiKey: apiKey)
        return ProviderFetchResult(
            usage: usage.toUsageSnapshot(),
            credits: nil,
            dashboard: nil,
            sourceOverride: "zai")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(_ context: ProviderFetchContext) -> String? {
        let fromSettings = context.settings?.zaiAPIToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromSettings, !fromSettings.isEmpty { return fromSettings }
        return ZaiSettingsReader.apiToken(environment: context.env)
    }
}
