import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct PopupLocalizationTests {
    @Test
    func `descriptor account labels use English copy`() {
        let settings = testSettingsStore(suiteName: "PopupLocalizationTests-descriptor")
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "codex@example.com",
                    accountOrganization: nil,
                    loginMethod: "free")),
            provider: .codex)

        let descriptor = MenuDescriptor.build(
            provider: .codex,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: false)
        let lines = Self.textLines(from: descriptor)

        #expect(lines.contains("Account: codex@example.com"))
        #expect(lines.contains("Plan: Free"))
    }

    @Test
    func `cookie source dynamic subtitles use English copy`() {
        let subtitle = ProviderCookieSourceUI.subtitle(
            source: .manual,
            keychainDisabled: false,
            auto: "Automatically imports browser cookies.",
            manual: "Paste a Cookie header or cURL capture from Claude settings.",
            off: "Claude cookies are disabled.")
        let disabledSubtitle = ProviderCookieSourceUI.subtitle(
            source: .manual,
            keychainDisabled: true,
            auto: "Automatically imports browser cookies.",
            manual: "Paste a Cookie header or cURL capture from Claude settings.",
            off: "Claude cookies are disabled.")

        #expect(subtitle == "Paste a Cookie header or cURL capture from Claude settings.")
        #expect(disabledSubtitle.hasPrefix("Keychain access is disabled in Advanced"))
    }

    private static func textLines(from descriptor: MenuDescriptor) -> [String] {
        descriptor.sections.flatMap(\.entries).compactMap { entry -> String? in
            guard case let .text(text, _) = entry else { return nil }
            return text
        }
    }
}
