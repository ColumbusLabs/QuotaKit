import CodexBarCore
import Foundation

extension UsageStore {
    /// Normalizes detector state for an accepted correction after account snapshots commit.
    /// This path deliberately leaves plan-utilization history and account selection untouched.
    func normalizeCodexWeeklyBoundaryCorrection(
        snapshot: UsageSnapshot,
        ownerKey: CodexLimitResetOwnerKey)
    {
        let capturedAt = snapshot.updatedAt
        let context = LimitResetDetectionContext(
            provider: .codex,
            account: nil,
            snapshot: snapshot,
            accountKey: nil,
            capturedAt: capturedAt,
            codexLimitResetOwnerKey: ownerKey,
            codexSuppressesWeeklyResetCelebration: false,
            codexCorrectsWeeklyBoundary: true)

        self.postLimitResetCelebrationIfNeeded(
            states: &self.sessionLimitResetDetectorStates,
            context: context,
            descriptor: LimitResetDetectionDescriptor(
                seriesName: .session,
                defaultsKey: Self.sessionLimitResetDetectorDefaultsKey,
                resetKind: "session"),
            observation: Self.codexBoundaryDetectorObservation(
                for: CodexConsumerProjection.sourceRateWindow(for: .session, snapshot: snapshot),
                observedAt: capturedAt))
        self.postLimitResetCelebrationIfNeeded(
            states: &self.weeklyLimitResetDetectorStates,
            context: context,
            descriptor: LimitResetDetectionDescriptor(
                seriesName: .weekly,
                defaultsKey: Self.weeklyLimitResetDetectorDefaultsKey,
                resetKind: "weekly"),
            observation: Self.codexBoundaryDetectorObservation(
                for: CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: snapshot),
                observedAt: capturedAt))
    }

    private nonisolated static func codexBoundaryDetectorObservation(
        for window: RateWindow?,
        observedAt: Date) -> LimitResetObservation?
    {
        guard let window,
              !window.isSyntheticPlaceholder,
              let windowMinutes = window.windowMinutes,
              windowMinutes > 0,
              let usedPercent = self.clampedCodexBoundaryDetectorPercent(window.usedPercent)
        else {
            return nil
        }
        return LimitResetObservation(
            usedPercent: usedPercent,
            observedAt: observedAt,
            resetBoundary: window.resetsAt,
            source: nil)
    }

    private nonisolated static func clampedCodexBoundaryDetectorPercent(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return max(0, min(100, value))
    }
}
