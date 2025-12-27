import CodexBarCore
import Foundation

struct ClaudeUsageStrategy: Equatable, Sendable {
    let dataSource: ClaudeUsageDataSource
    let useWebExtras: Bool
}

struct ClaudeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .claude
    let style: IconStyle = .claude

    @MainActor
    func settingsToggles(context: ProviderSettingsContext) -> [ProviderSettingsToggleDescriptor] {
        let id = "claude.webExtras"
        let metadata = context.store.metadata(for: .claude)
        let browserOrder = metadata.browserCookieOrder

        let statusText: () -> String? = { context.statusText(id) }

        var subtitleLines = [
            "Uses \(browserOrder?.shortLabel ?? "browser") session cookies to add extra dashboard fields " +
                "on top of OAuth.",
            "Adds extra usage spend/limit.",
        ]
        if let browserOrder {
            subtitleLines.append("\(browserOrder.displayLabel).")
        }

        let toggle = ProviderSettingsToggleDescriptor(
            id: id,
            title: "Augment Claude via web",
            subtitle: subtitleLines.joined(separator: " "),
            binding: context.boolBinding(\.claudeWebExtrasEnabled),
            statusText: statusText,
            actions: [],
            isVisible: { context.settings.claudeUsageDataSource == .cli },
            onChange: { enabled in
                if !enabled {
                    context.setStatusText(id, nil)
                }
            },
            onAppDidBecomeActive: nil,
            onAppearWhenEnabled: {
                await Self.refreshWebExtrasStatus(context: context, id: id)
            })

        return [toggle]
    }

    @MainActor
    static func usageStrategy(
        settings: SettingsStore,
        hasWebSession: () -> Bool = { ClaudeWebAPIFetcher.hasSessionKey() }) -> ClaudeUsageStrategy
    {
        if settings.debugMenuEnabled {
            let dataSource = settings.claudeUsageDataSource
            if dataSource == .oauth {
                return ClaudeUsageStrategy(dataSource: dataSource, useWebExtras: false)
            }
            let hasSession = hasWebSession()
            if dataSource == .web, !hasSession {
                return ClaudeUsageStrategy(dataSource: .cli, useWebExtras: false)
            }
            let useWebExtras = dataSource == .cli && settings.claudeWebExtrasEnabled && hasSession
            return ClaudeUsageStrategy(dataSource: dataSource, useWebExtras: useWebExtras)
        }

        let hasSession = hasWebSession()
        let dataSource: ClaudeUsageDataSource = hasSession ? .web : .cli
        return ClaudeUsageStrategy(dataSource: dataSource, useWebExtras: false)
    }

    func makeFetch(context: ProviderBuildContext) -> @Sendable () async throws -> UsageSnapshot {
        {
            let strategy = await MainActor.run { Self.usageStrategy(settings: context.settings) }

            let fetcher: any ClaudeUsageFetching = if context.claudeFetcher is ClaudeUsageFetcher {
                ClaudeUsageFetcher(dataSource: strategy.dataSource, useWebExtras: strategy.useWebExtras)
            } else {
                context.claudeFetcher
            }

            let usage = try await fetcher.loadLatestUsage(model: "sonnet")
            return UsageSnapshot(
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

    // MARK: - Web extras status

    @MainActor
    private static func refreshWebExtrasStatus(context: ProviderSettingsContext, id: String) async {
        let expectedEmail = context.store.snapshot(for: .claude)?.accountEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        context.setStatusText(id, "Checking Claude cookies…")
        let status = await Self.loadClaudeWebStatus(expectedEmail: expectedEmail)
        context.setStatusText(id, status)
    }

    private static func loadClaudeWebStatus(expectedEmail: String?) async -> String {
        await Task.detached(priority: .utility) {
            do {
                let info = try ClaudeWebAPIFetcher.sessionKeyInfo()
                var parts = ["Using \(info.sourceLabel) cookies (\(info.cookieCount))."]

                do {
                    let usage = try await ClaudeWebAPIFetcher.fetchUsage(using: info)
                    if let rawEmail = usage.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !rawEmail.isEmpty
                    {
                        if let expectedEmail, !expectedEmail.isEmpty {
                            let matches = rawEmail.lowercased() == expectedEmail.lowercased()
                            let matchText = matches ? "matches Claude" : "does not match Claude"
                            parts.append("Signed in as \(rawEmail) (\(matchText)).")
                        } else {
                            parts.append("Signed in as \(rawEmail).")
                        }
                    }
                } catch {
                    parts.append("Signed-in status unavailable: \(error.localizedDescription)")
                }

                return parts.joined(separator: " ")
            } catch {
                return "Browser cookie import failed: \(error.localizedDescription)"
            }
        }.value
    }
}
