import AppKit
import CodexBarCore

extension StatusItemController {
    func makeOverviewRowSubmenu(
        provider: UsageProvider,
        model: UsageMenuCardView.Model,
        width: CGFloat) -> NSMenu?
    {
        if provider == .openai,
           let submenu = self.makeOpenAIAPIUsageSubmenu(provider: provider, width: width)
        {
            return submenu
        }
        if provider == .zai,
           let submenu = self.makeZaiUsageDetailsSubmenu(snapshot: self.store.snapshot(for: provider))
        {
            return submenu
        }
        if model.tokenUsage != nil,
           let submenu = self.makeCostHistorySubmenu(provider: provider, width: width)
        {
            return submenu
        }
        if let submenu = self.makeUsageHistorySubmenu(provider: provider, width: width) {
            return submenu
        }
        return self.makeStorageBreakdownSubmenu(provider: provider, width: width)
    }
}
