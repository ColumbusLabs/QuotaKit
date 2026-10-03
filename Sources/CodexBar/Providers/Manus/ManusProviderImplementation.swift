import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct ManusProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .manus
    let supportsLoginFlow: Bool = true

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func runLoginFlow(context _: ProviderLoginContext) async -> Bool {
        if let url = URL(string: "https://manus.im") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.manusCookieSource
        _ = settings.manusManualCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .manus(context.settings.manusSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        guard support.requiresManualCookieSource else { return true }
        if !context.settings.tokenAccounts(for: context.provider).isEmpty { return true }
        return context.settings.manusCookieSource == .manual
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.manusCookieSource != .manual {
            settings.manusCookieSource = .manual
        }
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.manusCookieSource.rawValue },
            set: { raw in
                context.settings.manusCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let options = ProviderCookieSourceUI.options(
            allowsOff: true,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let subtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.manusCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                subtitles: ProviderCookieSourceUI.Subtitles(
                    auto: ProviderCookieSourceUI.browserImportSubtitle(
                        L("Automatically imports browser session cookies."),
                        provider: .manus),
                    manual: L("Paste the %@ value or a full Cookie header.", "session_id"),
                    off: L("%@ cookies are disabled.", "Manus")))
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "manus-cookie-source",
                title: "Cookie source",
                subtitle: ProviderCookieSourceUI.browserImportSubtitle(
                    L("Automatically imports browser session cookies."),
                    provider: .manus),
                dynamicSubtitle: subtitle,
                binding: cookieBinding,
                options: options,
                isVisible: nil,
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "manus-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "session_id=...\n\nor paste just the session_id value",
                binding: context.stringBinding(\.manusManualCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "manus-open-dashboard",
                        title: "Open Manus",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://manus.im") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { context.settings.manusCookieSource == .manual },
                onActivate: nil),
        ]
    }
}
