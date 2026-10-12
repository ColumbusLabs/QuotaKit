import Foundation

/// What the status item shows for one provider while the menu is closed: the full app's default "brand icon with
/// percent" mode (`MenuBarDisplayMode.percent`, `MenuBarMetricPreference.automatic`, bars showing what's left).
public enum MenuBarText {
    /// `MenuBarMetricWindowResolver.automaticWindow`: an exhausted window first, otherwise the session window,
    /// otherwise the weekly one. Windows past their reset count as projected (068 §5.3).
    public static func window(for state: ProviderState, now: Date) -> QuotaWindow? {
        let windows = state.projected(at: now).windows
        if let exhausted = windows.first(where: { $0.usedPercent >= 100 }) {
            return exhausted
        }
        return windows.first { $0.lane == .session } ?? windows.first { $0.lane == .weekly }
    }

    /// "11%", the remaining share as `UsageFormatter.percentString` formats it, or nil before the first fetch.
    public static func percent(for state: ProviderState, now: Date) -> String? {
        self.window(for: state, now: now).map { CardPresentation.percentText($0.remainingPercent) }
    }
}
