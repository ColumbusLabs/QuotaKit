import CodexBarSync
import Foundation

/// One rate-limit window, for example Claude's 5-hour session or a weekly limit.
public struct QuotaWindow: Codable, Sendable, Equatable {
    public typealias Lane = SyncRateWindowIdentity

    /// Shown on the card: "Session", "Weekly", "Sonnet", or an Antigravity bucket name.
    public var label: String
    /// Which pace rules apply, and which slot the window fills on iOS.
    public var lane: Lane
    public var usedPercent: Double
    public var windowMinutes: Int
    public var resetsAt: Date?
    /// True when `usedPercent` and `resetsAt` come from local reset projection, not a fetch (068 §5.3).
    public var isProjected: Bool

    public init(
        label: String,
        lane: Lane,
        usedPercent: Double,
        windowMinutes: Int,
        resetsAt: Date?,
        isProjected: Bool = false)
    {
        self.label = label
        self.lane = lane
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.isProjected = isProjected
    }

    public var remainingPercent: Double {
        max(0, 100 - self.usedPercent)
    }

    /// Local reset projection (068 §5.3): once `now` reaches `resetsAt`, the window shows 0% used and its
    /// reset moves forward by whole window lengths, with no network call. Windows before their reset are
    /// returned unchanged.
    public func projected(at now: Date) -> QuotaWindow {
        guard let resetsAt, now >= resetsAt, self.windowMinutes > 0 else { return self }
        let length = TimeInterval(self.windowMinutes) * 60
        let elapsedPeriods = (now.timeIntervalSince(resetsAt) / length).rounded(.down) + 1
        var window = self
        window.usedPercent = 0
        window.resetsAt = resetsAt.addingTimeInterval(elapsedPeriods * length)
        window.isProjected = true
        return window
    }
}

extension [QuotaWindow] {
    /// The window that speaks for a lane in the menu bar, alerts and the iPhone's two bars. Antigravity has a
    /// window per model group in each lane, so the one with the least left wins (068 §4.3); other providers have
    /// one per lane (Claude's Sonnet window is a weekly extra and never stands in for Weekly).
    public func representative(_ lane: QuotaWindow.Lane, for provider: LiteProvider) -> QuotaWindow? {
        let matching = self.filter { $0.lane == lane }
        guard provider == .antigravity else { return matching.first }
        return matching.min { $0.remainingPercent < $1.remainingPercent }
    }
}
