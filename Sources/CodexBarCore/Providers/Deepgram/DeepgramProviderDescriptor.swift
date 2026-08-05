import Foundation

public enum DeepgramProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter(
        supportsAPIKeyOverride: true,
        environmentProjections: [
            .apiKey(DeepgramSettingsReader.apiKeyEnvironmentKey),
            .workspaceID(DeepgramSettingsReader.projectIDEnvironmentKey),
        ],
        tokenResolver: { kind, environment, _ in
            let value: String? = switch kind {
            case .primary: DeepgramSettingsReader.apiKey(environment: environment)
            case .projectID: DeepgramSettingsReader.projectID(environment: environment)
            case .secondary: nil
            }
            guard let value else { return nil }
            return ProviderTokenResolution(token: value, source: .environment)
        },
        authDetector: { environment, _ in
            DeepgramSettingsReader.apiKey(environment: environment) == nil ? [] : ["api"]
        })

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .deepgram,
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .deepgram,
                displayName: "Deepgram",
                sessionLabel: "Requests",
                weeklyLabel: "Usage",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "Usage summary from Deepgram API",
                toggleTitle: "Show Deepgram usage",
                cliName: "deepgram",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://console.deepgram.com/project/",
                statusPageURL: nil,
                statusLinkURL: "https://status.deepgram.com"),
            branding: ProviderBranding(
                iconStyle: .init(provider: .deepgram),
                iconResourceName: "ProviderIcon-deepgram",
                color: ProviderColor(
                    red: 0.49,
                    green: 0.23,
                    blue: 0.93),
                confettiPalette: [
                    ProviderColor(hex: 0x13EF95),
                    ProviderColor(hex: 0x149AFB),
                    ProviderColor(hex: 0x1A1A1F),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: {
                    "Deepgram cost summary is not yet supported."
                }),
            fetchPlan: self.fetchPlan(),
            cli: ProviderCLIConfig(
                name: "deepgram",
                aliases: ["dg"],
                versionDetector: nil))
    }

    private static func fetchPlan() -> ProviderFetchPlan {
        ProviderFetchPlan(
            sourceModes: [.auto, .api],
            pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                let swift = DeepgramAPIFetchStrategy()
                #if canImport(JavaScriptCore)
                guard ProviderPluginPrototype.isEnabled(environment: context.env) else { return [swift] }
                return [
                    ScriptFetchStrategy(
                        id: "deepgram.js",
                        provider: .deepgram,
                        bundledPlugin: "deepgram",
                        secretKey: DeepgramSettingsReader.apiKeyEnvironmentKey,
                        resolveValues: { context in
                            guard let key = ProviderTokenResolver.deepgramResolution(
                                type: .apiKey,
                                environment: context.env)
                            else { return nil }
                            var settings: [String: String] = [:]
                            if let project = ProviderTokenResolver.deepgramResolution(
                                type: .projectID,
                                environment: context.env)
                            {
                                settings[DeepgramSettingsReader.projectIDEnvironmentKey] = project
                            }
                            if let apiURL = context.env[DeepgramUsageFetcher.apiURLKey] {
                                settings[DeepgramUsageFetcher.apiURLKey] = apiURL
                            }
                            return ScriptFetchStrategy.Values(
                                settings: settings,
                                secrets: [DeepgramSettingsReader.apiKeyEnvironmentKey: key])
                        }),
                    swift,
                ]
                #else
                return [swift]
                #endif
            }))
    }
}

struct DeepgramAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "deepgram.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveAPIKey(context) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveAPIKey(context) else {
            throw DeepgramSettingsError.missingToken
        }

        let usage = try await DeepgramUsageFetcher.fetchUsage(
            apiKey: apiKey,
            projectID: Self.resolveProjectID(context),
            environment: context.env)

        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveAPIKey(_ context: ProviderFetchContext) -> String? {
        ProviderTokenResolver.deepgramResolution(
            type: .apiKey,
            environment: context.env)
    }

    private static func resolveProjectID(_ context: ProviderFetchContext) -> String? {
        ProviderTokenResolver.deepgramResolution(
            type: .projectID,
            environment: context.env)
    }
}

/// Errors related to Deepgram settings
public enum DeepgramSettingsError: LocalizedError, Sendable {
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "Deepgram API token not configured. Set DEEPGRAM_API_KEY environment variable or configure in Settings."
        }
    }
}
