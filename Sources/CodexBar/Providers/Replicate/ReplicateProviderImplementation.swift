import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct ReplicateProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .replicate

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.replicateCookieSource
        _ = settings.replicateCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .replicate(context.settings.replicateSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        guard support.requiresManualCookieSource else { return true }
        if !context.settings.tokenAccounts(for: context.provider).isEmpty { return true }
        return context.settings.replicateCookieSource == .manual
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.replicateCookieSource != .manual {
            settings.replicateCookieSource = .manual
        }
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let binding = Binding(
            get: { context.settings.replicateCookieSource.rawValue },
            set: { raw in
                context.settings.replicateCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        return [
            ProviderSettingsPickerDescriptor(
                id: "replicate-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports Chrome cookies from replicate.com.",
                dynamicSubtitle: {
                    ProviderCookieSourceUI.subtitle(
                        source: context.settings.replicateCookieSource,
                        keychainDisabled: context.settings.debugDisableKeychainAccess,
                        auto: "Automatic imports Chrome cookies from replicate.com.",
                        manual: "Paste a Cookie header captured from the billing page.",
                        off: "Replicate cookies are disabled.")
                },
                binding: binding,
                options: ProviderCookieSourceUI.options(
                    allowsOff: false,
                    keychainDisabled: context.settings.debugDisableKeychainAccess),
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.loadForDisplay(provider: .replicate) else { return nil }
                    return "Cached: \(entry.sourceLabel) • \(entry.storedAt.relativeDescription())"
                },
                trailingActions: [
                    ProviderCookieRefreshAction.descriptor(
                        provider: .replicate,
                        cookieSource: { context.settings.replicateCookieSource },
                        context: context),
                ]),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "replicate-cookie-header",
                title: "Cookie header",
                subtitle: "Paste the Cookie header from a billing-page request. It must contain sessionid.",
                kind: .secure,
                placeholder: "sessionid=…; csrftoken=…",
                binding: context.stringBinding(\.replicateCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "replicate-open-billing",
                        title: "Open Replicate Billing",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            NSWorkspace.shared.open(URL(string: "https://replicate.com/account/billing")!)
                        }),
                ],
                isVisible: { context.settings.replicateCookieSource == .manual },
                onActivate: nil),
        ]
    }
}
