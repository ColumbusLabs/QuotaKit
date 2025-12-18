import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite
struct StatusMenuTests {
    @Test
    func remembersProviderWhenMenuOpens() {
        let settings = SettingsStore()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: false)
        }
        if let claudeMeta = registry.metadata[.claude] {
            settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: false)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection())

        let codexMenu = controller.makeMenu(for: .codex)
        controller.menuWillOpen(codexMenu)
        #expect(controller.lastMenuProvider == .codex)

        let claudeMenu = controller.makeMenu(for: .claude)
        controller.menuWillOpen(claudeMenu)
        #expect(controller.lastMenuProvider == .claude)

        // Unmapped menu falls back to the first enabled provider or Codex.
        let unmappedMenu = NSMenu()
        controller.menuWillOpen(unmappedMenu)
        #expect(controller.lastMenuProvider == .codex)
    }

    @Test
    func hidesOpenAIWebSubmenusWhenNoHistory() {
        let settings = SettingsStore()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.openAIDashboardEnabled = true

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, settings: settings)
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: 100,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [],
            updatedAt: Date())

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection())

        let menu = controller.makeMenu(for: .codex)
        let titles = Set(menu.items.map(\.title))
        #expect(!titles.contains("Credits usage history"))
        #expect(!titles.contains("Usage breakdown (30 days)"))
    }

    @Test
    func showsOpenAIWebSubmenusWhenHistoryExists() {
        let settings = SettingsStore()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.openAIDashboardEnabled = true

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, settings: settings)

        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2025
        components.month = 12
        components.day = 18
        let date = components.date!

        let events = [CreditEvent(date: date, service: "CLI", creditsUsed: 1)]
        let breakdown = OpenAIDashboardSnapshot.makeDailyBreakdown(from: events, maxDays: 30)
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: 100,
            creditEvents: events,
            dailyBreakdown: breakdown,
            usageBreakdown: breakdown,
            updatedAt: Date())

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection())

        let menu = controller.makeMenu(for: .codex)
        let titles = Set(menu.items.map(\.title))
        #expect(titles.contains("Credits usage history"))
        #expect(titles.contains("Usage breakdown (30 days)"))
    }
}
