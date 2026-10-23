import CodexBarSync
import Foundation

extension ProviderUsageSnapshot {
    /// Resolves the per-window quota warning config that `UsageCardView`
    /// should render for the given rate-window index.
    ///
    /// Mac's `QuotaWarningConfig` only knows two semantic windows:
    /// `session` and `weekly`. Within the supported first two slots, use
    /// synced identity or a seven-day cadence when available; untyped legacy
    /// windows retain the session-at-0 / weekly-at-1 fallback. Additional
    /// windows at index ≥ 2 have no warning config, so render without markers
    /// (`enabled = false`) rather than guessing.
    ///
    /// When `self.quotaWarnings` is nil (old Mac pre-0.25.2, or the
    /// provider didn't map to a known `UsageProvider` enum case on
    /// Mac), we still return Mac's documented defaults so the user
    /// sees a marker — matches the 16-cell device matrix proof in
    /// Research/020 §R7.4 (G3 + G7).
    func quotaWarning(forWindowIndex index: Int) -> (thresholds: [Int]?, enabled: Bool) {
        guard (0...1).contains(index) else { return (nil, false) }

        let windows = self.displayRateWindows
        let rateWindow = windows.indices.contains(index) ? windows[index] : nil
        let warningIndex = if let identity = rateWindow?.identity {
            identity == .weekly ? 1 : 0
        } else if rateWindow?.windowMinutes == 10080 {
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
