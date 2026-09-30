import CodexBarCore
import Foundation
import SwiftUI

struct VeniceProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .venice

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            context.store.sourceLabel(for: context.provider)
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.veniceUsageDataSource
        _ = settings.veniceCookieSource
        _ = settings.veniceCookieHeader
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        if context.settings.veniceUsageDataSource == .web { return true }
        if VeniceSettingsReader.apiKey(environment: context.environment) != nil { return true }
        return !context.settings.tokenAccounts(for: .venice).isEmpty
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        let cookies: CookieProviderSettings = context.settings.resolvedCookieSettings(
            provider: .venice,
            configuredSource: context.settings.veniceCookieSource,
            configuredHeader: context.settings.veniceCookieHeader,
            tokenOverride: context.tokenOverride)
        return .venice(.init(cookieSource: cookies.cookieSource, manualCookieHeader: cookies.manualCookieHeader))
    }

    @MainActor
    func defaultSourceLabel(context: ProviderSourceLabelContext) -> String? {
        context.settings.veniceUsageDataSource.rawValue
    }

    @MainActor
    func sourceMode(context: ProviderSourceModeContext) -> ProviderSourceMode {
        switch context.settings.veniceUsageDataSource {
        case .auto: .auto
        case .api: .api
        case .web: .web
        }
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let usageBinding = Binding(
            get: { context.settings.veniceUsageDataSource.rawValue },
            set: { raw in
                context.settings.veniceUsageDataSource = VeniceUsageDataSource(rawValue: raw) ?? .auto
            })
        let cookieBinding = Binding(
            get: { context.settings.veniceCookieSource.rawValue },
            set: { raw in
                context.settings.veniceCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.veniceCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                subtitles: ProviderCookieSourceUI.Subtitles(
                    auto: L("Automatically imports browser cookies for %@.", "venice.ai"),
                    manual: L("Paste a Cookie header from %@.", "venice.ai"),
                    off: L("%@ cookies are disabled.", "Venice")))
        }
        return [
            ProviderSettingsPickerDescriptor(
                id: "venice-usage-source",
                title: "Usage source",
                subtitle: "Auto uses the API key. Web reads the signed-in venice.ai browser session.",
                binding: usageBinding,
                options: VeniceUsageDataSource.allCases.map {
                    ProviderSettingsPickerOption(id: $0.rawValue, title: $0.displayName)
                },
                isVisible: nil,
                onChange: nil),
            ProviderSettingsPickerDescriptor(
                id: "venice-cookie-source",
                title: "Cookie source",
                subtitle: L("Automatically imports browser cookies for %@.", "venice.ai"),
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: ProviderCookieSourceUI.options(
                    allowsOff: true,
                    keychainDisabled: context.settings.debugDisableKeychainAccess),
                isVisible: { context.settings.veniceUsageDataSource == .web },
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [ProviderSettingsFieldDescriptor(
            id: "venice-cookie",
            title: "",
            subtitle: "",
            kind: .secure,
            placeholder: "Cookie: …",
            binding: context.stringBinding(\.veniceCookieHeader),
            actions: [],
            isVisible: {
                context.settings.veniceUsageDataSource == .web && context.settings.veniceCookieSource == .manual
            },
            onActivate: nil)]
    }
}
