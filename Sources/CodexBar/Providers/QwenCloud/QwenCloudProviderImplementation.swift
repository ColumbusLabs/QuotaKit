import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct QwenCloudProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .qwencloud

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            context.store.sourceLabel(for: context.provider)
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.qwenCloudCookieSource
        _ = settings.qwenCloudCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        _ = context
        return .qwenCloud(context.settings.qwenCloudSettingsSnapshot())
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.qwenCloudCookieSource.rawValue },
            set: { raw in
                context.settings.qwenCloudCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)
        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.qwenCloudCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                subtitles: ProviderCookieSourceUI.Subtitles(
                    auto: ProviderCookieSourceUI.browserImportSubtitle(
                        L("Automatically imports browser cookies for %@.", "Qwen Cloud"),
                        provider: .qwencloud),
                    manual: L("Paste a Cookie header from %@.", "home.qwencloud.com"),
                    off: L("%@ cookies are disabled.", "Qwen Cloud")))
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "qwen-cloud-cookie-source",
                title: "Cookie source",
                subtitle: ProviderCookieSourceUI.browserImportSubtitle(
                    L("Automatically imports browser cookies for %@.", "Qwen Cloud"),
                    provider: .qwencloud),
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.loadForDisplay(provider: .qwencloud) else { return nil }
                    let when = entry.storedAt.relativeDescription()
                    return "Cached: \(entry.sourceLabel) • \(when)"
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "qwen-cloud-cookie",
                title: "Cookie header",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: ...",
                binding: context.stringBinding(\.qwenCloudCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "qwen-cloud-open-dashboard",
                        title: "Open Token Plan",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            NSWorkspace.shared.open(QwenCloudUsageFetcher.dashboardURL)
                        }),
                ],
                isVisible: {
                    context.settings.qwenCloudCookieSource == .manual
                },
                onActivate: nil),
        ]
    }
}
