import AppKit
import CodexBarCore
import Foundation
import XCTest
@testable import CodexBar

/// The merged menu pre-builds sibling switcher tabs after opening so a tab
/// switch attaches cached, pre-laid-out rows (flicker fix follow-up).
@MainActor
final class StatusMenuSwitcherWarmupTests: XCTestCase {
    private func makeController() -> (controller: StatusItemController, menu: NSMenu) {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(false)
        let settings = testSettingsStore(
            suiteName: "StatusMenuSwitcherWarmupTests",
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.providerDetectionCompleted = true
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(
                provider: provider,
                metadata: metadata,
                enabled: provider == .claude || provider == .codex)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        return (controller, menu)
    }

    func test_warmupCachesSiblingSelections() {
        let (controller, menu) = self.makeController()
        defer { controller.releaseStatusItemsForTesting() }
        guard menu.items.first?.view is ProviderSwitcherView else {
            return XCTFail("expected merged menu with provider switcher")
        }

        controller.warmMergedSwitcherSiblingContent(in: menu)

        let caches = controller.mergedSwitcherContentCaches[ObjectIdentifier(menu)] ?? [:]
        let enabledProviders = controller.store.enabledProvidersForDisplay()
        let cachedSelections = Set(caches.keys)
        let siblingProviders = enabledProviders.filter { cachedSelections.contains(.provider($0)) }
        // Every non-visible provider tab gets a cache entry; the visible tab is
        // cached separately by the populate path.
        XCTAssertGreaterThanOrEqual(siblingProviders.count, enabledProviders.count - 1)
        for (_, entry) in caches {
            XCTAssertFalse(entry.items.isEmpty)
        }
    }

    func test_warmupSkipsSelectionsAlreadyCached() {
        let (controller, menu) = self.makeController()
        defer { controller.releaseStatusItemsForTesting() }

        controller.warmMergedSwitcherSiblingContent(in: menu)
        let firstItems = controller.mergedSwitcherContentCaches[ObjectIdentifier(menu)]?
            .mapValues { $0.items }

        controller.warmMergedSwitcherSiblingContent(in: menu)
        let secondItems = controller.mergedSwitcherContentCaches[ObjectIdentifier(menu)]?
            .mapValues { $0.items }

        // Re-warming with unchanged inputs must reuse the cached items, not rebuild them.
        XCTAssertEqual(firstItems?.count, secondItems?.count)
        for (selection, items) in firstItems ?? [:] {
            XCTAssertTrue(secondItems?[selection]?.elementsEqual(items, by: ===) == true)
        }
    }

    func test_warmupSchedulerRunsDuringMenuTrackingAndHonorsCancellation() {
        var runCount = 0
        let scheduled = MergedSwitcherWarmupRunLoopScheduler.schedule(after: 0) {
            runCount += 1
        }

        CFRunLoopRunInMode(
            CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString),
            0.1,
            true)
        XCTAssertEqual(runCount, 1)

        CFRunLoopRunInMode(.defaultMode, 0.1, true)
        XCTAssertEqual(runCount, 1)

        let cancelled = MergedSwitcherWarmupRunLoopScheduler.schedule(after: 0) {
            runCount += 1
        }
        cancelled.cancel()
        CFRunLoopRunInMode(
            CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString),
            0.1,
            true)
        XCTAssertEqual(runCount, 1)
        _ = scheduled
    }
}
