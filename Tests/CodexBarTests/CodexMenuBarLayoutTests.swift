import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CodexMenuBarLayoutTests {
    @Test
    func `switching a custom Codex layout from automatic to session retains its own values`() throws {
        let now = Date(timeIntervalSince1970: 1_752_768_000)
        let settings = testSettingsStore(
            suiteName: "CodexMenuBarLayoutTests", userDefaults: InMemoryUserDefaults())
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 2, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 6, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            updatedAt: now)
        store._setSnapshotForTesting(snapshot, provider: .codex)
        let data = store.menuBarLayoutRenderData(
            provider: .codex,
            snapshot: snapshot,
            iconKey: "fixture",
            accountLabel: nil,
            costs: .init(today: nil, last30Days: nil, todayUSD: nil, last30DaysUSD: nil),
            now: now)
        let layout = try JSONDecoder().decode(MenuBarLayout.self, from: Data(
            #"{"lines":[[{"icon":{}},{"percent":{"window":"session"}},{"percent":{"window":"weekly"}}]]}"#.utf8))
        let renderer = MenuBarLayoutRenderer()
        let options = MenuBarLayoutRenderOptions(
            size: .regular,
            highContrast: false,
            showUsed: true,
            conditionals: [],
            appearanceName: "aqua",
            isDebugApp: false,
            now: now,
            colorByProvider: true,
            showWindowLabels: false)
        let automatic = renderer.render(
            layout: MenuBarLayout(lines: [[.icon, .percent(window: .automatic), .percent(window: .weekly)]]),
            data: data,
            icon: nil,
            options: options)
        #expect(automatic.attributedTitle.string == "–\u{2009}6%\u{2009}6%")
        let result = renderer.render(layout: layout, data: data, icon: nil, options: options)
        #expect(data.session?.usedPercent == 2)
        #expect(data.weekly?.usedPercent == 6)
        #expect(result.attributedTitle.string == "–\u{2009}2%\u{2009}6%")
    }
}
