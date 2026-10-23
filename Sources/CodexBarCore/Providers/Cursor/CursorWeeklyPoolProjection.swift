#if os(macOS) || os(Linux)
import Foundation

struct CursorWeeklyPoolProjection {
    let primary: RateWindow?
    let secondary: RateWindow?
    let extraRateWindows: [NamedRateWindow]?
}

extension CursorStatusSnapshot {
    func weeklyPoolProjection(
        sandWindow: NamedRateWindow?,
        hasRequestQuota: Bool,
        standardWindows: (primary: RateWindow?, secondary: RateWindow?),
        now: Date) -> CursorWeeklyPoolProjection
    {
        // Unified token plans use the current shared weekly pool instead of stale monthly Auto/API lanes.
        let sharedWeeklyPool = !hasRequestQuota && self.sandUsage?.isUnified == true
            && sandWindow?.window.windowMinutes == 10080
            && sandWindow?.window.resetsAt.map { $0 > now } == true ? sandWindow?.window : nil
        let hidesMonthlyBreakdown = hasRequestQuota || sharedWeeklyPool != nil
        let extraRateWindows: [NamedRateWindow]? = if hidesMonthlyBreakdown {
            nil
        } else {
            sandWindow.map { [$0] }
        }
        return CursorWeeklyPoolProjection(
            primary: sharedWeeklyPool ?? standardWindows.primary,
            secondary: hidesMonthlyBreakdown ? nil : standardWindows.secondary,
            extraRateWindows: extraRateWindows)
    }
}
#endif
