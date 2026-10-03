import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct HuggingFaceProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .huggingface

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "api" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings[providerConfig: .huggingface, field: .apiKey]
        _ = settings.huggingFaceCookieSource
        _ = settings.huggingFaceCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .huggingface(context.settings.huggingFaceSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        if HuggingFaceSettingsReader.apiKey(environment: context.environment) != nil {
            return true
        }
        if !context.settings[providerConfig: .huggingface, field: .apiKey].isEmpty {
            return true
        }
        return !context.settings.tokenAccounts(for: .huggingface).isEmpty
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.huggingFaceCookieSource.rawValue },
            set: { raw in
                context.settings.huggingFaceCookieSource = ProviderCookieSource(rawValue: raw) ?? .off
            })
        let subtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.huggingFaceCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                subtitles: ProviderCookieSourceUI.Subtitles(
                    auto: ProviderCookieSourceUI.browserImportSubtitle(
                        L("Imports browser cookies to read the optional prepaid balance."),
                        provider: .huggingface),
                    manual: L("Paste the Cookie header captured from your Hugging Face billing page."),
                    off: L("%@ cookies are disabled.", "Hugging Face")))
        }
        return [
            ProviderSettingsPickerDescriptor(
                id: "huggingface-cookie-source",
                title: "Cookie source",
                subtitle: ProviderCookieSourceUI.browserImportSubtitle(
                    L("Imports browser cookies to read the optional prepaid balance."),
                    provider: .huggingface),
                dynamicSubtitle: subtitle,
                binding: cookieBinding,
                options: ProviderCookieSourceUI.options(
                    allowsOff: true,
                    keychainDisabled: context.settings.debugDisableKeychainAccess),
                isVisible: nil,
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        var fields = [
            ProviderSettingsFieldDescriptor(
                id: "huggingface-api-token",
                title: "Access token",
                subtitle: "Create a token at huggingface.co/settings/tokens. Classic read tokens work; "
                    + "fine-grained tokens need the Billing read permission.",
                kind: .secure,
                placeholder: "Paste access token…",
                binding: context.providerConfigBinding(.apiKey),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "huggingface-open-tokens",
                        title: "Open Hugging Face",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            NSWorkspace.shared.open(HuggingFaceURLs.tokens)
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
        fields.append(
            ProviderSettingsFieldDescriptor(
                id: "huggingface-cookie-header",
                title: "Cookie header",
                subtitle: "Paste the Cookie header captured from your Hugging Face billing page.",
                kind: .secure,
                placeholder: L("Paste a Cookie header captured from %@.", "Hugging Face billing page"),
                binding: context.stringBinding(\.huggingFaceCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "huggingface-open-billing",
                        title: "Open billing",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            NSWorkspace.shared.open(HuggingFaceURLs.billing)
                        }),
                ],
                isVisible: { context.settings.huggingFaceCookieSource == .manual },
                onActivate: nil))
        return fields
    }
}

enum HuggingFaceURLs {
    static let tokens = URL(string: "https://huggingface.co/settings/tokens")!
    static let billing = URL(string: "https://huggingface.co/settings/billing")!
}
