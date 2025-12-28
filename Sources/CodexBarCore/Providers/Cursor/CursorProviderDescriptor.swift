import CodexBarMacroSupport
import Foundation
import SweetCookieKit

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum CursorProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .cursor,
            metadata: ProviderMetadata(
                id: .cursor,
                displayName: "Cursor",
                sessionLabel: "Plan",
                weeklyLabel: "On-Demand",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: true,
                creditsHint: "On-demand usage beyond included plan limits.",
                toggleTitle: "Show Cursor usage",
                cliName: "cursor",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: Browser.defaultImportOrder,
                dashboardURL: "https://cursor.com/dashboard?tab=usage",
                statusPageURL: "https://status.cursor.com",
                statusLinkURL: nil),
            branding: ProviderBranding(
                iconStyle: .cursor,
                iconResourceName: "ProviderIcon-cursor",
                color: ProviderColor(red: 0 / 255, green: 191 / 255, blue: 165 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Cursor cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .cli],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [CursorStatusFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "cursor",
                versionDetector: nil))
    }
}

struct CursorStatusFetchStrategy: ProviderFetchStrategy {
    let id: String = "cursor.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_: ProviderFetchContext) async -> Bool { true }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let probe = CursorStatusProbe()
        let snap = try await probe.fetch()
        return self.makeResult(
            usage: snap.toUsageSnapshot(),
            sourceLabel: "web")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
