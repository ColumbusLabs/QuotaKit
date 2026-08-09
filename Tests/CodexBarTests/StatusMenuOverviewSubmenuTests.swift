import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

extension StatusMenuTests {
    @Test
    func `selecting overview row defers provider detail rebuild`() async throws {
        let previousMenuCardRendering = StatusItemController.menuCardRenderingEnabled
        let previousMenuRefresh = StatusItemController.menuRefreshEnabled
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer {
            StatusItemController.menuCardRenderingEnabled = previousMenuCardRendering
            StatusItemController.setMenuRefreshEnabledForTesting(previousMenuRefresh)
        }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.mergedMenuLastSelectedWasOverview = true

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            let shouldEnable = provider == .codex || provider == .cursor
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: shouldEnable)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        let cursorRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-cursor"
        })
        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        let action = try #require(cursorRow.action)
        let target = try #require(cursorRow.target as? StatusItemController)
        _ = target.perform(action, with: cursorRow)

        #expect(settings.mergedMenuLastSelectedWasOverview == false)
        #expect(settings.selectedMenuProvider == .cursor)
        #expect(rebuildCount == 0)
        #expect(menu.items.contains {
            ($0.representedObject as? String)?.hasPrefix("overviewRow-") == true
        })

        for _ in 0..<100 where rebuildCount == 0 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }

        let representedIDs = menu.items.compactMap { $0.representedObject as? String }
        let switcherButtons = (menu.items.first?.view as? ProviderSwitcherView)?.subviews
            .compactMap { $0 as? NSButton } ?? []
        #expect(rebuildCount == 1)
        #expect(representedIDs.contains("menuCard"))
        #expect(representedIDs.contains(where: { $0.hasPrefix("overviewRow-") }) == false)
        #expect(switcherButtons.first(where: { $0.state == .on })?.tag == 2)
    }

    @Test
    func `overview row action close renders selected provider on next open`() async throws {
        let previousMenuCardRendering = StatusItemController.menuCardRenderingEnabled
        let previousMenuRefresh = StatusItemController.menuRefreshEnabled
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer {
            StatusItemController.menuCardRenderingEnabled = previousMenuCardRendering
            StatusItemController.setMenuRefreshEnabledForTesting(previousMenuRefresh)
        }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.mergedMenuLastSelectedWasOverview = true

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            let shouldEnable = provider == .codex || provider == .cursor
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: shouldEnable)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let cursorRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-cursor"
        })
        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        let action = try #require(cursorRow.action)
        let target = try #require(cursorRow.target as? StatusItemController)
        _ = target.perform(action, with: cursorRow)
        controller.menuDidClose(menu)

        await Task.yield()
        await Task.yield()
        #expect(rebuildCount == 0)
        #expect(settings.selectedMenuProvider == .cursor)

        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        let representedIDs = menu.items.compactMap { $0.representedObject as? String }
        let switcherButtons = (menu.items.first?.view as? ProviderSwitcherView)?.subviews
            .compactMap { $0 as? NSButton } ?? []
        #expect(representedIDs.contains("menuCard"))
        #expect(representedIDs.contains(where: { $0.hasPrefix("overviewRow-") }) == false)
        #expect(switcherButtons.first(where: { $0.state == .on })?.tag == 2)
    }
}
