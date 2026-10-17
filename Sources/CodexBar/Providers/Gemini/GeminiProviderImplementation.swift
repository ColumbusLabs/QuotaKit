import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct GeminiProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .gemini
    let supportsLoginFlow: Bool = true

    @MainActor
    func presentation(context: ProviderPresentationContext) -> ProviderPresentation {
        let isWeb = context.settings.providerConfig(for: .gemini)?.source == .web
        return ProviderPresentation(
            showsVersionInSettings: !isWeb,
            detailLine: { context in
                isWeb ? "Gemini app" : ProviderPresentation.standardDetailLine(context: context)
            })
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.providerConfig(for: .gemini)?.source
        _ = settings.geminiCookieSource
        _ = settings.geminiCookieHeader
    }

    @MainActor
    func sourceMode(context: ProviderSourceModeContext) -> ProviderSourceMode {
        context.settings.providerConfig(for: .gemini)?.source == .web ? .web : .api
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        let cookieSettings: CookieProviderSettings = context.settings.resolvedCookieSettings(
            provider: .gemini,
            configuredSource: context.settings.geminiCookieSource,
            configuredHeader: context.settings.geminiCookieHeader,
            tokenOverride: context.tokenOverride)
        return .init(cookieSettings, for: GeminiProviderSettingsKey.self)
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.geminiCookieSource.rawValue },
            set: { raw in
                context.settings.geminiCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: true,
            keychainDisabled: context.settings.debugDisableKeychainAccess)
        let autoCookieSubtitle = L(
            "Supported browsers: %@. Use Manual for other browsers.",
            BrowserCookieImportSupport.browserNames(for: .gemini))
        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.geminiCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                subtitles: ProviderCookieSourceUI.Subtitles(
                    auto: autoCookieSubtitle,
                    manual: L("Paste a Cookie header from %@.", "gemini.google.com"),
                    off: L("%@ cookies are disabled.", "Gemini app")))
        }
        return [
            ProviderSettingsPickerDescriptor(
                id: "gemini-usage-source",
                title: "Usage source",
                subtitle: "Gemini app limits use your browser account and are separate from Gemini CLI quotas.",
                binding: Binding(
                    get: { context.settings.providerConfig(for: .gemini)?.source == .web ? "web" : "api" },
                    set: { value in
                        let isWeb = value == "web"
                        guard isWeb != (context.settings.providerConfig(for: .gemini)?.source == .web) else { return }
                        context.store.clearProviderState(.gemini)
                        context.settings.updateProviderConfig(provider: .gemini) {
                            $0.source = isWeb ? .web : .api
                        }
                    }),
                options: [.init(id: "api", title: "Gemini CLI"), .init(id: "web", title: "Gemini app")],
                isVisible: nil,
                onChange: nil),
            ProviderSettingsPickerDescriptor(
                id: "gemini-cookie-source",
                title: "Cookie source",
                subtitle: autoCookieSubtitle,
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: { context.settings.providerConfig(for: .gemini)?.source == .web },
                onChange: nil,
                trailingText: {
                    ProviderCookieRefreshAction.trailingText(
                        provider: .gemini, cookieSource: context.settings.geminiCookieSource, context: context)
                },
                trailingActions: [ProviderCookieRefreshAction.descriptor(
                    provider: .gemini,
                    cookieSource: { context.settings.geminiCookieSource },
                    context: context,
                    expectedSourceLabel: "Gemini app")]),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [.init(
            id: "gemini-cookie",
            title: "Cookie header",
            subtitle: "",
            kind: .secure,
            placeholder: "Cookie: …",
            binding: context.binding(\.geminiCookieHeader),
            actions: [ProviderSettingsActionDescriptor(
                id: "gemini-open-usage",
                title: "Open Usage Page",
                style: .link,
                isVisible: nil,
                perform: {
                    if let url = URL(string: "https://gemini.google.com/usage") {
                        NSWorkspace.shared.open(url)
                    }
                })],
            isVisible: {
                context.settings.providerConfig(for: .gemini)?.source == .web
                    && context.settings.geminiCookieSource == .manual
            },
            onActivate: nil)]
    }

    @MainActor
    func settingsActions(context: ProviderSettingsContext) -> [ProviderSettingsActionsDescriptor] {
        guard Self.showsAntigravityMigrationAction(context: context) else { return [] }
        return [
            ProviderSettingsActionsDescriptor(
                id: "gemini-antigravity-migration",
                title: "Gemini CLI migration",
                subtitle: GeminiConsumerTierMigration.deprecationError,
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "gemini-enable-antigravity",
                        title: "Enable Antigravity provider",
                        style: .bordered,
                        isVisible: nil,
                        perform: {
                            // Provider-specific by design: Gemini migration explicitly enables its Antigravity
                            // successor.
                            context.settings.setProviderEnabled(
                                provider: .antigravity,
                                metadata: ProviderDescriptorRegistry.descriptor(for: .antigravity).metadata,
                                enabled: true)
                            await context.store.refreshProvider(.antigravity, allowDisabled: true)
                        }),
                ],
                isVisible: nil),
        ]
    }

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        if context.controller.settings.providerConfig(for: .gemini)?.source == .web {
            NSWorkspace.shared.open(URL(string: "https://gemini.google.com/usage")!)
            return false
        }
        await context.controller.runGeminiLoginFlow()
        return false
    }

    @MainActor
    private static func showsAntigravityMigrationAction(context: ProviderSettingsContext) -> Bool {
        context.store.geminiObservedConsumerTierDeprecation
            && context.settings.providerConfig(for: .gemini)?.source != .web
    }
}

extension SettingsStore {
    var geminiCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .gemini, fallback: .auto) }
        set { self.providerCookieSourceBinding(provider: .gemini, fallback: .auto).wrappedValue = newValue }
    }

    var geminiCookieHeader: String {
        get { self[providerConfig: .gemini, field: .cookieHeader] }
        set { self[providerConfig: .gemini, field: .cookieHeader] = newValue }
    }
}
