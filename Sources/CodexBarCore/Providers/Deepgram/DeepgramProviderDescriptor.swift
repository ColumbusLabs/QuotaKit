import Foundation

public enum DeepgramProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.spec.makeDescriptor(fetchPlan: Self.fetchPlan())
    public static let spec = PluginProviderSpec(
        id: .deepgram,
        displayName: "Deepgram",
        sessionLabel: "Requests",
        weeklyLabel: "Usage",
        creditsHint: "Usage summary from Deepgram API",
        debugLogUnavailableMessage: "Deepgram debug log not yet implemented",
        dashboardURL: "https://console.deepgram.com/project/",
        statusLinkURL: "https://status.deepgram.com",
        color: ProviderColor(
            red: 0.49,
            green: 0.23,
            blue: 0.93),
        confetti: [0x13EF95, 0x149AFB, 0x1A1A1F],
        widgetColor: ProviderColor(hex: 0x0A121B),
        noDataMessage: "Deepgram cost summary is not yet supported.",
        environmentKey: DeepgramSettingsReader.apiKeyEnvironmentKey,
        config: ProviderConfigCapabilities(workspaceIDValidationOrder: 5),
        aliases: ["dg"],
        scriptSettings: { context in
            [DeepgramSettingsReader.apiURLEnvironmentKey:
                DeepgramSettingsReader.apiURL(environment: context.env).absoluteString]
        },
        validateContext: { context in
            try DeepgramSettingsReader.validateEndpointOverride(environment: context.env)
        },
        apiKeyField: .init(
            id: "deepgram-api-key",
            title: "API key",
            subtitle: "Stored in ~/.quotakit/config.json. Get your key from console.deepgram.com.",
            placeholder: "dg_..."),
        workspaceField: .init(
            environmentKey: DeepgramSettingsReader.projectIDEnvironmentKey,
            field: .init(
                id: "deepgram-project-id",
                title: "Project ID",
                subtitle: "Optional. Leave blank to discover and aggregate projects visible to the API key.",
                placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"),
            resolvesProjectID: true),
        showsAPIDetail: true,
        availability: .configuredKey)

    private static func fetchPlan() -> ProviderFetchPlan {
        ProviderFetchPlan(
            sourceModes: [.auto, .api],
            pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                let swift = DeepgramAPIFetchStrategy()
                #if canImport(JavaScriptCore) || canImport(CQuickJS)
                guard ProviderPluginPrototype.isEnabled(environment: context.env) else { return [swift] }
                return [self.spec.makeStrategy(timeout: self.spec.fetchTimeout(environment: context.env)), swift]
                #else
                return [swift]
                #endif
            }))
    }
}

struct DeepgramAPIFetchStrategy: ProviderFetchStrategy {
    let id = "deepgram.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        ProviderTokenResolver.token(for: .deepgram, environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = ProviderTokenResolver.token(for: .deepgram, environment: context.env) else {
            throw DeepgramSettingsError.missingToken
        }
        let usage = try await DeepgramUsageFetcher.fetchUsage(
            apiKey: apiKey,
            projectID: ProviderTokenResolver.token(for: .deepgram, kind: .projectID, environment: context.env),
            environment: context.env)
        return self.makeResult(usage: usage.toUsageSnapshot(), sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}

/// Errors related to Deepgram settings
public enum DeepgramSettingsError: LocalizedError, Sendable {
    case missingToken
    case invalidEndpointOverride(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "Deepgram API token not configured. Set DEEPGRAM_API_KEY environment variable or configure in Settings."
        case let .invalidEndpointOverride(key):
            "Deepgram endpoint override \(key) must use HTTPS or a bare host."
        }
    }
}
