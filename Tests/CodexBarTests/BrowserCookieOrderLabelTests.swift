import CodexBarCore
import Foundation
import SweetCookieKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
@Suite
struct BrowserCookieOrderLabelTests {
    private func makeContext(
        provider: UsageProvider,
        settings: SettingsStore,
        store: UsageStore) -> ProviderSettingsContext
    {
        ProviderSettingsContext(
            provider: provider,
            settings: settings,
            store: store,
            boolBinding: { keyPath in
                Binding(
                    get: { settings[keyPath: keyPath] },
                    set: { settings[keyPath: keyPath] = $0 })
            },
            stringBinding: { keyPath in
                Binding(
                    get: { settings[keyPath: keyPath] },
                    set: { settings[keyPath: keyPath] = $0 })
            },
            statusText: { _ in nil },
            setStatusText: { _, _ in },
            lastAppActiveRunAt: { _ in nil },
            setLastAppActiveRunAt: { _, _ in },
            requestConfirmation: { _ in })
    }

    @Test
    func claudeWebExtrasSubtitleUsesBrowserOrderLabels() {
        let defaults = UserDefaults(suiteName: "BrowserCookieOrderLabelTests-claude")!
        defaults.removePersistentDomain(forName: "BrowserCookieOrderLabelTests-claude")
        let settings = SettingsStore(userDefaults: defaults, zaiTokenStore: NoopZaiTokenStore())
        let store = UsageStore(fetcher: UsageFetcher(environment: [:]), settings: settings)
        let context = self.makeContext(provider: .claude, settings: settings, store: store)
        let toggle = ClaudeProviderImplementation().settingsToggles(context: context)
            .first { $0.id == "claude.webExtras" }!

        let order = ProviderDefaults.metadata[.claude]?.browserCookieOrder ?? BrowserCookieDefaults.importOrder
        #expect(toggle.subtitle.contains(order.shortLabel))
        #expect(toggle.subtitle.contains(order.displayLabel))
    }
}

@Suite
struct BrowserCookieOrderStatusStringTests {
    #if os(macOS)
    @Test
    func cursorNoSessionIncludesBrowserLoginHint() {
        let order = ProviderDefaults.metadata[.cursor]?.browserCookieOrder ?? BrowserCookieDefaults.importOrder
        let message = CursorStatusProbeError.noSessionCookie.errorDescription ?? ""
        #expect(message.contains(order.loginHint))
    }

    @Test
    func factoryNoSessionIncludesBrowserLoginHint() {
        let order = ProviderDefaults.metadata[.factory]?.browserCookieOrder ?? BrowserCookieDefaults.importOrder
        let message = FactoryStatusProbeError.noSessionCookie.errorDescription ?? ""
        #expect(message.contains(order.loginHint))
    }
    #endif
}
