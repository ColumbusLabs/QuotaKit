import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum GroqProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .groq,
            metadata: ProviderMetadata(
                id: .groq,
                displayName: "Groq",
                sessionLabel: "Requests",
                weeklyLabel: "Tokens",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Groq usage",
                cliName: "groqcloud",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://console.groq.com/dashboard/metrics",
                statusPageURL: nil,
                statusLinkURL: "https://status.groq.com"),
            branding: ProviderBranding(
                iconStyle: .groq,
                iconResourceName: "ProviderIcon-groq",
                color: ProviderColor(red: 245 / 255, green: 104 / 255, blue: 68 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Groq cost history is not available via the metrics API." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [GroqAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "groqcloud",
                aliases: ["groq", "groq-api"],
                versionDetector: nil))
    }
}

struct GroqAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "groq.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        ProviderTokenResolver.groqToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = ProviderTokenResolver.groqToken(environment: context.env) else {
            throw GroqUsageError.missingCredentials
        }
        let usage = try await GroqUsageFetcher.fetchUsage(
            apiKey: apiKey,
            environment: context.env)
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "metrics")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
