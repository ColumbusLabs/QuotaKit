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

    /// Most Constrained style: the provider whose menu bar window has the least left. Providers without data are
    /// skipped; ties keep the earlier provider.
    public static func mostConstrained(_ states: [ProviderState], now: Date) -> ProviderState? {
        var best: (state: ProviderState, remaining: Double)?
        for state in states {
            guard let remaining = self.window(for: state, now: now)?.remainingPercent else { continue }
            if best.map({ remaining < $0.remaining }) ?? true {
                best = (state, remaining)
            }
        }
        return best?.state
    }

    /// Logos and Bars style: what's left of the session and weekly windows as fractions from 0 to 1, or nil for a
    /// lane the provider doesn't have.
    public struct Bars: Equatable, Sendable {
        public var session: Double?
        public var weekly: Double?
        /// Depleted or at 95% used or more: the bars are drawn in red (068 §7.3).
        public var isCritical: Bool

        public init(session: Double?, weekly: Double?, isCritical: Bool) {
            self.session = session
            self.weekly = weekly
            self.isCritical = isCritical
        }
    }

    public static func bars(for state: ProviderState, now: Date) -> Bars? {
        let windows = state.projected(at: now).windows
        guard !windows.isEmpty else { return nil }
        func remaining(_ lane: QuotaWindow.Lane) -> Double? {
            windows.first { $0.lane == lane }.map { $0.remainingPercent / 100 }
        }
        return Bars(
            session: remaining(.session),
            weekly: remaining(.weekly),
            isCritical: windows.contains { $0.usedPercent >= 95 })
    }
}
