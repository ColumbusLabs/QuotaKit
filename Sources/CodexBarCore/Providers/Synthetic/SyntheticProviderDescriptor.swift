import Foundation

public enum SyntheticProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .synthetic,
            metadata: ProviderMetadata(
                id: .synthetic,
                displayName: "Synthetic",
                sessionLabel: "Five-hour quota",
                weeklyLabel: "Weekly tokens",
                opusLabel: "Search hourly",
                supportsOpus: true,
                supportsCredits: false,
                creditsHint: "Weekly token quota regenerates continuously.",
                toggleTitle: "Show Synthetic usage",
                cliName: "synthetic",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                dashboardURL: nil,
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .synthetic),
                iconResourceName: "ProviderIcon-synthetic",
                color: ProviderColor(red: 42 / 255, green: 42 / 255, blue: 42 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x6366F1),
                    ProviderColor(hex: 0x3E3E3E),
                    ProviderColor(hex: 0xF7F6F3),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Synthetic cost summary is not supported." }),
            fetchPlan: self.fetchPlan(),
            cli: ProviderCLIConfig(
                name: "synthetic",
                aliases: ["synthetic.new"],
                versionDetector: nil))
    }

    private static func fetchPlan() -> ProviderFetchPlan {
        #if canImport(JavaScriptCore)
        .scriptPrototypeAPI(
            configuration: .init(
                provider: .synthetic,
                plugin: "synthetic",
                secretKey: SyntheticSettingsReader.apiKeyKey,
                strategyID: "synthetic.api"),
            resolveToken: { ProviderTokenResolver.syntheticToken(environment: $0) },
            missingCredentialsError: { SyntheticSettingsError.missingToken },
            loadUsage: { apiKey, _ in
                try await SyntheticUsageFetcher.fetchUsage(apiKey: apiKey).toUsageSnapshot()
            })
        #else
        .apiToken(
            strategyID: "synthetic.api",
            resolveToken: { ProviderTokenResolver.syntheticToken(environment: $0) },
            missingCredentialsError: { SyntheticSettingsError.missingToken },
            loadUsage: { apiKey, _ in
                try await SyntheticUsageFetcher.fetchUsage(apiKey: apiKey).toUsageSnapshot()
            })
        #endif
    }
}
