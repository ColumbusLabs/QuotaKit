import Foundation

public enum HyperProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    public static let apiKeyEnvironmentKey = "HYPER_API_KEY"

    private static let credentials = ProviderCredentialAdapter(
        supportsAPIKeyOverride: true,
        apiKeyDebugLabel: apiKeyEnvironmentKey,
        environmentProjections: [.apiKey(apiKeyEnvironmentKey)],
        tokenResolver: { kind, environment, _ in
            guard kind == .primary, let token = Self.apiKey(environment: environment) else { return nil }
            return ProviderTokenResolution(token: token, source: .environment)
        },
        tokenAccountSupport: TokenAccountSupport(
            title: "API keys",
            subtitle: "Store multiple Charm Hyper API keys.",
            placeholder: "Paste API key…",
            injection: .environment(key: apiKeyEnvironmentKey),
            requiresManualCookieSource: false,
            cookieName: nil),
        authDetector: { environment, _ in Self.apiKey(environment: environment) == nil ? [] : ["api"] },
        missingCredentialMessage: { _ in "Sign in to hyper.charm.land or configure a Charm Hyper API key." },
        selectedAccountSourceModeResolver: { base, account, _ in
            base == .auto && account != nil ? .api : base
        })

    public static func apiKey(environment: [String: String]) -> String? {
        guard let raw = environment[self.apiKeyEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        return raw
    }

    private static var browserCookieOrder: BrowserCookieImportOrder? {
        #if os(macOS)
        [.chrome]
        #else
        nil
        #endif
    }

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .hyper,
            menuBarMetrics: .automaticOnly,
            settingsSection: .init(HyperProviderSettingsKey.self, cookieSettings: HyperProviderSettings.self),
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .hyper,
                displayName: "Charm Hyper",
                sessionLabel: "Balance",
                weeklyLabel: "Balance",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Charm Hyper balance",
                cliName: "hyper",
                defaultEnabled: false,
                widgetSelectable: false,
                balanceOnly: true,
                browserCookieOrder: self.browserCookieOrder,
                dashboardURL: "https://hyper.charm.land",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .hyper),
                iconResourceName: "ProviderIcon-hyper",
                color: ProviderColor(hex: 0xFF60FF),
                confettiPalette: [ProviderColor(hex: 0xFF60FF), ProviderColor(hex: 0xFFFFFF)]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Charm Hyper cost history is not available via API." }),
            presentation: ProviderUsagePresentation(
                costPresenter: { _ in ProviderCostPresentation(showsGenericFallback: false, menuCardStyle: .hidden) }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                    [ScriptFetchStrategy(
                        id: "hyper.js",
                        provider: .hyper,
                        bundledPlugin: "hyper",
                        sourceLabel: context.sourceMode.rawValue,
                        kind: context.sourceMode == .web ? .web : .apiToken,
                        resolveValues: { context in
                            .init(
                                settings: ["SOURCE_MODE": context.sourceMode.rawValue],
                                secrets: Self.apiKey(environment: context.env)
                                    .map { [Self.apiKeyEnvironmentKey: $0] } ?? [:])
                        },
                        isEnabled: { _ in true })]
                })),
            cli: ProviderCLIConfig(
                name: "hyper",
                versionDetector: nil,
                browserSupportExemption: { sourceMode, environment, settings in
                    if settings?[HyperProviderSettingsKey.self]?.cookieSource == .manual {
                        return true
                    }
                    guard sourceMode == .auto, let environment else { return false }
                    return Self.apiKey(environment: environment) != nil
                }))
    }
}
