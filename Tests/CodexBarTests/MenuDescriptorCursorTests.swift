import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct MenuDescriptorCursorTests {
    @Test
    func `modern auto api layout labels both quota windows`() throws {
        let suite = "MenuDescriptorCursorTests-auto-api"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 40, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                tertiary: nil,
                cursorRateWindowLayout: .autoAPI,
                updatedAt: Date()),
            provider: .cursor)

        let descriptor = MenuDescriptor.build(
            provider: .cursor,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: false)

        let textLines = descriptor.sections
            .flatMap(\.entries)
            .compactMap { entry -> String? in
                guard case let .text(text, _) = entry else { return nil }
                return text
            }

        let rateWindowLabels = textLines.compactMap { line -> String? in
            if line.hasPrefix("Auto:") { return "Auto" }
            if line.hasPrefix("API:") { return "API" }
            if line.hasPrefix("Total:") { return "Total" }
            return nil
        }

        #expect(rateWindowLabels == ["Auto", "API"])
    }

    @Test
    func `legacy request plan labels primary window as requests`() throws {
        let suite = "MenuDescriptorCursorTests-legacy-requests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                tertiary: nil,
                cursorRequests: CursorRequestUsage(used: 250, limit: 500),
                updatedAt: Date()),
            provider: .cursor)

        let descriptor = MenuDescriptor.build(
            provider: .cursor,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: false)

        let textLines = descriptor.sections
            .flatMap(\.entries)
            .compactMap { entry -> String? in
                guard case let .text(text, _) = entry else { return nil }
                return text
            }

        #expect(textLines.contains(where: { $0.hasPrefix("Requests:") }))
        #expect(!textLines.contains(where: { $0.hasPrefix("Auto:") }))
    }
}
