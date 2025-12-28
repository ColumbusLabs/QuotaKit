import CodexBarMacroSupport
import Foundation
import SweetCookieKit

@ProviderDescriptorRegistration
public enum ClaudeProviderDescriptor {
    public static let descriptor: ProviderDescriptor = .init(
        id: .claude,
        metadata: ProviderMetadata(
            id: .claude,
            displayName: "Claude",
            sessionLabel: "Session",
            weeklyLabel: "Weekly",
            opusLabel: "Sonnet",
            supportsOpus: true,
            supportsCredits: false,
            creditsHint: "",
            toggleTitle: "Show Claude Code usage",
            cliName: "claude",
            defaultEnabled: false,
            browserCookieOrder: Browser.defaultImportOrder,
            dashboardURL: "https://console.anthropic.com/settings/billing",
            subscriptionDashboardURL: "https://claude.ai/settings/usage",
            statusPageURL: "https://status.claude.com/"),
        branding: ProviderBranding(
            iconStyle: .claude,
            iconResourceName: "ProviderIcon-claude",
            color: ProviderColor(red: 204 / 255, green: 124 / 255, blue: 94 / 255)),
        tokenCost: ProviderTokenCostConfig(
            supportsTokenCost: true,
            noDataMessage: Self.noDataMessage),
        sourceLabel: "auto",
        cli: ProviderCLIConfig(
            name: "claude",
            sourceLabel: "claude",
            versionDetector: { ClaudeUsageFetcher().detectVersion() },
            sourceModes: [.auto, .web, .cli, .oauth]),
        fetchPipeline: ProviderFetchPipeline(resolveStrategies: Self.resolveStrategies))

    private static func resolveStrategies(context: ProviderFetchContext) async -> [any ProviderFetchStrategy] {
        switch context.runtime {
        case .cli:
            switch context.sourceMode {
            case .oauth:
                return [ClaudeOAuthFetchStrategy()]
            case .web:
                return [ClaudeWebFetchStrategy()]
            case .cli:
                return [ClaudeCLIFetchStrategy(useWebExtras: false)]
            case .auto:
                return [ClaudeWebFetchStrategy(), ClaudeCLIFetchStrategy(useWebExtras: false)]
            }
        case .app:
            let hasWebSession = ClaudeWebAPIFetcher.hasSessionKey()
            let hasOAuthCredentials = (try? ClaudeOAuthCredentialsStore.load()) != nil
            let settings = context.settings
            let debugMenuEnabled = settings?.debugMenuEnabled ?? false
            let selected = settings?.claudeUsageDataSource ?? .web
            let webExtrasEnabled = settings?.claudeWebExtrasEnabled ?? false
            let strategy = Self.resolveUsageStrategy(
                debugMenuEnabled: debugMenuEnabled,
                selectedDataSource: selected,
                webExtrasEnabled: webExtrasEnabled,
                hasWebSession: hasWebSession,
                hasOAuthCredentials: hasOAuthCredentials)
            switch strategy.dataSource {
            case .oauth:
                return [ClaudeOAuthFetchStrategy()]
            case .web:
                return [ClaudeWebFetchStrategy()]
            case .cli:
                return [ClaudeCLIFetchStrategy(useWebExtras: strategy.useWebExtras)]
            }
        }
    }

    private static func noDataMessage() -> String {
        "No Claude usage logs found in ~/.config/claude/projects or ~/.claude/projects."
    }

    public static func resolveUsageStrategy(
        debugMenuEnabled: Bool,
        selectedDataSource: ClaudeUsageDataSource,
        webExtrasEnabled: Bool,
        hasWebSession: Bool,
        hasOAuthCredentials: Bool) -> ClaudeUsageStrategy
    {
        if debugMenuEnabled {
            if selectedDataSource == .oauth {
                return ClaudeUsageStrategy(dataSource: .oauth, useWebExtras: false)
            }
            if selectedDataSource == .web, !hasWebSession {
                return ClaudeUsageStrategy(dataSource: .cli, useWebExtras: false)
            }
            let useWebExtras = selectedDataSource == .cli && webExtrasEnabled && hasWebSession
            return ClaudeUsageStrategy(dataSource: selectedDataSource, useWebExtras: useWebExtras)
        }

        if hasOAuthCredentials {
            return ClaudeUsageStrategy(dataSource: .oauth, useWebExtras: false)
        }
        if hasWebSession {
            return ClaudeUsageStrategy(dataSource: .web, useWebExtras: false)
        }
        return ClaudeUsageStrategy(dataSource: .cli, useWebExtras: false)
    }
}

public struct ClaudeUsageStrategy: Equatable, Sendable {
    public let dataSource: ClaudeUsageDataSource
    public let useWebExtras: Bool
}

struct ClaudeOAuthFetchStrategy: ProviderFetchStrategy {
    let id: String = "claude.oauth"
    let kind: ProviderFetchKind = .oauth

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        (try? ClaudeOAuthCredentialsStore.load()) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let fetcher = ClaudeUsageFetcher(dataSource: .oauth, useWebExtras: false)
        let usage = try await fetcher.loadLatestUsage(model: "sonnet")
        return ProviderFetchResult(
            usage: Self.snapshot(from: usage),
            credits: nil,
            dashboard: nil,
            sourceOverride: nil)
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    fileprivate static func snapshot(from usage: ClaudeUsageSnapshot) -> UsageSnapshot {
        UsageSnapshot(
            primary: usage.primary,
            secondary: usage.secondary,
            tertiary: usage.opus,
            providerCost: usage.providerCost,
            updatedAt: usage.updatedAt,
            accountEmail: usage.accountEmail,
            accountOrganization: usage.accountOrganization,
            loginMethod: usage.loginMethod)
    }
}

struct ClaudeWebFetchStrategy: ProviderFetchStrategy {
    let id: String = "claude.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        ClaudeWebAPIFetcher.hasSessionKey()
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let fetcher = ClaudeUsageFetcher(dataSource: .web, useWebExtras: false)
        let usage = try await fetcher.loadLatestUsage(model: "sonnet")
        return ProviderFetchResult(
            usage: ClaudeOAuthFetchStrategy.snapshot(from: usage),
            credits: nil,
            dashboard: nil,
            sourceOverride: nil)
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        guard context.sourceMode == .auto else { return false }
        if let fetchError = error as? ClaudeWebAPIFetcher.FetchError {
            if case .noSessionKeyFound = fetchError { return true }
        }
        return false
    }
}

struct ClaudeCLIFetchStrategy: ProviderFetchStrategy {
    let id: String = "claude.cli"
    let kind: ProviderFetchKind = .cli
    let useWebExtras: Bool

    func isAvailable(_: ProviderFetchContext) async -> Bool { true }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let fetcher = ClaudeUsageFetcher(dataSource: .cli, useWebExtras: self.useWebExtras)
        let usage = try await fetcher.loadLatestUsage(model: "sonnet")
        return ProviderFetchResult(
            usage: ClaudeOAuthFetchStrategy.snapshot(from: usage),
            credits: nil,
            dashboard: nil,
            sourceOverride: nil)
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
