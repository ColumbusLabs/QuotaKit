import CodexBarCore
import Foundation

struct CodexProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .codex
    let style: IconStyle = .codex

    func makeFetch(context: ProviderBuildContext) -> @Sendable () async throws -> UsageSnapshot {
        { try await context.codexFetcher.loadLatestUsage() }
    }

    @MainActor
    func settingsToggles(context: ProviderSettingsContext) -> [ProviderSettingsToggleDescriptor] {
        let id = "codex.openaiWeb"

        let statusText: () -> String? = {
            context.statusText(id) ??
                context.store.openAIDashboardCookieImportStatus ??
                context.store.lastOpenAIDashboardError
        }

        let fixFullDiskAccess = ProviderSettingsActionDescriptor(
            id: "\(id).fixFullDiskAccess",
            title: "Fix: enable Full Disk Access…",
            style: .bordered,
            isVisible: {
                guard let status = statusText(), !status.isEmpty else { return false }
                return Self.needsOpenAIWebFullDiskAccess(status: status)
            },
            perform: {
                context.requestConfirmation(
                    ProviderSettingsConfirmation(
                        title: "Enable Full Disk Access",
                        message: [
                            "CodexBar needs Full Disk Access to read Safari cookies (required for OpenAI web).",
                            "System Settings → Privacy & Security → Full Disk Access → add/enable CodexBar.",
                            "Then re-toggle “Use Codex via web” to import cookies again.",
                        ].joined(separator: "\n"),
                        confirmTitle: "Open System Settings",
                        onConfirm: {
                            SystemSettingsLinks.openFullDiskAccess()
                            context.setStatusText(id, "Waiting for Full Disk Access…")
                        }))
            })

        let toggle = ProviderSettingsToggleDescriptor(
            id: id,
            title: "Use Codex via web",
            subtitle: [
                "Uses your Safari/Chrome/Firefox session cookies for Codex usage + credits.",
                "Adds Code review + Usage breakdown.",
                "Safari → Chrome → Firefox.",
            ].joined(separator: " "),
            binding: context.boolBinding(\.openAIDashboardEnabled),
            statusText: statusText,
            actions: [fixFullDiskAccess],
            isVisible: nil,
            onChange: { enabled in
                if enabled {
                    context.setStatusText(id, "Importing cookies…")
                    await context.store.importOpenAIDashboardBrowserCookiesNow()
                    context.setStatusText(id, nil)
                } else {
                    context.setStatusText(id, nil)
                }
            },
            onAppDidBecomeActive: {
                guard context.settings.openAIDashboardEnabled else { return }

                guard let status = statusText(), !status.isEmpty else { return }
                guard Self.needsOpenAIWebFullDiskAccess(status: status) else { return }

                let now = Date()
                if let last = context.lastAppActiveRunAt(id), now.timeIntervalSince(last) < 5 {
                    return
                }
                context.setLastAppActiveRunAt(id, now)

                context.setStatusText(id, "Re-checking Full Disk Access…")
                await context.store.importOpenAIDashboardBrowserCookiesNow()
                context.setStatusText(id, nil)
            },
            onAppearWhenEnabled: nil)

        return [toggle]
    }

    private static func needsOpenAIWebFullDiskAccess(status: String) -> Bool {
        let s = status.lowercased()
        return s.contains("full disk access") && s.contains("safari")
    }
}
