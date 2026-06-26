import Foundation

/// Mirror of Mac's `QuotaWarningConfig` for wire sync (iOS 1.6.0 / Mac 0.25.2).
///
/// iOS is the **receiver** for quota warning settings — Mac owns the
/// configuration source-of-truth (`CodexBarConfig.quotaWarnings` + per-provider
/// overrides via `SettingsStore.quotaWarningEnabled(provider:, window:)` and
/// `.quotaWarningThresholds(provider:, window:)`). Mac SyncCoordinator
/// resolves the EFFECTIVE config per provider and ships it via
/// `ProviderUsageEnvelope.quotaWarnings` so iOS can render the same warning
/// markers as Mac's menu bar with zero iOS-local UI.
///
/// **Wire compatibility (16-cell device matrix)**:
/// - Field on `ProviderUsageEnvelope` is `Optional` and `decodeIfPresent` —
///   old iOS clients ignore unknown JSON fields and decode without crash
///   (Codable's default behavior; `decodeIfPresent` is belt-and-suspenders).
/// - Old Mac (pre-0.25.2) doesn't write this field, so new iOS sees `nil`
///   and falls back to Mac's documented defaults `[50, 20]` (= 50% / 20%
///   remaining ≈ 50% / 80% used). Visual marker still renders so the user
///   doesn't see an empty bar when one side is on the old version.
///
/// Thresholds semantic mirrors Mac (`Sources/CodexBarCore/Config/CodexBarConfig.swift`):
/// the array stores **remaining percent** values at which a warning should
/// fire. `[50, 20]` means "warn when 50% remaining" and again "when 20%
/// remaining". iOS converts to bar position (used%) by `100 - threshold`.
public struct SyncQuotaWarningConfig: Codable, Sendable, Equatable {
    /// Thresholds for the session-length window. Nil = inherit Mac's
    /// global default (`[50, 20]`).
    public let sessionThresholds: [Int]?
    /// Whether session-window warnings are enabled. Nil = inherit
    /// Mac's global default (true if thresholds set, else global).
    public let sessionEnabled: Bool?

    public let weeklyThresholds: [Int]?
    public let weeklyEnabled: Bool?

    public init(
        sessionThresholds: [Int]? = nil,
        sessionEnabled: Bool? = nil,
        weeklyThresholds: [Int]? = nil,
        weeklyEnabled: Bool? = nil)
    {
        self.sessionThresholds = sessionThresholds
        self.sessionEnabled = sessionEnabled
        self.weeklyThresholds = weeklyThresholds
        self.weeklyEnabled = weeklyEnabled
    }

    /// Mac's documented warning defaults (50% remaining = 50% used,
    /// 20% remaining = 80% used). Used by iOS when this config is
    /// absent (old Mac) OR when an override is nil (user accepted
    /// Mac's defaults for this provider/window).
    ///
    /// Mac source: `QuotaWarningThresholds.defaults` in `CodexBarConfig.swift`.
    /// Keep in lockstep with Mac — both sides must compute the same fallback
    /// when neither overrides.
    public static let macDefaults: [Int] = [50, 20]

    /// Effective thresholds for the session window, applying the
    /// Mac-side fallback chain (override → global → defaults).
    public func resolvedSessionThresholds() -> [Int] {
        Self.resolved(self.sessionThresholds)
    }

    public func resolvedWeeklyThresholds() -> [Int] {
        Self.resolved(self.weeklyThresholds)
    }

    /// True if session warnings are on. When the config explicitly
    /// sets `enabled = false`, return false; otherwise true so the
    /// default is "warnings are visible" (matches Mac's UX where
    /// having thresholds implies enabled).
    public func resolvedSessionEnabled() -> Bool {
        self.sessionEnabled ?? true
    }

    public func resolvedWeeklyEnabled() -> Bool {
        self.weeklyEnabled ?? true
    }

    private static func resolved(_ raw: [Int]?) -> [Int] {
        guard let raw, !raw.isEmpty else { return self.macDefaults }
        // Defensive sanitize: clamp to 0…99 and dedupe (mirrors Mac's
        // QuotaWarningThresholds.sanitized).
        let clamped = raw.map { max(0, min(99, $0)) }
        return Array(Set(clamped)).sorted(by: >) // descending so [50, 20]
    }
}
