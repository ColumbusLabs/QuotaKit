import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct MiniMaxProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .minimax

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.minimaxCookieSource.rawValue },
            set: { raw in
                context.settings.minimaxCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
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
            switch context.settings.minimaxCookieSource {
            case .auto:
                "Automatic imports browser cookies and local storage tokens."
            case .manual:
                "Paste a Cookie header or cURL capture from the Coding Plan page."
            case .off:
                "MiniMax cookies are disabled."
            }
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "minimax-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies and local storage tokens.",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: { !context.settings.debugDisableKeychainAccess },
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.load(provider: .minimax) else { return nil }
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
}
