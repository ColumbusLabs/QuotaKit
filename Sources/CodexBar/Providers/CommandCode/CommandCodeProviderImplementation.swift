import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct CommandCodeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .commandcode

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        guard support.requiresManualCookieSource else { return true }
        if !context.settings.tokenAccounts(for: context.provider).isEmpty { return true }
        return context.settings.commandcodeCookieSource == .manual
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.commandcodeCookieSource != .manual {
            settings.commandcodeCookieSource = .manual
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.commandcodeUsageDataSource
        _ = settings.commandcodeAPIKey
        _ = settings.commandcodeCookieSource
        _ = settings.commandcodeCookieHeader
    }

    @MainActor
    func sourceMode(context: ProviderSourceModeContext) -> ProviderSourceMode {
        context.settings.commandcodeUsageDataSource
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .commandcode(context.settings.commandcodeSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let usageBinding = Binding(
            get: { context.settings.commandcodeUsageDataSource.rawValue },
            set: { raw in
                context.settings.commandcodeUsageDataSource = ProviderSourceMode(rawValue: raw) ?? .auto
            })
        let cookieBinding = Binding(
            get: { context.settings.commandcodeCookieSource.rawValue },
            set: { raw in
                context.settings.commandcodeCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.commandcodeCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                subtitles: ProviderCookieSourceUI.Subtitles(
                    auto: ProviderCookieSourceUI.browserImportSubtitle(
                        L("Automatic imports browser cookies."),
                        provider: .commandcode),
                    manual: L("Paste a Cookie header or cURL capture from %@.", "Command Code"),
                    off: L("%@ cookies are disabled.", "Command Code")))
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "commandcode-usage-source",
                title: "Usage source",
                subtitle: "Auto uses the active saved session, otherwise an API key or browser cookies.",
                binding: usageBinding,
                options: [
                    ProviderSettingsPickerOption(id: ProviderSourceMode.auto.rawValue, title: "Auto"),
                    ProviderSettingsPickerOption(id: ProviderSourceMode.api.rawValue, title: "API key"),
                    ProviderSettingsPickerOption(id: ProviderSourceMode.web.rawValue, title: "Browser cookies"),
                ],
                isVisible: nil,
                onChange: nil),
            ProviderSettingsPickerDescriptor(
                id: "commandcode-cookie-source",
                title: "Cookie source",
                subtitle: ProviderCookieSourceUI.browserImportSubtitle(
                    L("Automatic imports browser cookies."),
                    provider: .commandcode),
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: { context.settings.commandcodeUsageDataSource != .api },
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "commandcode-api-key",
                title: "API key",
                subtitle: "Stored in the QuotaKit config file. You can also set COMMAND_CODE_API_KEY.",
                kind: .secure,
                placeholder: "API key",
                binding: context.binding(\.commandcodeAPIKey),
                actions: [],
                isVisible: { context.settings.commandcodeUsageDataSource != .web },
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "commandcode-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: …",
                binding: context.stringBinding(\.commandcodeCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "commandcode-open-settings",
                        title: "Open Command Code Settings",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://commandcode.ai/studio") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: {
                    context.settings.commandcodeUsageDataSource != .api &&
                        context.settings.commandcodeCookieSource == .manual
                },
                onActivate: { context.settings.ensureCommandCodeCookieLoaded() }),
        ]
    }
}
