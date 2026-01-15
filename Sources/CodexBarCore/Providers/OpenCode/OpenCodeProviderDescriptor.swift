import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum OpenCodeProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .opencode,
            metadata: ProviderMetadata(
                id: .opencode,
                displayName: "OpenCode",
                sessionLabel: "5-hour",
                weeklyLabel: "Weekly",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show OpenCode usage",
                cliName: "opencode",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: ProviderBrowserCookieDefaults.defaultImportOrder,
                dashboardURL: "https://opencode.ai",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .opencode,
                iconResourceName: "ProviderIcon-opencode",
                color: ProviderColor(red: 59 / 255, green: 130 / 255, blue: 246 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "OpenCode cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [OpenCodeUsageFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "opencode",
                versionDetector: nil))
    }
}

struct OpenCodeUsageFetchStrategy: ProviderFetchStrategy {
    let id: String = "opencode.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        guard context.settings?.opencode?.cookieSource != .off else { return false }
        return true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let cookieHeader = try Self.resolveCookieHeader(context: context)
        let snapshot = try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: cookieHeader,
            timeout: context.webTimeout)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "web")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveCookieHeader(context: ProviderFetchContext) throws -> String {
        if let settings = context.settings?.opencode, settings.cookieSource == .manual {
            if let header = CookieHeaderNormalizer.normalize(settings.manualCookieHeader) {
                return header
            }
            throw OpenCodeSettingsError.invalidCookie
        }

        #if os(macOS)
        let session = try OpenCodeCookieImporter.importSession(browserDetection: context.browserDetection)
        return session.cookieHeader
        #else
        throw OpenCodeSettingsError.missingCookie
        #endif
    }
}

enum OpenCodeSettingsError: LocalizedError {
    case missingCookie
    case invalidCookie

    var errorDescription: String? {
        switch self {
        case .missingCookie:
            "No OpenCode session cookies found in browsers."
        case .invalidCookie:
            "OpenCode cookie header is invalid."
        }
    }
}
