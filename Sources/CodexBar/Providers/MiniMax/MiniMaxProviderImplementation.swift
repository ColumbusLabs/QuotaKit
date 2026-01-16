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
        context.settings.ensureMiniMaxAPITokenLoaded()
        let tokenIsSet: () -> Bool = {
            if MiniMaxAPISettingsReader.apiToken(environment: ProcessInfo.processInfo.environment) != nil {
                return true
            }
            return !context.settings.minimaxAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

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

        let regionBinding = Binding(
            get: { context.settings.minimaxAPIRegion.rawValue },
            set: { raw in
                context.settings.minimaxAPIRegion = MiniMaxAPIRegion(rawValue: raw) ?? .global
            })
        let regionOptions = MiniMaxAPIRegion.allCases.map {
            ProviderSettingsPickerOption(id: $0.rawValue, title: $0.displayName)
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "minimax-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies and local storage tokens.",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: { !context.settings.debugDisableKeychainAccess && !tokenIsSet() },
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.load(provider: .minimax) else { return nil }
                    let when = entry.storedAt.relativeDescription()
                    return "Cached: \(entry.sourceLabel) • \(when)"
                }),
            ProviderSettingsPickerDescriptor(
                id: "minimax-region",
                title: "API region",
                subtitle: "Choose the MiniMax host (global .io or China mainland .com).",
                binding: regionBinding,
                options: regionOptions,
                isVisible: { !tokenIsSet() },
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        context.settings.ensureMiniMaxAPITokenLoaded()
        let tokenIsSet: () -> Bool = {
            if MiniMaxAPISettingsReader.apiToken(environment: ProcessInfo.processInfo.environment) != nil {
                return true
            }
            return !context.settings.minimaxAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return [
            ProviderSettingsFieldDescriptor(
                id: "minimax-api-token",
                title: "API token",
                subtitle: "Stored in Keychain. Paste your MiniMax API key.",
                kind: .secure,
                placeholder: "Paste API token…",
                binding: context.stringBinding(\.minimaxAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "minimax-open-dashboard",
                        title: "Open Coding Plan",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(
                                string: "https://platform.minimax.io/user-center/payment/coding-plan?cycle_type=3")
                            {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { !context.settings.debugDisableKeychainAccess },
                onActivate: { context.settings.ensureMiniMaxAPITokenLoaded() }),
            ProviderSettingsFieldDescriptor(
                id: "minimax-cookie",
                title: "Cookie header",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: …",
                binding: context.stringBinding(\.minimaxCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "minimax-open-dashboard-cookie",
                        title: "Open Coding Plan",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(
                                string: "https://platform.minimax.io/user-center/payment/coding-plan?cycle_type=3")
                            {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: {
                    !context.settings.debugDisableKeychainAccess &&
                        !tokenIsSet() &&
                        context.settings.minimaxCookieSource == .manual
                },
                onActivate: { context.settings.ensureMiniMaxCookieLoaded() }),
        ]
    }
}
