import CodexBarCore
import Foundation

extension UsageStore {
    typealias CodexWeeklyConfirmationFetch = @Sendable () async -> ProviderFetchOutcome

    struct CodexWeeklyResetPublicationAdmission {
        let outcome: ProviderFetchOutcome?
        let pendingCandidate: CodexWeeklyResetPublicationCandidate?
        /// Keeps a confirmed early rolling window from emitting a premature weekly-reset event.
        let suppressesWeeklyResetCelebration: Bool
        /// A nil publication alone cannot distinguish a withheld success from a failed confirmation.
        let withheldSuccess: ProviderFetchResult?

        init(
            outcome: ProviderFetchOutcome?,
            pendingCandidate: CodexWeeklyResetPublicationCandidate?,
            suppressesWeeklyResetCelebration: Bool = false,
            withheldSuccess: ProviderFetchResult? = nil)
        {
            self.outcome = outcome
            self.pendingCandidate = pendingCandidate
            self.suppressesWeeklyResetCelebration = suppressesWeeklyResetCelebration
            self.withheldSuccess = withheldSuccess
        }
    }

    struct CodexWeeklyResetPublicationTrace {
        let previousSnapshot: UsageSnapshot?
        let missingWindowBackfillSnapshot: UsageSnapshot?
        let publicationBaseline: UsageSnapshot?
        let initialSnapshot: UsageSnapshot
        let confirmationSnapshot: UsageSnapshot?
    }

    private struct CodexMissingWeeklyAdmissionInput {
        let rawInitialSnapshot: UsageSnapshot
        let previousSnapshot: UsageSnapshot?
        let publicationBaseline: UsageSnapshot?
        let missingWindowBackfillSnapshot: UsageSnapshot?
        let publicationInitialOutcome: ProviderFetchOutcome
        let pendingCandidate: CodexWeeklyResetPublicationCandidate?
    }

    nonisolated static func codexOutcomeAdmittedForPublication( // swiftlint:disable:this function_body_length
        initialOutcome: ProviderFetchOutcome,
        previousSnapshot: UsageSnapshot?,
        previousSourceLabel: String?,
        missingWindowBackfillSnapshot: UsageSnapshot?,
        pendingCandidate: CodexWeeklyResetPublicationCandidate? = nil,
        observedAt: Date = CodexWeeklyResetConfirmation.observationDate,
        fetchConfirmation: @escaping CodexWeeklyConfirmationFetch) async -> CodexWeeklyResetPublicationAdmission
    {
        var candidateForRetry = Self.codexRetainedPendingCandidate(
            pendingCandidate,
            observedAt: observedAt)
        guard case let .success(rawInitialResult) = initialOutcome.result else {
            return CodexWeeklyResetPublicationAdmission(outcome: initialOutcome, pendingCandidate: candidateForRetry)
        }
        let rawInitialSnapshot = rawInitialResult.usage.scoped(to: .codex)
        let publicationBaseline = [previousSnapshot, missingWindowBackfillSnapshot]
            .compactMap(\.self)
            .max { $0.updatedAt < $1.updatedAt }
        let publicationInitialOutcome = if let missingWindowBackfillSnapshot {
            initialOutcome.replacingUsage(Self.codexBackfillingResetWindows(
                rawInitialSnapshot,
                from: missingWindowBackfillSnapshot))
        } else {
            initialOutcome
        }

        if CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: rawInitialSnapshot) == nil {
            return Self.codexMissingWeeklyAdmission(input: CodexMissingWeeklyAdmissionInput(
                rawInitialSnapshot: rawInitialSnapshot,
                previousSnapshot: previousSnapshot,
                publicationBaseline: publicationBaseline,
                missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
                publicationInitialOutcome: publicationInitialOutcome,
                pendingCandidate: candidateForRetry))
        }

        let initialDecision = CodexWeeklyResetConfirmation.initialDecision(
            previous: publicationBaseline,
            initial: rawInitialSnapshot)
        Self.logCodexWeeklyResetInitialDecision(
            initialDecision,
            previousSnapshot: previousSnapshot,
            missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
            publicationBaseline: publicationBaseline,
            initialSnapshot: rawInitialSnapshot)
        switch initialDecision {
        case .publishInitial:
            return CodexWeeklyResetPublicationAdmission(
                outcome: publicationInitialOutcome,
                pendingCandidate: nil)
        case .preservePrevious:
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: Self.codexCandidateAfterPreservedInitial(
                    candidateForRetry,
                    previousSnapshot: previousSnapshot,
                    initialSnapshot: rawInitialSnapshot,
                    initialResult: rawInitialResult,
                    observedAt: observedAt),
                withheldSuccess: rawInitialResult)
        case .requiresConfirmation:
            break
        }

        if let pendingCandidate = candidateForRetry {
            let delayedEvaluation = CodexWeeklyResetConfirmation.evaluateDelayedCandidate(
                previous: previousSnapshot,
                candidate: pendingCandidate,
                current: rawInitialSnapshot,
                currentIsExactOAuth: Self.isExactCodexOAuthResult(rawInitialResult),
                observedAt: observedAt)
            Self.logCodexWeeklyResetPublicationDecision(
                stage: "delayedConfirmation",
                decision: String(describing: delayedEvaluation.decision),
                reason: delayedEvaluation.reason,
                trace: CodexWeeklyResetPublicationTrace(
                    previousSnapshot: previousSnapshot,
                    missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
                    publicationBaseline: publicationBaseline,
                    initialSnapshot: rawInitialSnapshot,
                    confirmationSnapshot: pendingCandidate.snapshot))
            switch delayedEvaluation.decision {
            case .publishCurrent:
                return CodexWeeklyResetPublicationAdmission(
                    outcome: publicationInitialOutcome,
                    pendingCandidate: nil)
            case .retainCandidate:
                return CodexWeeklyResetPublicationAdmission(
                    outcome: nil,
                    pendingCandidate: pendingCandidate,
                    withheldSuccess: rawInitialResult)
            case .discardCandidate:
                candidateForRetry = nil
            }
        }

        guard !Task.isCancelled else {
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: candidateForRetry)
        }
        let confirmationOutcome = await fetchConfirmation()
        guard !Task.isCancelled,
              case let .success(confirmationResult) = confirmationOutcome.result
        else {
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: candidateForRetry)
        }
        let confirmationSnapshot = confirmationResult.usage.scoped(to: .codex)
        let confirmationTrace = CodexWeeklyResetPublicationTrace(
            previousSnapshot: previousSnapshot,
            missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
            publicationBaseline: publicationBaseline,
            initialSnapshot: rawInitialSnapshot,
            confirmationSnapshot: confirmationSnapshot)
        guard CodexIdentityResolver.normalizeEmail(rawInitialSnapshot.accountEmail(for: .codex)) ==
            CodexIdentityResolver.normalizeEmail(confirmationSnapshot.accountEmail(for: .codex))
        else {
            Self.logCodexWeeklyResetPublicationDecision(
                stage: "confirmation",
                decision: "preservePreviousAccountMismatch",
                trace: confirmationTrace)
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: nil)
        }
        let confirmationDecision = CodexWeeklyResetConfirmation.confirmationDecision(
            previous: publicationBaseline,
            previousEvidence: previousSnapshot,
            initial: rawInitialSnapshot,
            confirmation: confirmationSnapshot)
        Self.logCodexWeeklyResetPublicationDecision(
            stage: "confirmation",
            decision: String(describing: confirmationDecision),
            trace: confirmationTrace)
        switch confirmationDecision {
        case .publishConfirmation:
            let outcome = if let missingWindowBackfillSnapshot {
                confirmationOutcome.replacingUsage(Self.codexBackfillingResetWindows(
                    confirmationSnapshot,
                    from: missingWindowBackfillSnapshot))
            } else {
                confirmationOutcome
            }
            return CodexWeeklyResetPublicationAdmission(
                outcome: outcome,
                pendingCandidate: nil)
        case .publishRollingWindowConfirmation:
            let outcome = if let missingWindowBackfillSnapshot {
                confirmationOutcome.replacingUsage(Self.codexBackfillingResetWindows(
                    confirmationSnapshot,
                    from: missingWindowBackfillSnapshot))
            } else {
                confirmationOutcome
            }
            CodexBarLog.logger(LogCategories.codexRPC).debug(
                "Publishing confirmed Codex rolling-window usage without a reset event",
                metadata: [
                    "initialObservedAt": String(format: "%.0f", rawInitialSnapshot.updatedAt.timeIntervalSince1970),
                    "confirmationObservedAt": String(
                        format: "%.0f",
                        confirmationSnapshot.updatedAt.timeIntervalSince1970),
                ])
            return CodexWeeklyResetPublicationAdmission(
                outcome: outcome,
                pendingCandidate: nil,
                suppressesWeeklyResetCelebration: true)
        case .publishManualResetConfirmation:
            let outcome = if let missingWindowBackfillSnapshot {
                confirmationOutcome.replacingUsage(Self.codexBackfillingResetWindows(
                    confirmationSnapshot,
                    from: missingWindowBackfillSnapshot))
            } else {
                confirmationOutcome
            }
            return CodexWeeklyResetPublicationAdmission(
                outcome: outcome,
                pendingCandidate: nil)
        case .preservePrevious:
            let creation = CodexWeeklyResetConfirmation.evaluateDelayedCandidateCreation(
                previous: previousSnapshot,
                initial: rawInitialSnapshot,
                confirmation: confirmationSnapshot,
                sourceEvidence: .init(
                    previousIsExactOAuth: previousSourceLabel?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() == "oauth",
                    initialIsExactOAuth: Self.isExactCodexOAuthResult(rawInitialResult),
                    confirmationIsExactOAuth: Self.isExactCodexOAuthResult(confirmationResult)),
                observedAt: observedAt)
            Self.logCodexWeeklyResetPublicationDecision(
                stage: "candidateCreation",
                decision: creation.candidate == nil ? "rejected" : "created",
                reason: creation.reason,
                trace: confirmationTrace)
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: creation.candidate,
                withheldSuccess: confirmationResult)
        }
    }

    private nonisolated static func codexMissingWeeklyAdmission(
        input: CodexMissingWeeklyAdmissionInput) -> CodexWeeklyResetPublicationAdmission
    {
        let rawInitialSnapshot = input.rawInitialSnapshot
        let withheldSuccess: ProviderFetchResult? = if case let .success(result) = input.publicationInitialOutcome
            .result
        {
            result
        } else {
            nil
        }
        guard rawInitialSnapshot.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              input.previousSnapshot.map({
                  $0.updatedAt.timeIntervalSinceReferenceDate.isFinite &&
                      rawInitialSnapshot.updatedAt > $0.updatedAt
              }) ?? true,
              input.missingWindowBackfillSnapshot.map({
                  $0.updatedAt.timeIntervalSinceReferenceDate.isFinite &&
                      rawInitialSnapshot.updatedAt >= $0.updatedAt
              }) ?? true
        else {
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: input.pendingCandidate,
                withheldSuccess: withheldSuccess)
        }
        if CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: input.publicationBaseline) != nil,
           case let .success(publicationResult) = input.publicationInitialOutcome.result,
           CodexConsumerProjection.sourceRateWindow(
               for: .weekly,
               snapshot: publicationResult.usage.scoped(to: .codex)) == nil
        {
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: input.pendingCandidate,
                withheldSuccess: withheldSuccess)
        }
        return CodexWeeklyResetPublicationAdmission(
            outcome: input.publicationInitialOutcome,
            pendingCandidate: nil)
    }

    private nonisolated static func codexCandidateAfterPreservedInitial(
        _ candidate: CodexWeeklyResetPublicationCandidate?,
        previousSnapshot: UsageSnapshot?,
        initialSnapshot: UsageSnapshot,
        initialResult: ProviderFetchResult,
        observedAt: Date) -> CodexWeeklyResetPublicationCandidate?
    {
        guard let candidate else { return nil }
        let evaluation = CodexWeeklyResetConfirmation.evaluateDelayedCandidate(
            previous: previousSnapshot,
            candidate: candidate,
            current: initialSnapshot,
            currentIsExactOAuth: Self.isExactCodexOAuthResult(initialResult),
            observedAt: observedAt)
        self.logCodexWeeklyResetReason(
            stage: "candidateRevalidation",
            decision: String(describing: evaluation.decision),
            reason: evaluation.reason)
        return evaluation.decision == .discardCandidate ? nil : candidate
    }

    private nonisolated static func codexRetainedPendingCandidate(
        _ candidate: CodexWeeklyResetPublicationCandidate?,
        observedAt: Date) -> CodexWeeklyResetPublicationCandidate?
    {
        guard let candidate else { return nil }
        guard let reason = CodexWeeklyResetConfirmation.delayedCandidateRejection(
            candidate,
            observedAt: observedAt)
        else { return candidate }
        Self.logCodexWeeklyResetReason(
            stage: "candidateRetention",
            decision: "discardCandidate",
            reason: reason)
        return nil
    }

    private nonisolated static func logCodexWeeklyResetInitialDecision(
        _ decision: CodexWeeklyResetConfirmation.InitialDecision,
        previousSnapshot: UsageSnapshot?,
        missingWindowBackfillSnapshot: UsageSnapshot?,
        publicationBaseline: UsageSnapshot?,
        initialSnapshot: UsageSnapshot)
    {
        guard decision != .publishInitial else { return }
        self.logCodexWeeklyResetPublicationDecision(
            stage: "initial",
            decision: String(describing: decision),
            trace: CodexWeeklyResetPublicationTrace(
                previousSnapshot: previousSnapshot,
                missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
                publicationBaseline: publicationBaseline,
                initialSnapshot: initialSnapshot,
                confirmationSnapshot: nil))
    }

    private nonisolated static func isExactCodexOAuthResult(_ result: ProviderFetchResult) -> Bool {
        guard case .oauth = result.strategyKind else { return false }
        return result.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "oauth"
            && result.usage.scoped(to: .codex).dataConfidence == .exact
    }

    private nonisolated static func logCodexWeeklyResetPublicationDecision(
        stage: String,
        decision: String,
        reason: CodexWeeklyResetConfirmation.Reason? = nil,
        trace: CodexWeeklyResetPublicationTrace)
    {
        let metadata = Self.codexWeeklyResetPublicationMetadata(
            stage: stage,
            decision: decision,
            reason: reason,
            trace: trace)
        CodexBarLog.logger(LogCategories.provider(.codex, scope: "weekly-reset-publication")).debug(
            "Codex weekly reset publication decision",
            metadata: metadata)
    }

    nonisolated static func codexWeeklyResetPublicationMetadata(
        stage: String,
        decision: String,
        reason: CodexWeeklyResetConfirmation.Reason? = nil,
        trace: CodexWeeklyResetPublicationTrace) -> [String: String]
    {
        var metadata = Self.codexWeeklyResetDiagnosticMetadata(
            stage: stage,
            decision: decision,
            reason: reason)
        Self.appendCodexWeeklyResetTrace(
            snapshot: trace.previousSnapshot,
            prefix: "previousSnapshot",
            metadata: &metadata)
        Self.appendCodexWeeklyResetTrace(
            snapshot: trace.missingWindowBackfillSnapshot,
            prefix: "missingWindowBackfillSnapshot",
            metadata: &metadata)
        Self.appendCodexWeeklyResetTrace(
            snapshot: trace.publicationBaseline,
            prefix: "publicationBaseline",
            metadata: &metadata)
        Self.appendCodexWeeklyResetTrace(
            snapshot: trace.initialSnapshot,
            prefix: "initial",
            metadata: &metadata)
        Self.appendCodexWeeklyResetTrace(
            snapshot: trace.confirmationSnapshot,
            prefix: "confirmation",
            metadata: &metadata)
        metadata["initialConfirmationAccountMatches"] = Self.codexWeeklyResetCompatibility(
            snapshots: [trace.initialSnapshot, trace.confirmationSnapshot],
            value: { CodexIdentityResolver.normalizeEmail($0.accountEmail(for: .codex)) })
        metadata["stableAccountCompatible"] = Self.codexWeeklyResetCompatibility(
            snapshots: [trace.previousSnapshot, trace.initialSnapshot, trace.confirmationSnapshot],
            value: { CodexIdentityResolver.normalizeEmail($0.accountEmail(for: .codex)) })
        metadata["stablePlanCompatible"] = Self.codexWeeklyResetCompatibility(
            snapshots: [trace.previousSnapshot, trace.initialSnapshot, trace.confirmationSnapshot],
            value: { snapshot in
                snapshot.loginMethod(for: .codex)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            })
        return metadata
    }

    private nonisolated static func logCodexWeeklyResetReason(
        stage: String,
        decision: String,
        reason: CodexWeeklyResetConfirmation.Reason)
    {
        CodexBarLog.logger(LogCategories.provider(.codex, scope: "weekly-reset-publication")).debug(
            "Codex weekly reset candidate diagnostic",
            metadata: self.codexWeeklyResetDiagnosticMetadata(
                stage: stage,
                decision: decision,
                reason: reason))
    }

    nonisolated static func codexWeeklyResetDiagnosticMetadata(
        stage: String,
        decision: String,
        reason: CodexWeeklyResetConfirmation.Reason? = nil) -> [String: String]
    {
        var metadata = ["stage": stage, "decision": decision]
        if let reason { metadata["reason"] = reason.rawValue }
        return metadata
    }

    private nonisolated static func codexWeeklyResetCompatibility(
        snapshots: [UsageSnapshot?],
        value: (UsageSnapshot) -> String?) -> String
    {
        let values = snapshots.map { $0.flatMap(value) }
        guard let first = values.compactMap(\.self).first,
              values.allSatisfy({ $0 != nil })
        else {
            return "unknown"
        }
        return String(values.allSatisfy { $0 == first })
    }

    private nonisolated static func appendCodexWeeklyResetTrace(
        snapshot: UsageSnapshot?,
        prefix: String,
        metadata: inout [String: String])
    {
        guard let snapshot else {
            metadata["\(prefix).present"] = "false"
            return
        }
        let weekly = CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: snapshot)
        metadata["\(prefix).present"] = "true"
        metadata["\(prefix).updatedAt"] = String(format: "%.0f", snapshot.updatedAt.timeIntervalSince1970)
        metadata["\(prefix).weeklyUsedPercent"] = weekly.map { String(format: "%.3f", $0.usedPercent) } ?? "nil"
        metadata["\(prefix).resetBoundary"] = weekly?.resetsAt.map {
            String(format: "%.0f", $0.timeIntervalSince1970)
        } ?? "nil"
        metadata["\(prefix).accountKnown"] = String(
            CodexIdentityResolver.normalizeEmail(snapshot.accountEmail(for: .codex)) != nil)
        metadata["\(prefix).planKnown"] = String(snapshot.loginMethod(for: .codex) != nil)
        metadata["\(prefix).creditsPresent"] = String(snapshot.codexResetCredits != nil)
        metadata["\(prefix).creditsAvailableCount"] = snapshot.codexResetCredits.map {
            String($0.availableCount)
        } ?? "nil"
    }
}
