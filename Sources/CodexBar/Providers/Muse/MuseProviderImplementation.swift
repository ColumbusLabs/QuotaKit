import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct MuseProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .muse

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "oauth" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.museWebTeamID
    }

    /// The shared cookie snapshot defaults to Automatic; Muse reads a browser session only after an explicit choice.
    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        ProviderSettingsSnapshotContribution(
            MuseProviderSettings(
                cookieSource: context.settings.museCookieSource,
                manualCookieHeader: context.settings.museCookieHeader,
                webTeamID: context.settings.museWebTeamID.isEmpty ? nil : context.settings.museWebTeamID),
            for: MuseProviderSettingsKey.self)
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        MuseCredentials.hasLogin(environment: context.environment)
    }

    /// The dev.meta.ai session only fills quotas that the Muse login response leaves out.
    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let rows = context.store.snapshot(for: .muse)?.details.first { $0.title == "Browser teams" }?.rows ?? []
        var options = [ProviderSettingsPickerOption(id: "", title: "Choose a team…")]
        for row in rows where !row.value.isEmpty && row.value.allSatisfy(\.isNumber) {
            guard !options.contains(where: { $0.id == row.value }) else { continue }
            options.append(.init(id: row.value, title: "\(row.label) (\(row.value))"))
        }
        let selected = context.settings.museWebTeamID
        if !selected.isEmpty, !options.contains(where: { $0.id == selected }) {
            options.append(.init(id: selected, title: "\(selected) (unavailable)"))
        }
        let cookieBinding = Binding(
            get: { context.settings.museCookieSource.rawValue },
            set: { raw in
                context.settings.museCookieSource = ProviderCookieSource(rawValue: raw) ?? .off
            })
        return [
            ProviderSettingsPickerDescriptor(
                id: "muse-cookie-source",
                title: "Cookie source",
                subtitle: ProviderCookieSourceUI.browserImportSubtitle(
                    L("Automatically imports browser cookies."),
                    provider: .muse),
                dynamicSubtitle: {
                    ProviderCookieSourceUI.subtitle(
                        source: context.settings.museCookieSource,
                        keychainDisabled: context.settings.debugDisableKeychainAccess,
                        subtitles: ProviderCookieSourceUI.Subtitles(
                            auto: ProviderCookieSourceUI.browserImportSubtitle(
                                L("Automatically imports browser cookies."),
                                provider: .muse),
                            manual: L("Paste a Cookie header from %@.", "dev.meta.ai"),
                            off: L("%@ cookies are disabled.", "Muse Code")))
                },
                binding: cookieBinding,
                options: ProviderCookieSourceUI.options(
                    allowsOff: true,
                    keychainDisabled: context.settings.debugDisableKeychainAccess),
                isVisible: nil,
                onChange: nil),
            ProviderSettingsPickerDescriptor(
                id: "muse-web-team-id",
                title: "Browser team",
                subtitle: "Refresh Muse Code to load teams when the login omits quotas. "
                    + "Choose the web team's quota to display, then refresh.",
                binding: context.stringBinding(\.museWebTeamID),
                options: options,
                isVisible: { context.settings.museCookieSource != .off },
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "muse-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: llama_dev_sess=...",
                binding: context.stringBinding(\.museCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "muse-open-usage",
                        title: "Open dev.meta.ai",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://dev.meta.ai/usage") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { context.settings.museCookieSource == .manual },
                onActivate: nil),
        ]
    }
}
