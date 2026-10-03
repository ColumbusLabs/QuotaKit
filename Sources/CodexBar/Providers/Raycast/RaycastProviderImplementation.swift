import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct RaycastProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .raycast

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.raycastCookieSource
        _ = settings.raycastCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .raycast(context.settings.raycastSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let binding = Binding(
            get: { context.settings.raycastCookieSource.rawValue },
            set: { raw in
                context.settings.raycastCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        return [ProviderSettingsPickerDescriptor(
            id: "raycast-cookie-source",
            title: "Cookie source",
            subtitle: ProviderCookieSourceUI.browserImportSubtitle(
                L("Automatically imports browser cookies for %@.", "www.raycast.com"),
                provider: .raycast),
            dynamicSubtitle: {
                ProviderCookieSourceUI.subtitle(
                    source: context.settings.raycastCookieSource,
                    keychainDisabled: context.settings.debugDisableKeychainAccess,
                    subtitles: ProviderCookieSourceUI.Subtitles(
                        auto: ProviderCookieSourceUI.browserImportSubtitle(
                            L("Automatically imports browser cookies for %@.", "www.raycast.com"),
                            provider: .raycast),
                        manual: L("Paste a Cookie header captured from %@.", "www.raycast.com"),
                        off: L("%@ cookies are disabled.", "Raycast")))
            },
            binding: binding,
            options: ProviderCookieSourceUI.options(
                allowsOff: true,
                keychainDisabled: context.settings.debugDisableKeychainAccess),
            isVisible: nil,
            onChange: nil,
            trailingText: {
                ProviderCookieRefreshAction.trailingText(
                    provider: .raycast,
                    cookieSource: context.settings.raycastCookieSource,
                    context: context)
            },
            trailingActions: [
                ProviderCookieRefreshAction.descriptor(
                    provider: .raycast,
                    cookieSource: { context.settings.raycastCookieSource },
                    context: context),
            ])]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [ProviderSettingsFieldDescriptor(
            id: "raycast-cookie-header",
            title: "Cookie header",
            subtitle: "Paste the Cookie header from a www.raycast.com/settings request. It must contain __raycast_session.",
            kind: .secure,
            placeholder: "__raycast_session=…; csrf_token=…",
            binding: context.providerConfigBinding(.cookieHeader),
            actions: [ProviderSettingsActionDescriptor(
                id: "raycast-open-settings",
                title: "Open Raycast Account",
                style: .link,
                isVisible: nil,
                perform: {
                    if let url = URL(string: "https://www.raycast.com/settings") {
                        NSWorkspace.shared.open(url)
                    }
                })],
            isVisible: { context.settings.raycastCookieSource == .manual },
            onActivate: nil)]
    }
}
