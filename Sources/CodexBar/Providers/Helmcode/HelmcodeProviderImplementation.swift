import CodexBarCore
import Foundation
import SwiftUI

struct HelmcodeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .helmcode

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        let cookies: CookieProviderSettings = context.settings.resolvedCookieSettings(
            provider: self.id, tokenOverride: context.tokenOverride)
        return .init(HelmcodeProviderSettings(
            cookieSource: cookies.cookieSource,
            manualCookieHeader: cookies.manualCookieHeader,
            manualTenant: context.settings.helmcodeManualTenant), for: HelmcodeProviderSettingsKey.self)
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.helmcodeCookieSource.rawValue },
            set: { raw in
                context.settings.helmcodeCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let tenantBinding = Binding(
            get: { context.settings.helmcodeManualTenant },
            set: { context.settings.helmcodeManualTenant = $0 })
        return [
            ProviderSettingsPickerDescriptor(
                id: "helmcode-cookie-source",
                title: "Cookie source",
                subtitle: "Choose how QuotaKit reads Helmcode and NaN Builders sessions.",
                dynamicSubtitle: {
                    ProviderCookieSourceUI.subtitle(
                        source: context.settings.helmcodeCookieSource,
                        keychainDisabled: context.settings.debugDisableKeychainAccess,
                        auto: "Imports Chrome sessions for Helmcode Cloud or NaN Builders; Cloud is preferred.",
                        manual: "Paste a Cookie header and select its tenant below.",
                        off: "Helmcode dashboard cookies are disabled.")
                },
                binding: cookieBinding,
                options: ProviderCookieSourceUI.options(
                    allowsOff: true,
                    keychainDisabled: context.settings.debugDisableKeychainAccess),
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    ProviderCookieRefreshAction.trailingText(
                        provider: .helmcode,
                        cookieSource: context.settings.helmcodeCookieSource,
                        context: context)
                },
                trailingActions: [ProviderCookieRefreshAction.descriptor(
                    provider: .helmcode,
                    cookieSource: { context.settings.helmcodeCookieSource },
                    context: context)]),
            ProviderSettingsPickerDescriptor(
                id: "helmcode-manual-tenant",
                title: "Manual cookie tenant",
                subtitle: "The pasted header is sent only to this tenant.",
                binding: tenantBinding,
                options: [
                    .init(id: "helmcode", title: "Helmcode Cloud"),
                    .init(id: "nanBuilders", title: "NaN Builders"),
                ],
                isVisible: { context.settings.helmcodeCookieSource == .manual },
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [ProviderSettingsFieldDescriptor(
            id: "helmcode-cookie",
            title: "Cookie header",
            subtitle: "Copy the Cookie request header from your tenant's dashboard. cURL captures are not supported.",
            kind: .secure,
            placeholder: "Cookie: …",
            binding: context.providerConfigBinding(.cookieHeader),
            actions: [],
            isVisible: { context.settings.helmcodeCookieSource == .manual },
            onActivate: nil)]
    }
}

extension SettingsStore {
    var helmcodeCookieHeader: String {
        get { self[providerConfig: .helmcode, field: .cookieHeader] }
        set { self[providerConfig: .helmcode, field: .cookieHeader] = newValue }
    }

    var helmcodeCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .helmcode, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .helmcode) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .helmcode, field: "cookieSource", value: newValue.rawValue)
        }
    }

    var helmcodeManualTenant: String {
        get { self.configSnapshot.providerConfig(for: .helmcode)?.region == "nanBuilders" ? "nanBuilders" : "helmcode" }
        set { self.updateProviderConfig(provider: .helmcode) { $0.region = newValue } }
    }
}
