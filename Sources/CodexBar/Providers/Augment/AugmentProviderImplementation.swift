import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct AugmentProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .augment

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.augmentCookieSource.rawValue },
            set: { raw in
                context.settings.augmentCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
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
            switch context.settings.augmentCookieSource {
            case .auto:
                "Automatic imports browser cookies."
            case .manual:
                "Paste a Cookie header or cURL capture from the Augment dashboard."
            case .off:
                "Augment cookies are disabled."
            }
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "augment-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies.",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        // Actions for auto mode (browser cookies)
        let autoModeActions: [ProviderSettingsActionDescriptor] = [
            ProviderSettingsActionDescriptor(
                id: "augment-refresh-browser",
                title: "Refresh Browser Cookies",
                style: .bordered,
                isVisible: nil,
                perform: {
                    // Open Augment dashboard to refresh the session
                    if let url = URL(string: "https://app.augmentcode.com") {
                        NSWorkspace.shared.open(url)
                    }

                    // Show alert with instructions
                    let alert = NSAlert()
                    alert.messageText = "Refresh Browser Cookies"
                    alert.informativeText = """
                    To refresh your Augment session cookies:

                    1. The Augment dashboard should now be open in your browser
                    2. If you're not logged in, log in now
                    3. If you are logged in, refresh the page (⌘R)
                    4. Wait a few seconds for cookies to update
                    5. Click "Force Refresh Session" below to reload

                    Note: Browser cookies may take a few seconds to write to disk.
                    If it still doesn't work, try closing and reopening your browser.
                    """
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }),
            ProviderSettingsActionDescriptor(
                id: "augment-force-refresh",
                title: "Force Refresh Session",
                style: .bordered,
                isVisible: nil,
                perform: {
                    print("[CodexBar] Force refresh requested by user")
                    await context.store.forceRefreshAugmentSession()
                }),
            ProviderSettingsActionDescriptor(
                id: "augment-open-dashboard",
                title: "Open Augment Dashboard",
                style: .link,
                isVisible: nil,
                perform: {
                    if let url = URL(string: "https://app.augmentcode.com") {
                        NSWorkspace.shared.open(url)
                    }
                }),
        ]

        // Actions for manual mode (cookie header)
        let manualModeActions: [ProviderSettingsActionDescriptor] = [
            ProviderSettingsActionDescriptor(
                id: "augment-open-dashboard-manual",
                title: "Open Augment",
                style: .link,
                isVisible: nil,
                perform: {
                    if let url = URL(string: "https://augmentcode.com") {
                        NSWorkspace.shared.open(url)
                    }
                }),
        ]

        return [
            ProviderSettingsFieldDescriptor(
                id: "augment-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: …",
                binding: context.stringBinding(\.augmentCookieHeader),
                actions: context.settings.augmentCookieSource == .auto ? autoModeActions : manualModeActions,
                isVisible: { context.settings.augmentCookieSource == .manual },
                onActivate: { context.settings.ensureAugmentCookieLoaded() }),
        ]
    }
}
