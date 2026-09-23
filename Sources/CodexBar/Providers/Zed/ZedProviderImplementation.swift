import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct ZedProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .zed

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.zedCookieSource
        _ = settings.zedCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .init(
            context.settings.zedSettingsSnapshot(tokenOverride: context.tokenOverride),
            for: ZedProviderSettingsKey.self)
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.zedCookieSource.rawValue },
            set: { raw in
                context.settings.zedCookieSource = ProviderCookieSource(rawValue: raw) ?? .off
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: true,
            keychainDisabled: context.settings.debugDisableKeychainAccess)
        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.zedCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "Uses a zed.dev browser session for spend and predictions; " +
                    "editor-only cycle and invoice data are unavailable.",
                manual: "Uses a pasted zed.dev Cookie for spend and predictions; " +
                    "editor-only cycle and invoice data are unavailable.",
                off: "Uses editor login for predictions, billing cycle, and invoices; browser spend is off.")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "zed-cookie-source",
                title: "Cookie source",
                subtitle: "Choose the editor source or a separate browser session for token spend.",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: { ProviderCookieSourceUI.cachedTrailingText(provider: .zed) }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "zed-cookie",
                title: "Zed cookie",
                subtitle: "Paste the Cookie request header from zed.dev.",
                kind: .secure,
                placeholder: "Cookie: …",
                binding: context.stringBinding(\.zedCookieHeader),
                actions: [],
                isVisible: { context.settings.zedCookieSource == .manual },
                onActivate: nil),
        ]
    }
}

extension SettingsStore {
    var zedCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .zed)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .zed) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .zed, field: "cookieHeader", value: newValue)
        }
    }

    var zedCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .zed, fallback: .off) }
        set {
            self.updateProviderConfig(provider: .zed) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .zed, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func zedSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> CookieProviderSettings {
        self.resolvedCookieSettings(
            provider: .zed,
            configuredSource: self.zedCookieSource,
            configuredHeader: self.zedCookieHeader,
            tokenOverride: tokenOverride)
    }
}
