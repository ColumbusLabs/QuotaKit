import CodexBarMacroSupport
import Foundation
import SweetCookieKit

@ProviderDescriptorRegistration
public enum CodexProviderDescriptor {
    public static let descriptor: ProviderDescriptor = .init(
        id: .codex,
        metadata: ProviderMetadata(
            id: .codex,
            displayName: "Codex",
            sessionLabel: "Session",
            weeklyLabel: "Weekly",
            opusLabel: nil,
            supportsOpus: false,
            supportsCredits: true,
            creditsHint: "Credits unavailable; keep Codex running to refresh.",
            toggleTitle: "Show Codex usage",
            cliName: "codex",
            defaultEnabled: true,
            browserCookieOrder: Browser.defaultImportOrder,
            dashboardURL: "https://chatgpt.com/codex/settings/usage",
            statusPageURL: "https://status.openai.com/"),
        branding: ProviderBranding(
            iconStyle: .codex,
            iconResourceName: "ProviderIcon-codex",
            color: ProviderColor(red: 73 / 255, green: 163 / 255, blue: 176 / 255)),
        tokenCost: ProviderTokenCostConfig(
            supportsTokenCost: true,
            noDataMessage: Self.noDataMessage),
        sourceLabel: "auto",
        cli: ProviderCLIConfig(
            name: "codex",
            sourceLabel: "codex-cli",
            versionDetector: { ProviderVersionDetector.codexVersion() },
            sourceModes: [.auto, .web, .cli]),
        fetchPipeline: ProviderFetchPipeline(resolveStrategies: Self.resolveStrategies))

    private static func resolveStrategies(context: ProviderFetchContext) async -> [any ProviderFetchStrategy] {
        let cli = CodexCLIUsageStrategy()
        let web = CodexWebDashboardStrategy()
        switch context.sourceMode {
        case .web:
            return [web]
        case .cli, .oauth:
            return [cli]
        case .auto:
            if context.runtime == .cli {
                return [web, cli]
            }
            return [cli]
        }
    }

    private static func noDataMessage() -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let root = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return "\(trimmed)/sessions"
        } ?? "\(home)/.codex/sessions"
        return "No Codex sessions found in \(root)."
    }
}

struct CodexCLIUsageStrategy: ProviderFetchStrategy {
    let id: String = "codex.cli"
    let kind: ProviderFetchKind = .cli

    func isAvailable(_: ProviderFetchContext) async -> Bool { true }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let usage = try await context.fetcher.loadLatestUsage()
        let credits = await context.includeCredits ? (try? context.fetcher.loadLatestCredits()) : nil
        return ProviderFetchResult(
            usage: usage,
            credits: credits,
            dashboard: nil,
            sourceOverride: nil)
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
