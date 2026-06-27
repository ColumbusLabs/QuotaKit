import CodexBarCore
import Foundation
import SwiftUI

struct CursorProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .cursor
    let supportsLoginFlow: Bool = true

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            context.store.sourceLabel(for: context.provider)
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.cursorUsageDataSource
        _ = settings.cursorCookieSource
        _ = settings.cursorCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .cursor(context.settings.cursorSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        guard support.requiresManualCookieSource else { return true }
        if !context.settings.tokenAccounts(for: context.provider).isEmpty { return true }
        return context.settings.cursorCookieSource == .manual
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.cursorCookieSource != .manual {
            settings.cursorCookieSource = .manual
        }
    }

    @MainActor
    func defaultSourceLabel(context: ProviderSourceLabelContext) -> String? {
        context.settings.cursorUsageDataSource.rawValue
    }

    @MainActor
    func sourceMode(context: ProviderSourceModeContext) -> ProviderSourceMode {
        context.settings.cursorUsageDataSource
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let usageBinding = Binding(
            get: { context.settings.cursorUsageDataSource.rawValue },
            set: { raw in
                context.settings.cursorUsageDataSource = ProviderSourceMode(rawValue: raw) ?? .auto
            })
        let usageOptions = [
            ProviderSettingsPickerOption(id: ProviderSourceMode.auto.rawValue, title: "Auto"),
            ProviderSettingsPickerOption(id: ProviderSourceMode.api.rawValue, title: "API"),
        ]

        let cookieBinding = Binding(
            get: { context.settings.cursorCookieSource.rawValue },
            set: { raw in
                context.settings.cursorCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.cursorCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "Automatic imports browser cookies or stored sessions.",
                manual: "Paste a Cookie header from a cursor.com request.",
                off: "Cursor cookies are disabled.")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "cursor-usage-source",
                title: "Usage source",
                subtitle: "",
                binding: usageBinding,
                options: usageOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard context.settings.cursorUsageDataSource == .auto else { return nil }
                    let label = context.store.sourceLabel(for: .cursor)
                    return label == "auto" ? nil : label
                }),
            ProviderSettingsPickerDescriptor(
                id: "cursor-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies or stored sessions.",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.loadForDisplay(provider: .cursor) else { return nil }
                    let when = entry.storedAt.relativeDescription()
                    return "Cached: \(entry.sourceLabel) • \(when)"
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        _ = context
        return []
    }

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await context.controller.runCursorLoginFlow()
        return true
    }

    @MainActor
    func appendUsageMenuEntries(context: ProviderMenuUsageContext, entries: inout [ProviderMenuEntry]) {
        guard let cost = context.snapshot?.providerCost, cost.currencyCode != "Quota" else { return }
        let used = UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode)
        if cost.limit > 0 {
            let limitStr = UsageFormatter.currencyString(cost.limit, currencyCode: cost.currencyCode)
            entries.append(.text(String(format: L("cursor_on_demand_with_limit"), used, limitStr), .primary))
        } else {
            entries.append(.text(String(format: L("cursor_on_demand"), used), .primary))
        }
    }
}
