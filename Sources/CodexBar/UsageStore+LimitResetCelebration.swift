import CodexBarCore
import Foundation

extension UsageStore {
    private nonisolated static let limitResetThreshold = 1.0
    private nonisolated static let claudeWeeklyRecoveryObservationCount = 2

    struct LimitResetDetectorState: Codable, Equatable {
        let wasAboveThreshold: Bool
        let lastObservedAt: Date
        let sourceRawValue: String?
        var resetBoundary: Date?
        var recoveryAboveThresholdCount: Int?
        /// A confirmed Codex rolling window moved before the previous boundary elapsed.
        var codexEarlyWeeklyResetPending: Bool
        /// Identity-less Claude CLI samples share one detector key and can be transient.
        /// Require a second low sample before celebrating an apparent reset from that key.
        var pendingLowConfirmation: Bool

        init(
            wasAboveThreshold: Bool,
            lastObservedAt: Date,
            sourceRawValue: String?,
            resetBoundary: Date? = nil,
            recoveryAboveThresholdCount: Int? = nil,
            codexEarlyWeeklyResetPending: Bool = false,
            pendingLowConfirmation: Bool = false)
        {
            self.wasAboveThreshold = wasAboveThreshold
            self.lastObservedAt = lastObservedAt
            self.sourceRawValue = sourceRawValue
            self.resetBoundary = resetBoundary
            self.recoveryAboveThresholdCount = recoveryAboveThresholdCount
            self.codexEarlyWeeklyResetPending = codexEarlyWeeklyResetPending
            self.pendingLowConfirmation = pendingLowConfirmation
        }

        private enum CodingKeys: String, CodingKey {
            case wasAboveThreshold
            case lastObservedAt
            case sourceRawValue
            case resetBoundary
            case recoveryAboveThresholdCount
            case codexEarlyWeeklyResetPending
            case pendingLowConfirmation
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.wasAboveThreshold = try container.decode(Bool.self, forKey: .wasAboveThreshold)
            self.lastObservedAt = try container.decode(Date.self, forKey: .lastObservedAt)
            self.sourceRawValue = try container.decodeIfPresent(String.self, forKey: .sourceRawValue)
            self.resetBoundary = try container.decodeIfPresent(Date.self, forKey: .resetBoundary)
            self.recoveryAboveThresholdCount = try container.decodeIfPresent(
                Int.self,
                forKey: .recoveryAboveThresholdCount)
            self.codexEarlyWeeklyResetPending = try container.decodeIfPresent(
                Bool.self,
                forKey: .codexEarlyWeeklyResetPending) ?? false
            self.pendingLowConfirmation = try container.decodeIfPresent(
                Bool.self,
                forKey: .pendingLowConfirmation) ?? false
        }
    }

    struct LimitResetDetectionContext {
        let provider: UsageProvider
        let account: ProviderTokenAccount?
        let snapshot: UsageSnapshot
        let accountKey: String?
        let capturedAt: Date
        let codexLimitResetOwnerKey: CodexLimitResetOwnerKey?
        let codexSuppressesWeeklyResetCelebration: Bool
    }

    struct LimitResetObservation {
        let usedPercent: Double
        let observedAt: Date
        let resetBoundary: Date?
        let source: SessionQuotaWindowSource?
    }

    struct LimitResetDetectionDescriptor {
        let seriesName: PlanUtilizationSeriesName
        let defaultsKey: String
        let resetKind: String
    }

    func postLimitResetCelebrationIfNeeded(
        states: inout [String: LimitResetDetectorState],
        context: LimitResetDetectionContext,
        descriptor: LimitResetDetectionDescriptor,
        observation: LimitResetObservation?)
    {
        guard let observation else { return }

        guard let accountIdentifier = self.limitResetAccountIdentifier(
            provider: context.provider,
            account: context.account,
            snapshot: context.snapshot,
            accountKey: context.accountKey,
            codexLimitResetOwnerKey: context.codexLimitResetOwnerKey)
        else {
            return
        }
        let detectorKey = Self.limitResetDetectorStateKey(
            provider: context.provider,
            accountIdentifier: accountIdentifier)
        let requiresLowConfirmation = context.provider == .claude
            && accountIdentifier == context.provider.rawValue
        let currentUsed = observation.usedPercent
        let currentObservedAt = observation.observedAt
        let wasAboveThreshold = currentUsed > Self.limitResetThreshold
        if let existingState = states[detectorKey],
           currentObservedAt <= existingState.lastObservedAt
        {
            return
        }

        let previousState = states[detectorKey]
        let isCodexWeekly = context.provider == .codex && descriptor.seriesName == .weekly
        let codexEarlyWeeklyResetPending = previousState?.codexEarlyWeeklyResetPending ?? false
        let claudeWeeklyRecoveryPending = Self.hasClaudeWeeklyRecoveryPending(context, descriptor, previousState)
        let sourceRawValue = observation.source?.rawValue
        let sourceChanged = descriptor.seriesName == .session && previousState?.sourceRawValue != nil
            && previousState?.sourceRawValue != sourceRawValue
        let resetBoundaryAllowsPost = if descriptor.seriesName == .session {
            Self.limitResetBoundaryAdvanced(
                previous: previousState?.resetBoundary,
                current: observation.resetBoundary)
        } else if context.provider == .codex, descriptor.seriesName == .weekly {
            Self.codexWeeklyResetBoundaryAllowsPost(
                previous: previousState?.resetBoundary,
                current: observation.resetBoundary,
                observedAt: currentObservedAt,
                suppressesWeeklyResetCelebration: context.codexSuppressesWeeklyResetCelebration,
                hasPendingEarlyRollingWindow: codexEarlyWeeklyResetPending)
        } else {
            true
        }
        let crossedBelowThreshold = !sourceChanged && previousState?.wasAboveThreshold == true && !wasAboveThreshold
        let confirmingLowSample = !sourceChanged && previousState?.pendingLowConfirmation == true && !wasAboveThreshold
        let shouldPost = if requiresLowConfirmation {
            confirmingLowSample && !claudeWeeklyRecoveryPending
        } else {
            crossedBelowThreshold && resetBoundaryAllowsPost && !claudeWeeklyRecoveryPending
        }
        let suppressedGuardedCrossing = crossedBelowThreshold && !resetBoundaryAllowsPost
        let shouldAwaitLowConfirmation = requiresLowConfirmation
            && crossedBelowThreshold
            && !confirmingLowSample
            && resetBoundaryAllowsPost
            && !claudeWeeklyRecoveryPending
        // Sessions and premature Codex rolling-window observations retain the last known boundary so a
        // genuine reset can still trigger once after the prior boundary has elapsed.
        let shouldPreserveBoundary = !sourceChanged && !resetBoundaryAllowsPost
            && (descriptor.seriesName == .session || previousState?.resetBoundary != nil)
        let shouldPreserveBaseline = suppressedGuardedCrossing
        let previousRecoveryCount = previousState?.recoveryAboveThresholdCount ?? 0
        let nextRecoveryCount = if claudeWeeklyRecoveryPending {
            wasAboveThreshold ? previousRecoveryCount + 1 : 0
        } else {
            0
        }
        let claudeWeeklyRecoveryConfirmed = claudeWeeklyRecoveryPending
            && nextRecoveryCount >= Self.claudeWeeklyRecoveryObservationCount
        let nextWasAboveThreshold = if claudeWeeklyRecoveryPending {
            claudeWeeklyRecoveryConfirmed
        } else if shouldPreserveBaseline || shouldAwaitLowConfirmation {
            true
        } else {
            wasAboveThreshold
        }
        let persistedRecoveryCount: Int? = if shouldPost {
            0
        } else if claudeWeeklyRecoveryPending, !claudeWeeklyRecoveryConfirmed {
            nextRecoveryCount
        } else {
            nil
        }
        let nextCodexEarlyWeeklyResetPending = isCodexWeekly && !shouldPost
            && (context.codexSuppressesWeeklyResetCelebration
                || (codexEarlyWeeklyResetPending
                    && !(previousState?.resetBoundary.map { currentObservedAt >= $0 } ?? false)))
        states[detectorKey] = LimitResetDetectorState(
            // A transient zero must not erase the baseline needed to recognize the real reset that follows.
            wasAboveThreshold: nextWasAboveThreshold,
            lastObservedAt: currentObservedAt,
            sourceRawValue: sourceRawValue,
            resetBoundary: shouldPreserveBoundary ? previousState?.resetBoundary : observation.resetBoundary,
            recoveryAboveThresholdCount: persistedRecoveryCount,
            codexEarlyWeeklyResetPending: nextCodexEarlyWeeklyResetPending,
            pendingLowConfirmation: shouldAwaitLowConfirmation)
        self.persistLimitResetDetectorStates(
            states,
            defaultsKey: descriptor.defaultsKey,
            logName: descriptor.resetKind)

        if claudeWeeklyRecoveryPending, wasAboveThreshold {
            CodexBarLog.logger(LogCategories.confetti).debug(
                "Confirming Claude weekly usage recovery after celebration",
                metadata: [
                    "accountIdentifier": accountIdentifier,
                    "confirmationCount": String(nextRecoveryCount),
                    "observedAt": String(format: "%.0f", currentObservedAt.timeIntervalSince1970),
                ])
        }

        guard shouldPost else { return }
        let accountLabel = self.limitResetAccountLabel(
            provider: context.provider,
            account: context.account,
            snapshot: context.snapshot)

        CodexBarLog.logger(LogCategories.confetti).info(
            "\(descriptor.resetKind.capitalized) limit reset",
            metadata: [
                "provider": context.provider.rawValue,
                "accountIdentifier": accountIdentifier,
                "accountLabel": accountLabel ?? "",
                "resetKind": descriptor.resetKind,
                "usedPercent": String(format: "%.2f", currentUsed),
                "observedAt": String(format: "%.0f", currentObservedAt.timeIntervalSince1970),
            ])
        switch descriptor.seriesName {
        case .session:
            self.emitQuotaResetHook(
                provider: context.provider,
                window: .session,
                usedPercent: currentUsed,
                accountLabel: accountLabel)
            let event = SessionLimitResetEvent(
                provider: context.provider,
                accountIdentifier: accountIdentifier,
                accountLabel: accountLabel,
                usedPercent: currentUsed)
            NotificationCenter.default.post(name: .codexbarSessionLimitReset, object: event)
        case .weekly:
            self.emitQuotaResetHook(
                provider: context.provider,
                window: .weekly,
                usedPercent: currentUsed,
                accountLabel: accountLabel)
            let event = WeeklyLimitResetEvent(
                provider: context.provider,
                accountIdentifier: accountIdentifier,
                accountLabel: accountLabel,
                usedPercent: currentUsed)
            NotificationCenter.default.post(name: .codexbarWeeklyLimitReset, object: event)
        default:
            return
        }
    }

    private nonisolated static func codexWeeklyResetBoundaryAllowsPost(
        previous: Date?,
        current: Date?,
        observedAt: Date,
        suppressesWeeklyResetCelebration: Bool,
        hasPendingEarlyRollingWindow: Bool) -> Bool
    {
        guard limitResetBoundaryAdvanced(
            previous: previous,
            current: current,
            requiresPreviousBoundary: true),
            !suppressesWeeklyResetCelebration
        else {
            return false
        }
        guard hasPendingEarlyRollingWindow else { return true }
        return previous.map { observedAt >= $0 } ?? false
    }

    private nonisolated static func hasClaudeWeeklyRecoveryPending(
        _ context: LimitResetDetectionContext,
        _ descriptor: LimitResetDetectionDescriptor,
        _ state: LimitResetDetectorState?) -> Bool
    {
        context.provider == .claude
            && descriptor.seriesName == .weekly
            && state?.recoveryAboveThresholdCount != nil
    }
}
