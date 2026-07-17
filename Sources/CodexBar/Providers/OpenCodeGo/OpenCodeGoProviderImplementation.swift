import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct OpenCodeGoProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .opencodego

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.opencodegoCookieSource
        _ = settings.opencodegoCookieHeader
        _ = settings.opencodegoWorkspaceID
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .opencodego(context.settings.opencodegoSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        guard support.requiresManualCookieSource else { return true }
        if !context.settings.tokenAccounts(for: context.provider).isEmpty { return true }
        return context.settings.opencodegoCookieSource == .manual
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.opencodegoCookieSource != .manual {
            settings.opencodegoCookieSource = .manual
        }
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.opencodegoCookieSource.rawValue },
            set: { raw in
                context.settings.opencodegoCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.opencodegoCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "Automatic imports browser cookies from opencode.ai.",
                manual: "Paste a Cookie header captured from the billing page.",
                off: "OpenCode Go cookies are disabled.")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "opencodego-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies from opencode.ai.",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    OpenCodeProviderUI.cachedCookieTrailingText(
                        provider: .opencodego,
                        cookieSource: context.settings.opencodegoCookieSource)
                },
                trailingActions: [
                    ProviderSettingsActionDescriptor(
                        id: "opencodego-reimport-cookie",
                        title: "↻",
                        style: .bordered,
                        isVisible: nil,
                        perform: {
                            CookieHeaderCache.clear(provider: .opencodego)
                            #if os(macOS)
                            do {
                                let session = try OpenCodeCookieImporter.importSession(
                                    browserDetection: BrowserDetection(),
                                    preferredBrowsers: [])
                                CookieHeaderCache.store(
                                    provider: .opencodego,
                                    cookieHeader: session.cookieHeader,
                                    sourceLabel: session.sourceLabel)
                                context.setStatusText("opencodego-cookie-status", "✅ Refreshed from \(session.sourceLabel)")
                            } catch {
                                context.setStatusText("opencodego-cookie-status", "Cache cleared. Will re-import on next refresh.")
                            }
                            #endif
                            await context.store.refreshProvider(.opencodego, allowDisabled: true)
                        }),
                ]),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "opencodego-workspace-id",
                title: "Workspace ID",
                subtitle: "Optional override if workspace lookup fails.",
                kind: .plain,
                placeholder: "wrk_…",
                binding: context.stringBinding(\.opencodegoWorkspaceID),
                actions: [],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
