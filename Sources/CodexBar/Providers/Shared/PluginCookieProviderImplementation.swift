import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct PluginCookieProviderImplementation: ProviderImplementation {
    let spec: PluginProviderSpec
    var fieldActions: (@MainActor @Sendable (ProviderSettingsContext) -> [ProviderSettingsActionDescriptor])?
    var trailingText: (@MainActor @Sendable () -> String?)?

    var id: UsageProvider {
        self.spec.id
    }

    private var web: PluginProviderSpec.WebSource {
        self.spec.webSource!
    }

    var supportsLoginFlow: Bool {
        self.web.loginURL != nil
    }

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation(detailLine: { context in
            if let detailLine = self.web.detailLine { return detailLine }
            return self.web.showsVersionInSettings ? ProviderPresentation.standardDetailLine(context: context) : ""
        })
    }

    @MainActor
    func runLoginFlow(context _: ProviderLoginContext) async -> Bool {
        if let url = self.web.loginURL.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
        return false
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.resolvedCookieSource(provider: self.id, fallback: .auto)
        _ = settings[providerConfig: self.id, field: .cookieHeader]
        if self.spec.apiKeyField != nil { _ = settings[providerConfig: self.id, field: .apiKey] }
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        self.web.availability(context.environment)
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        let registration = ProviderDescriptorRegistry.descriptor(for: self.id).settingsSection
        guard let cookieContribution = registration.cookieContribution else {
            return registration.defaultContribution
        }
        let cookies: ProviderSettingsSnapshot.CookieProviderSettings = context.settings.resolvedCookieSettings(
            provider: self.id,
            configuredSource: self.source(context.settings),
            configuredHeader: context.settings[providerConfig: self.id, field: .cookieHeader],
            tokenOverride: context.tokenOverride)
        return cookieContribution(cookies)
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        !support.requiresManualCookieSource || self.source(context.settings) == .manual
            || !context.settings.tokenAccounts(for: self.id).isEmpty
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        guard ProviderDescriptorRegistry.descriptor(for: self.id).credentials?
            .tokenAccountSupport?.requiresManualCookieSource == true, self.source(settings) != .manual else { return }
        settings.providerCookieSourceBinding(provider: self.id, fallback: .auto).wrappedValue = .manual
    }

    @MainActor
    private func source(_ settings: SettingsStore) -> ProviderCookieSource {
        settings.resolvedCookieSource(provider: self.id, fallback: .auto)
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        guard let picker = self.web.picker else { return [] }
        let autoSubtitle = ProviderCookieSourceUI.browserImportSubtitle(picker.auto.localized, provider: self.id)
        let sourceBinding = context.settings.providerCookieSourceBinding(provider: self.id, fallback: .auto)
        let binding = Binding(
            get: { sourceBinding.wrappedValue.rawValue },
            set: { sourceBinding.wrappedValue = ProviderCookieSource(rawValue: $0) ?? .auto })
        let refreshText: (() -> String?)? = picker.showsRefreshAction ? {
            ProviderCookieRefreshAction.trailingText(
                provider: self.id,
                cookieSource: self.source(context.settings),
                context: context)
        } : nil
        let refreshAction = picker.showsRefreshAction ? [ProviderCookieRefreshAction.descriptor(
            provider: self.id,
            cookieSource: { self.source(context.settings) },
            context: context)] : []
        return [ProviderSettingsPickerDescriptor(
            id: picker.id,
            title: "Cookie source",
            subtitle: autoSubtitle,
            dynamicSubtitle: {
                ProviderCookieSourceUI.subtitle(
                    source: self.source(context.settings),
                    keychainDisabled: context.settings.debugDisableKeychainAccess,
                    subtitles: .init(
                        auto: autoSubtitle,
                        manual: picker.manual.localized,
                        off: picker.off.localized))
            },
            binding: binding,
            options: ProviderCookieSourceUI.options(
                allowsOff: picker.allowsOff,
                keychainDisabled: context.settings.debugDisableKeychainAccess),
            isVisible: nil,
            onChange: nil,
            trailingText: self.trailingText ?? refreshText,
            trailingActions: refreshAction)]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        let field = self.web.field
        let actions: [ProviderSettingsActionDescriptor] = if let fieldActions = self.fieldActions {
            fieldActions(context)
        } else if let action = field.action, let url = URL(string: action.url) {
            [ProviderSettingsActionDescriptor(
                id: action.id,
                title: action.title,
                style: .link,
                isVisible: nil,
                perform: { NSWorkspace.shared.open(url) })]
        } else {
            []
        }
        return [ProviderSettingsFieldDescriptor(
            id: field.id,
            title: field.title,
            subtitle: field.subtitle,
            kind: .secure,
            placeholder: field.placeholder,
            binding: context.providerConfigBinding(.cookieHeader),
            actions: actions,
            isVisible: self.web.picker == nil ? nil : { self.source(context.settings) == .manual },
            onActivate: nil)] + PluginAPIKeyProviderImplementation(spec: self.spec).settingsFields(context: context)
    }
}

extension PluginProviderSpec.CookiePicker.Text {
    @MainActor
    fileprivate var localized: String {
        switch self {
        case let .literal(text): text
        case let .localized(key, argument): argument.map { L(key, $0) } ?? L(key)
        }
    }
}
