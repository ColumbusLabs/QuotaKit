import Foundation

public enum ClawRouterProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.spec.makeDescriptor(fetchPlan: Self.fetchPlan())
    public static let spec = PluginProviderSpec(
        id: .clawrouter,
        displayName: "ClawRouter",
        sessionLabel: "Monthly budget",
        weeklyLabel: "Requests",
        debugLogUnavailableMessage: "ClawRouter debug log not yet implemented",
        dashboardURL: "https://clawrouter.openclaw.ai/dashboard/access",
        color: ProviderColor(red: 42 / 255, green: 130 / 255, blue: 245 / 255),
        confetti: [0x332CB3, 0x456FDD, 0xFFFFFF],
        noDataMessage: "ClawRouter spend is reported by its usage API.",
        environmentKey: ClawRouterSettingsReader.apiKeyEnvironmentKey,
        missingCredentialMessage: { _ in ClawRouterSettingsReader.missingCredentialsMessage },
        additionalProjections: [.enterpriseHost(ClawRouterSettingsReader.baseURLEnvironmentKey)],
        config: ProviderConfigCapabilities(supportsEnterpriseHost: true),
        presentation: ProviderUsagePresentation(costPresenter: { _ in
            ProviderCostPresentation(showsGenericFallback: false, menuCardStyle: .clawRouter)
        }),
        aliases: ["claw-router"],
        scriptSettings: { context in
            [ClawRouterSettingsReader.baseURLEnvironmentKey:
                ClawRouterSettingsReader.baseURL(environment: context.env).absoluteString]
        },
        validateContext: { try ClawRouterSettingsReader.validateEndpointOverride(environment: $0.env) })

    private static func fetchPlan() -> ProviderFetchPlan {
        ProviderFetchPlan(
            sourceModes: [.auto, .api],
            pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                let swift = ClawRouterAPIFetchStrategy()
                #if canImport(JavaScriptCore) || canImport(CQuickJS)
                guard ProviderPluginPrototype.isEnabled(environment: context.env) else { return [swift] }
                return [ScriptFetchStrategy(
                    id: "clawrouter.js",
                    provider: .clawrouter,
                    bundledPlugin: "clawrouter",
                    secretKey: ClawRouterSettingsReader.apiKeyEnvironmentKey,
                    sourceLabel: "api",
                    validateContext: { context in
                        try ClawRouterSettingsReader.validateEndpointOverride(environment: context.env)
                    },
                    resolveValues: { context in
                        guard let token = self.spec.apiKey(environment: context.env) else {
                            return nil
                        }
                        return ScriptFetchStrategy.Values(
                            settings: [
                                ClawRouterSettingsReader.baseURLEnvironmentKey:
                                    ClawRouterSettingsReader.baseURL(environment: context.env).absoluteString,
                            ],
                            secrets: [ClawRouterSettingsReader.apiKeyEnvironmentKey: token])
                    }), swift]
                #else
                return [swift]
                #endif
            }))
    }
}

struct ClawRouterAPIFetchStrategy: ProviderFetchStrategy {
    let id = "clawrouter.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        ProviderTokenResolver.token(for: .clawrouter, environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = ProviderTokenResolver.token(for: .clawrouter, environment: context.env) else {
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
