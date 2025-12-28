import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
public enum CopilotProviderDescriptor {
    public static let descriptor: ProviderDescriptor = .init(
        id: .copilot,
        metadata: ProviderMetadata(
            id: .copilot,
            displayName: "Copilot",
            sessionLabel: "Premium",
            weeklyLabel: "Chat",
            opusLabel: nil,
            supportsOpus: false,
            supportsCredits: false,
            creditsHint: "",
            toggleTitle: "Show Copilot usage",
            cliName: "copilot",
            defaultEnabled: false,
            dashboardURL: "https://github.com/settings/copilot",
            statusPageURL: "https://www.githubstatus.com/"),
        branding: ProviderBranding(
            iconStyle: .copilot,
            iconResourceName: "ProviderIcon-copilot",
            color: ProviderColor(red: 168 / 255, green: 85 / 255, blue: 247 / 255)),
        tokenCost: ProviderTokenCostConfig(
            supportsTokenCost: false,
            noDataMessage: { "Copilot cost summary is not supported." }),
        sourceLabel: "api",
        cli: ProviderCLIConfig(
            name: "copilot",
            sourceLabel: "copilot",
            versionDetector: nil,
            sourceModes: [.auto, .cli]),
        fetchPipeline: ProviderFetchPipeline(resolveStrategies: { _ in [CopilotAPIFetchStrategy()] }))
}

struct CopilotAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "copilot.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(context) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let token = Self.resolveToken(context), !token.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        let fetcher = CopilotUsageFetcher(token: token)
        let snap = try await fetcher.fetch()
        return ProviderFetchResult(
            usage: snap,
            credits: nil,
            dashboard: nil,
            sourceOverride: nil)
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(_ context: ProviderFetchContext) -> String? {
        let fromSettings = context.settings?.copilotAPIToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromSettings, !fromSettings.isEmpty { return fromSettings }
        let env = context.env["COPILOT_API_TOKEN"]
        return env?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
