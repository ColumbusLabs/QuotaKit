import CodexBarSync
import Foundation

enum MobileSettingsKeys {
    static let usageCostChartStyle = "usageCostChartStyle"
    static let dashboardCostChartStyle = "dashboardCostChartStyle"
    static let hidePersonalInfo = "hidePersonalInfo"
    static let openCostByDefault = "openCostByDefault"
    static let usagePercentDisplayMode = "usagePercentDisplayMode"
    static let showRemainingUsage = "showRemainingUsage"
    // iOS 1.7.0 — mirrors upstream v0.26.0 / v0.26.1 settings.
    /// When `true`, the warning tick-marks on each usage bar are
    /// suppressed (the quota warning notification still fires — only
    /// the visual marker is hidden). Mirrors the Mac toggle added in
    /// upstream PR #918.
    static let hideQuotaWarningMarkers = "hideQuotaWarningMarkers"
    /// When `true`, the Settings / About page shows a "Provider
    /// changelogs" section linking to upstream provider release notes
    /// (Codex CLI, Claude Code, Gemini CLI). Mirrors upstream PR #929.
    static let showProviderChangelogLinks = "showProviderChangelogLinks"
}

enum UsagePercentDisplayMode: String, CaseIterable, Identifiable {
    case used
    case remaining

    var id: String {
        self.rawValue
    }

    var percentSuffix: String {
        switch self {
        case .used:
            String(localized: "used")
        case .remaining:
            String(localized: "left")
        }
    }

    func displayedPercent(for window: SyncRateWindow) -> Double {
        switch self {
        case .used:
            window.usedPercent
        case .remaining:
            window.remainingPercent
        }
    }

    func progressFraction(for window: SyncRateWindow) -> Double {
        min(max(self.displayedPercent(for: window) / 100, 0), 1)
    }

    func percentageValueText(for window: SyncRateWindow) -> String {
        let roundedValue = Int(self.displayedPercent(for: window).rounded())
        return "\(roundedValue)%"
    }

    func percentageText(for window: SyncRateWindow) -> String {
        "\(self.percentageValueText(for: window)) \(self.percentSuffix)"
    }
}
