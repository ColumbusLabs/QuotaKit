import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct FactoryProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .factory
    let supportsLoginFlow: Bool = true

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.factoryCookieSource.rawValue },
            set: { raw in
                context.settings.factoryCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions: [ProviderSettingsPickerOption] = [
            ProviderSettingsPickerOption(
                id: ProviderCookieSource.auto.rawValue,
                title: ProviderCookieSource.auto.displayName),
            ProviderSettingsPickerOption(
                id: ProviderCookieSource.manual.rawValue,
                title: ProviderCookieSource.manual.displayName),
        ]

        let cookieSubtitle: () -> String? = {
            switch context.settings.factoryCookieSource {
            case .auto:
                "Automatic imports browser cookies and WorkOS tokens."
            case .manual:
                "Paste a Cookie header from app.factory.ai."
            case .off:
                "Factory cookies are disabled."
            }
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "factory-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies and WorkOS tokens.",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: { !context.settings.debugDisableKeychainAccess },
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.load(provider: .factory) else { return nil }
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
        await context.controller.runFactoryLoginFlow()
        return true
    }
}
