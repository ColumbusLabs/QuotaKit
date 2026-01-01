import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct CursorProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .cursor
    let supportsLoginFlow: Bool = true

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.cursorCookieSource.rawValue },
            set: { raw in
                context.settings.cursorCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions: [ProviderSettingsPickerOption] = [
            ProviderSettingsPickerOption(
                id: ProviderCookieSource.auto.rawValue,
                title: ProviderCookieSource.auto.displayName),
            ProviderSettingsPickerOption(
                id: ProviderCookieSource.manual.rawValue,
                title: ProviderCookieSource.manual.displayName),
        ]

        return [
            ProviderSettingsPickerDescriptor(
                id: "cursor-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies or stored sessions.",
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "cursor-cookie-header",
                title: "Cookie header",
                subtitle: "Paste the Cookie header from a cursor.com request.",
                kind: .secure,
                placeholder: "Cookie: …",
                binding: context.stringBinding(\.cursorCookieHeader),
                actions: [],
                isVisible: { context.settings.cursorCookieSource == .manual },
                onActivate: { context.settings.ensureCursorCookieLoaded() }),
        ]
    }

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await context.controller.runCursorLoginFlow()
        return true
    }
}
