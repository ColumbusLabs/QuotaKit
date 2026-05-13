import CodexBarSync
import Foundation

extension ProviderUsageSnapshot {
    /// Resolves the per-window quota warning config that `UsageCardView`
    /// should render for the given rate-window index.
    ///
    /// Mac's `QuotaWarningConfig` only knows two semantic windows:
    /// `session` (index 0) and `weekly` (index 1). Providers with
    /// additional rate windows (e.g. Perplexity's three-tier plan)
    /// expose them at index ≥ 2; the design choice mirrors Mac, where
    /// these extra windows have no warning config — we render the bar
    /// without markers (`enabled = false`) rather than guessing.
    ///
    /// When `self.quotaWarnings` is nil (old Mac pre-0.25.2, or the
    /// provider didn't map to a known `UsageProvider` enum case on
    /// Mac), we still return Mac's documented defaults so the user
    /// sees a marker — matches the 16-cell device matrix proof in
    /// Research/020 §R7.4 (G3 + G7).
    func quotaWarning(forWindowIndex index: Int) -> (thresholds: [Int]?, enabled: Bool) {
        switch index {
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
