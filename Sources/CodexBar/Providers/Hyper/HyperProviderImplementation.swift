import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct HyperProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .hyper

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "Session or API key" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.hyperCookieSource
        _ = settings[providerConfig: .hyper, field: .apiKey]
        _ = settings[providerConfig: .hyper, field: .cookieHeader]
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .hyper(context.settings.hyperSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.hyperCookieSource.rawValue },
            set: { raw in
                context.settings.hyperCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let options = ProviderCookieSourceUI.options(
            allowsOff: true,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let subtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.hyperCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "Automatically imports a Chrome session cookie, then falls back to an API key.",
                manual: "Uses a pasted hyper.charm.land Cookie header, then falls back to an API key.",
                off: "Browser cookies are disabled; an API key is still used when available.")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "hyper-cookie-source",
                title: "Cookie source",
                subtitle: "Choose how QuotaKit reads your Charm Hyper session.",
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
                id: "hyper-cookie",
                title: "Charm Hyper Cookie",
                subtitle: "Paste a Cookie request header from hyper.charm.land. Stored securely in QuotaKit settings.",
                kind: .secure,
                placeholder: "Cookie: …",
                binding: context.providerConfigBinding(.cookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "hyper-open-dashboard",
                        title: "Open Charm Hyper",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://hyper.charm.land") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { context.settings.hyperCookieSource == .manual },
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "hyper-api-key",
                title: "API key",
                subtitle: "Used when browser cookies are unavailable. Saved in QuotaKit settings, or set " +
                    "HYPER_API_KEY.",
                kind: .secure,
                placeholder: "Paste API key…",
                binding: context.providerConfigBinding(.apiKey),
                actions: [],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}

extension SettingsStore {
    var hyperCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .hyper, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .hyper) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .hyper, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func hyperSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> HyperProviderSettings {
        let resolved: CookieProviderSettings = self.resolvedCookieSettings(
            provider: .hyper,
            configuredSource: self.hyperCookieSource,
            configuredHeader: self[providerConfig: .hyper, field: .cookieHeader],
            tokenOverride: tokenOverride)
        return HyperProviderSettings(
            cookieSource: resolved.cookieSource,
            manualCookieHeader: resolved.manualCookieHeader)
    }
}
