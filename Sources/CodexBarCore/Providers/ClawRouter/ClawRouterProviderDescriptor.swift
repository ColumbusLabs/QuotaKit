import Foundation

public enum ClawRouterProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: ClawRouterSettingsReader.apiKeyEnvironmentKey,
        additionalProjections: [.enterpriseHost(ClawRouterSettingsReader.baseURLEnvironmentKey)],
        resolve: ClawRouterSettingsReader.apiKey,
        missingCredentialMessage: { _ in ClawRouterUsageError.missingCredentials.errorDescription })

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .clawrouter,
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .clawrouter,
                displayName: "ClawRouter",
                sessionLabel: "Monthly budget",
                weeklyLabel: "Requests",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show ClawRouter usage",
                cliName: "clawrouter",
                defaultEnabled: false,
                widgetSelectable: false,
                dashboardURL: "https://clawrouter.openclaw.ai/dashboard/access",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .clawrouter),
                iconResourceName: "ProviderIcon-clawrouter",
                color: ProviderColor(red: 42 / 255, green: 130 / 255, blue: 245 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x332CB3),
                    ProviderColor(hex: 0x456FDD),
                    ProviderColor(hex: 0xFFFFFF),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "ClawRouter spend is reported by its usage API." }),
            fetchPlan: self.fetchPlan(),
            cli: ProviderCLIConfig(
                name: "clawrouter",
                aliases: ["claw-router"],
                versionDetector: nil))
    }

    private static func fetchPlan() -> ProviderFetchPlan {
        #if canImport(JavaScriptCore)
        ProviderFetchPlan(
            sourceModes: [.auto, .api],
            pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                let swift = ClawRouterAPIFetchStrategy()
                guard ProviderPluginPrototype.isEnabled(environment: context.env) else { return [swift] }
                return [
                    ScriptFetchStrategy(
                        id: "clawrouter.js",
                        provider: .clawrouter,
                        bundledPlugin: "clawrouter",
                        secretKey: ClawRouterSettingsReader.apiKeyEnvironmentKey,
                        resolveSecret: { ProviderTokenResolver.clawRouterToken(environment: $0) }),
                    swift,
                ]
            }))
        #else
        ProviderFetchPlan(
            sourceModes: [.auto, .api],
            pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [ClawRouterAPIFetchStrategy()] }))
        #endif
    }
}

struct ClawRouterAPIFetchStrategy: ProviderFetchStrategy {
    let id = "clawrouter.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        ProviderTokenResolver.clawRouterToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = ProviderTokenResolver.clawRouterToken(environment: context.env) else {
            throw ClawRouterUsageError.missingCredentials
        }
        try ClawRouterSettingsReader.validateEndpointOverride(environment: context.env)
        let usage = try await ClawRouterUsageFetcher.fetchUsage(
            apiKey: apiKey,
            baseURL: ClawRouterSettingsReader.baseURL(environment: context.env))
        return self.makeResult(usage: usage.toUsageSnapshot(), sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
