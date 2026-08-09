import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct StatusItemControllerMenuTests {
    @MainActor
    private final class RecordingUpdater: UpdaterProviding {
        var automaticallyChecksForUpdates = false
        var automaticallyDownloadsUpdates = false
        let isAvailable = true
        let unavailableReason: String? = nil
        let updateStatus = UpdateStatus(isUpdateReady: true)
        var checkForUpdatesCount = 0
        var installUpdateCount = 0

        func checkForUpdates(_ sender: Any?) {
            _ = sender
            self.checkForUpdatesCount += 1
        }

        func installUpdate() {
            self.installUpdateCount += 1
        }
    }

    private func makeSnapshot(
        primary: RateWindow?,
        secondary: RateWindow?,
        tertiary: RateWindow? = nil,
        extraRateWindows: [NamedRateWindow]? = nil,
        providerCost: ProviderCostSnapshot? = nil)
        -> UsageSnapshot
    {
        UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            extraRateWindows: extraRateWindows,
            providerCost: providerCost,
            updatedAt: Date())
    }

    @Test
    func `switcher prefers weekly allowance over primary session allowance`() {
        let session = RateWindow(usedPercent: 20, windowMinutes: 5 * 60, resetsAt: nil, resetDescription: nil)
        let weekly = RateWindow(usedPercent: 65, windowMinutes: 7 * 24 * 60, resetsAt: nil, resetDescription: nil)
        let snapshot = self.makeSnapshot(primary: session, secondary: weekly)

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .claude,
            snapshot: snapshot,
            showUsed: false)

        #expect(percent == 35)
    }

    @Test
    func `claude switcher ignores exhausted scoped weekly carve outs`() {
        let session = RateWindow(usedPercent: 77, windowMinutes: 5 * 60, resetsAt: nil, resetDescription: nil)
        let weekly = RateWindow(usedPercent: 61, windowMinutes: 7 * 24 * 60, resetsAt: nil, resetDescription: nil)
        let snapshot = self.makeSnapshot(
            primary: session,
            secondary: weekly,
            tertiary: RateWindow(
                usedPercent: 100,
                windowMinutes: 7 * 24 * 60,
                resetsAt: nil,
                resetDescription: nil),
            extraRateWindows: [
                NamedRateWindow(
                    id: "claude-weekly-scoped-fable",
                    title: "Fable only",
                    window: RateWindow(
                        usedPercent: 100,
                        windowMinutes: 7 * 24 * 60,
                        resetsAt: nil,
                        resetDescription: nil)),
            ])

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .claude,
            snapshot: snapshot,
            showUsed: false)

        #expect(percent == 39)
    }

    @Test
    func `claude switcher keeps account weekly even when scoped carve out remains`() {
        let session = RateWindow(usedPercent: 20, windowMinutes: 5 * 60, resetsAt: nil, resetDescription: nil)
        let weekly = RateWindow(usedPercent: 40, windowMinutes: 7 * 24 * 60, resetsAt: nil, resetDescription: nil)
        let snapshot = self.makeSnapshot(
            primary: session,
            secondary: weekly,
            extraRateWindows: [
                NamedRateWindow(
                    id: "claude-weekly-scoped-fable",
                    title: "Fable only",
                    window: RateWindow(
                        usedPercent: 85,
                        windowMinutes: 7 * 24 * 60,
                        resetsAt: nil,
                        resetDescription: nil)),
            ])

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .claude,
            snapshot: snapshot,
            showUsed: false)

        #expect(percent == 60)
    }

    @Test
    func `cursor switcher falls back to on demand budget when plan exhausted and showing remaining`() {
        let snapshot = self.makeSnapshot(
            primary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 36, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            providerCost: ProviderCostSnapshot(
                used: 12,
                limit: 200,
                currencyCode: "USD",
                updatedAt: Date()))

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .cursor,
            snapshot: snapshot,
            showUsed: false)

        #expect(percent == 94)
    }

    @Test
    func `cursor switcher uses primary when showing used`() {
        let snapshot = self.makeSnapshot(
            primary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 36, windowMinutes: nil, resetsAt: nil, resetDescription: nil))

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .cursor,
            snapshot: snapshot,
            showUsed: true)

        #expect(percent == 100)
    }

    @Test
    func `cursor switcher keeps primary when remaining is positive`() {
        let snapshot = self.makeSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 40, windowMinutes: nil, resetsAt: nil, resetDescription: nil))

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .cursor,
            snapshot: snapshot,
            showUsed: false)

        #expect(percent == 80)
    }

    @Test
    func `cursor switcher does not treat auto lane as extra remaining quota`() {
        let snapshot = self.makeSnapshot(
            primary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 36, windowMinutes: nil, resetsAt: nil, resetDescription: nil))

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .cursor,
            snapshot: snapshot,
            showUsed: false)

        #expect(percent == 0)
    }

    @Test
    @MainActor
    func `menu card width stays at base width when menu accessories are present`() {
        let shortcutMenu = NSMenu()
        shortcutMenu.addItem(NSMenuItem(title: "Refresh", action: nil, keyEquivalent: "r"))
        #expect(ceil(shortcutMenu.size.width) < 310)

        let submenuMenu = NSMenu()
        let parentItem = NSMenuItem(title: "Session", action: nil, keyEquivalent: "")
        parentItem.submenu = NSMenu(title: "Session")
        submenuMenu.addItem(parentItem)
        #expect(ceil(submenuMenu.size.width) < 310)
    }

    @Test
    @MainActor
    func `status components pass through for retained providers`() {
        let components = [
            ProviderStatusComponent(id: "1", name: "API", indicator: .none, status: "operational"),
            ProviderStatusComponent(id: "2", name: "Web App", indicator: .none, status: "operational"),
        ]

        let filtered = StatusItemController.filterStatusComponents(components, for: .claude)

        #expect(filtered.map(\.name) == ["API", "Web App"])
    }

    @Test
    @MainActor
    func `update menu action installs prepared update instead of checking again`() {
        let settings = testSettingsStore(suiteName: "StatusItemControllerMenuTests-\(UUID().uuidString)")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let updater = RecordingUpdater()
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: updater,
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)

        controller.installUpdate()

        #expect(updater.installUpdateCount == 1)
        #expect(updater.checkForUpdatesCount == 0)
    }
}
