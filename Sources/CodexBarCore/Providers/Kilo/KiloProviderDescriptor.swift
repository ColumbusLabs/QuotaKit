import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum KiloProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .kilo,
            metadata: ProviderMetadata(
                id: .kilo,
                displayName: "Kilo",
                sessionLabel: "Credits",
                weeklyLabel: "Kilo Pass",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Kilo usage",
                cliName: "kilo",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://app.kilo.ai/account/usage",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .kilo,
                iconResourceName: "ProviderIcon-kilo",
                color: ProviderColor(red: 242 / 255, green: 112 / 255, blue: 39 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Kilo cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [KiloAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "kilo",
                aliases: ["kilo-ai"],
                versionDetector: nil))
    }
}

struct KiloAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "kilo.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveToken(environment: context.env) else {
            throw KiloUsageError.missingCredentials
        }
        let usage = try await KiloUsageFetcher.fetchUsage(apiKey: apiKey, environment: context.env)
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.kiloToken(environment: environment)
    }
}
