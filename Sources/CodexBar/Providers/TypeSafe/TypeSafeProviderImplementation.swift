import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct TypeSafeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .typesafe

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        let cookies: TypeSafeProviderSettings = context.settings.resolvedCookieSettings(
            provider: self.id,
            configuredSource: context.settings.typesafeCookieSource,
            configuredHeader: context.settings.typesafeCookieHeader,
            tokenOverride: context.tokenOverride)
        return .typesafe(cookies)
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        !support.requiresManualCookieSource || context.settings.typesafeCookieSource == .manual
            || !context.settings.tokenAccounts(for: .typesafe).isEmpty
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        settings.typesafeCookieSource = .manual
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let binding = Binding(
            get: { context.settings.typesafeCookieSource.rawValue },
            set: { raw in
                context.settings.typesafeCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        return [ProviderSettingsPickerDescriptor(
            id: "typesafe-cookie-source",
            title: "Cookie source",
            subtitle: L("Automatically imports browser cookies for %@.", "typesafe.ai"),
            dynamicSubtitle: {
                ProviderCookieSourceUI.subtitle(
                    source: context.settings.typesafeCookieSource,
                    keychainDisabled: context.settings.debugDisableKeychainAccess,
                    subtitles: ProviderCookieSourceUI.Subtitles(
                        auto: L("Automatically imports browser cookies for %@.", "typesafe.ai"),
                        manual: L("Paste a Cookie header captured from %@.", "typesafe.ai"),
                        off: L("%@ cookies are disabled.", "TypeSafe")))
            },
            binding: binding,
            options: ProviderCookieSourceUI.options(
                allowsOff: false,
                keychainDisabled: context.settings.debugDisableKeychainAccess),
            isVisible: nil,
            onChange: nil,
            trailingText: {
                ProviderCookieRefreshAction.trailingText(
                    provider: .typesafe,
                    cookieSource: context.settings.typesafeCookieSource,
                    context: context)
            },
            trailingActions: [
                ProviderCookieRefreshAction.descriptor(
                    provider: .typesafe,
                    cookieSource: { context.settings.typesafeCookieSource },
                    context: context),
            ])]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [ProviderSettingsFieldDescriptor(
            id: "typesafe-cookie-header",
            title: "Cookie header",
            subtitle: "Paste the Cookie header from a billing-page request.",
            kind: .secure,
            placeholder: "Cookie: …",
            binding: context.providerConfigBinding(.cookieHeader),
            actions: [ProviderSettingsActionDescriptor(
                id: "typesafe-open-billing",
                title: "Open TypeSafe Billing",
                style: .link,
                isVisible: nil,
                perform: {
                    if let url = URL(string: "https://console.typesafe.ai/settings/billing") {
                        NSWorkspace.shared.open(url)
                    }
                })],
            isVisible: { context.settings.typesafeCookieSource == .manual },
            onActivate: nil)]
    }
}
