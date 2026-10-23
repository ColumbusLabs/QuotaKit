import CodexBarSync
import Foundation

extension ProviderUsageSnapshot {
    /// Resolves the per-window quota warning config that `UsageCardView`
    /// should render for the given rate-window index.
    ///
    /// Mac's `QuotaWarningConfig` remains slot-based: session at index 0 and
    /// weekly at index 1. The one exception is Cursor's verified, single
    /// shared-weekly window, which occupies index 0 on Mac but uses weekly
    /// thresholds. Additional windows at index ≥ 2 have no warning config, so
    /// render without markers (`enabled = false`) rather than guessing.
    ///
    /// When `self.quotaWarnings` is nil (old Mac pre-0.25.2, or the
    /// provider didn't map to a known `UsageProvider` enum case on
    /// Mac), we still return Mac's documented defaults so the user
    /// sees a marker — matches the 16-cell device matrix proof in
    /// Research/020 §R7.4 (G3 + G7).
    func quotaWarning(forWindowIndex index: Int) -> (thresholds: [Int]?, enabled: Bool) {
        guard (0...1).contains(index) else { return (nil, false) }

        let windows = self.displayRateWindows
        let warningIndex = if index == 0,
            self.providerID == "cursor",
            windows.count == 1,
            let rateWindow = windows.first,
            rateWindow.windowMinutes == 10080,
            rateWindow.identity != .session,
            rateWindow.label != "Requests"
        {
            1
        } else {
            index
        }

        switch warningIndex {
        case 0:
            guard let cfg = self.quotaWarnings else {
                return (SyncQuotaWarningConfig.macDefaults, true)
            }
            return (cfg.resolvedSessionThresholds(), cfg.resolvedSessionEnabled())
        case 1:
            guard let cfg = self.quotaWarnings else {
                return (SyncQuotaWarningConfig.macDefaults, true)
            }
            return (cfg.resolvedWeeklyThresholds(), cfg.resolvedWeeklyEnabled())
        default:
            return (nil, false)
        }
    }
}
