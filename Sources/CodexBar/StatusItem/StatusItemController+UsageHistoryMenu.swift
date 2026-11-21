import AppKit
import CodexBarCore
import SwiftUI

private final class UsageHistoryMenuHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool {
        true
    }
}

extension StatusItemController {
    @discardableResult
    func addUsageHistoryMenuItemIfNeeded(to menu: NSMenu, provider: UsageProvider, width: CGFloat) -> Bool {
        guard let submenu = self.makeUsageHistorySubmenu(provider: provider, width: width) else { return false }
        let item = NSMenuItem(title: L("Plan Usage"), action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.representedObject = "usageHistorySubmenu"
        item.submenu = submenu
        menu.addItem(item)
        return true
    }

    func makeUsageHistorySubmenu(provider: UsageProvider, width: CGFloat? = nil) -> NSMenu? {
        guard self.store.supportsPlanUtilizationHistory(for: provider) else { return nil }
        guard !self.store.shouldHidePlanUtilizationMenuItem(for: provider) else { return nil }
        if let width {
            return self.makeHostedSubviewPlaceholderMenu(
                chartID: Self.usageHistoryChartID,
                provider: provider,
                width: width)
        }
        return self.makeHostedSubviewPlaceholderMenu(chartID: Self.usageHistoryChartID, provider: provider)
    }

    func appendUsageHistoryChartItem(
        to submenu: NSMenu,
        provider: UsageProvider,
        width: CGFloat) -> Bool
    {
        let (selection, snapshot) = self.usageHistorySource(for: provider)
        let histories = selection.histories

        if !self.menuCardRenderingEnabledForController {
            let chartItem = NSMenuItem()
            chartItem.isEnabled = true
            chartItem.representedObject = Self.usageHistoryChartID
            chartItem.toolTip = provider.rawValue
            submenu.addItem(chartItem)
            return true
        }

        // Provider-specific by design: burndown uses recorded Codex, Claude, and Kiro reset-scoped plan windows.
        // Keep the existing utilization history chart available below it.
        if provider == .codex || provider == .claude || provider == .kiro {
            let burndownView = QuotaBurndownChartMenuView(
                provider: provider,
                histories: histories,
                width: width)
            if burndownView.hasSeries {
                self.appendUsageHistoryChart(burndownView, to: submenu, provider: provider, width: width)
                submenu.addItem(.separator())
            }
        }

        let chartView = PlanUtilizationHistoryChartMenuView(
            provider: provider,
            histories: histories,
            snapshot: snapshot,
            width: width)
        self.appendUsageHistoryChart(chartView, to: submenu, provider: provider, width: width)
        return true
    }

    func usageHistorySource(
        for provider: UsageProvider) -> (selection: PlanUtilizationHistorySelection, snapshot: UsageSnapshot?)
    {
        if let account = self.store.claudeSwapMenuDisplay(
            for: provider,
            inspectedAccountID: self.claudeSwapInspectedAccountID)?.displayedAccount,
            self.fleetAccountProjection(for: provider).fallback == nil
        {
            return (self.store.claudeSwapPlanUtilizationHistorySelection(for: account), account.snapshot)
        }
        return (
            self.store.planUtilizationHistorySelection(for: provider),
            self.store.snapshot(for: provider.instanceID))
    }

    func appendHistoryChart(
        _ chartView: some View,
        to submenu: NSMenu,
        id: String,
        width: CGFloat)
    {
        let hosting = MenuHostingView(rootView: chartView)
        hosting.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width, height: self.hostedSubviewFittingHeight(for: hosting, width: width)))
        let item = NSMenuItem()
        item.view = hosting
        item.isEnabled = true
        item.representedObject = id
        submenu.addItem(item)
    }

    private func appendUsageHistoryChart(
        _ chartView: some View,
        to submenu: NSMenu,
        provider: UsageProvider,
        width: CGFloat)
    {
        let hosting = UsageHistoryMenuHostingView(rootView: chartView.codexBarLocalized())
        hosting.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width, height: self.hostedSubviewFittingHeight(for: hosting, width: width)))

        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = true
        chartItem.representedObject = Self.usageHistoryChartID
        chartItem.toolTip = provider.rawValue
        submenu.addItem(chartItem)
    }
}
