import Foundation

/// Swift registration data for bundled API-key plugins. Fetching and parsing stay in the plugin.
public struct PluginProviderSpec: Sendable {
    public struct APIKeyField: Sendable {
        public let id: String
        public let title: String
        public let subtitle: String
        public var placeholder: String? = "Paste API key…"
        public var action: (id: String, title: String, url: String)?
    }

    public let id: UsageProvider
    public let displayName: String
    public let sessionLabel: String
    public let weeklyLabel: String
    public var opusLabel: String?
    public var toggleTitle: String?
    public var debugLogUnavailableMessage: String?
    public var balanceOnly = false
    public var usesDetailBackedWindow = false
    public let dashboardURL: String
    public var statusLinkURL: String?
    public let color: ProviderColor
    public let confetti: [UInt32]
    public let noDataMessage: String
    public let environmentKey: String
    public var environmentAliases: [String] = []
    public var missingCredentialMessage: ProviderCredentialAdapter.MissingCredentialMessage?
    public var additionalProjections: [ProviderCredentialEnvironmentProjection] = []
    public var tokenAccountSupport: TokenAccountSupport?
    public var config = ProviderConfigCapabilities()
    public var menuBarMetrics: ProviderMenuBarMetricCapabilities?
    public var presentation = ProviderUsagePresentation()
    public var aliases: [String] = []
    public var timeout = ProviderPluginRuntime.defaultTimeout
    public var scriptSettings: @Sendable (ProviderFetchContext) -> [String: String] = { _ in [:] }
    public var validateContext: ScriptFetchStrategy.ContextValidator = { _ in }
    public var apiKeyField: APIKeyField?
    public var showsAPIDetail = false
    public var requiresCredentialForAvailability = false

    public func apiKey(environment: [String: String]) -> String? {
        SettingsValue.first(in: environment, keys: [self.environmentKey] + self.environmentAliases)
    }

    public func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: self.id,
            menuBarMetrics: self.menuBarMetrics,
            credentials: .apiKey(
                environmentKey: self.environmentKey,
                additionalProjections: self.additionalProjections,
                resolve: self.apiKey,
                tokenAccountSupport: self.tokenAccountSupport,
                missingCredentialMessage: self.missingCredentialMessage),
            config: self.config,
            metadata: ProviderMetadata(
                id: self.id, displayName: self.displayName,
                sessionLabel: self.sessionLabel, weeklyLabel: self.weeklyLabel,
                opusLabel: self.opusLabel, supportsOpus: self.opusLabel != nil,
                supportsCredits: false, creditsHint: "",
                toggleTitle: self.toggleTitle ?? "Show \(self.displayName) usage",
                cliName: self.id.rawValue, defaultEnabled: false, widgetSelectable: false,
                debugLogUnavailableMessage: self.debugLogUnavailableMessage,
                balanceOnly: self.balanceOnly, usesDetailBackedWindow: self.usesDetailBackedWindow,
                dashboardURL: self.dashboardURL, statusPageURL: nil, statusLinkURL: self.statusLinkURL),
            branding: ProviderBranding(
                iconStyle: .init(provider: self.id), iconResourceName: "ProviderIcon-\(self.id.rawValue)",
                color: self.color, confettiPalette: self.confetti.map { ProviderColor(hex: $0) }),
            tokenCost: ProviderTokenCostConfig(supportsTokenCost: false, noDataMessage: { self.noDataMessage }),
            presentation: self.presentation,
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [self.makeStrategy()] })),
            cli: ProviderCLIConfig(name: self.id.rawValue, aliases: self.aliases, versionDetector: nil))
    }

    func scriptValues(_ context: ProviderFetchContext) -> ScriptFetchStrategy.Values? {
        guard let key = self.apiKey(environment: context.env) else { return nil }
        return .init(settings: self.scriptSettings(context), secrets: [self.environmentKey: key])
    }

    func makeStrategy(transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) -> ScriptFetchStrategy {
        ScriptFetchStrategy(
            id: "\(self.id.rawValue).js", provider: self.id, bundledPlugin: self.id.rawValue,
            secretKey: self.environmentKey, sourceLabel: "api", transport: transport, timeout: self.timeout,
            validateContext: self.validateContext, resolveValues: self.scriptValues, isEnabled: { _ in true })
    }
}
