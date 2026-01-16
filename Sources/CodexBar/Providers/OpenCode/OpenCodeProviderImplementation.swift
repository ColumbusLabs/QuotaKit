import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct OpenCodeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .opencode

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.opencodeCookieSource.rawValue },
            set: { raw in
                context.settings.opencodeCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
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
            switch context.settings.opencodeCookieSource {
            case .auto:
                "Automatic imports browser cookies from opencode.ai."
            case .manual:
                "Paste a Cookie header captured from the billing page."
            case .off:
                "OpenCode cookies are disabled."
            }
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "opencode-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies from opencode.ai.",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: { !context.settings.debugDisableKeychainAccess },
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.load(provider: .opencode) else { return nil }
                    let when = entry.storedAt.relativeDescription()
                    return "Cached: \(entry.sourceLabel) • \(when)"
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "opencode-workspace-id",
                title: "Workspace ID",
                subtitle: "Optional override if workspace lookup fails.",
                kind: .plain,
                placeholder: "wrk_…",
                binding: context.stringBinding(\.opencodeWorkspaceID),
                actions: [],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
