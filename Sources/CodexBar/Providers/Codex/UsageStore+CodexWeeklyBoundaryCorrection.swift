import CodexBarCore
import Foundation

extension UsageStore {
    /// Boundary corrections have separate evidence from high-to-low reset confirmation.
    /// The account/workspace refresh guard remains the publication authority in the caller.
    nonisolated static func codexOutcomeAdmittedForPublication(
        initialOutcome: ProviderFetchOutcome,
        previousSnapshot: UsageSnapshot?,
        previousSourceLabel: String?,
        missingWindowBackfillSnapshot: UsageSnapshot?,
        pendingCandidate: CodexWeeklyResetPublicationCandidate? = nil,
        weeklyBoundaryEvidence: CodexWeeklyBoundaryEvidence? = nil,
        observedAt: Date = CodexWeeklyResetConfirmation.observationDate,
        fetchConfirmation: @escaping CodexWeeklyConfirmationFetch) async -> CodexWeeklyResetPublicationAdmission
    {
        var evidence = weeklyBoundaryEvidence ?? CodexWeeklyBoundaryEvidence()
        guard case let .success(result) = initialOutcome.result else {
            let admission = await Self.codexOutcomeAdmittedByResetPolicy(
                initialOutcome: initialOutcome,
                previousSnapshot: previousSnapshot,
                previousSourceLabel: previousSourceLabel,
                missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
                pendingCandidate: pendingCandidate,
                observedAt: observedAt,
                fetchConfirmation: fetchConfirmation)
            return Self.codexAdmission(admission, evidence: evidence)
        }
        let current = result.usage.scoped(to: .codex)
        let comparableBaseline = previousSnapshot.map {
            CodexWeeklyResetConfirmation.accountsAreCompatible($0, current)
                && CodexWeeklyResetConfirmation.plansAreCompatible($0, current)
        } ?? false
        if !comparableBaseline {
            evidence = CodexWeeklyBoundaryEvidence()
        }
        let boundary = CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: current)?.resetsAt
        if let boundary, CodexWeeklyBoundaryCorrection.isRetiredBoundary(
            boundary, evidence: evidence, observedAt: observedAt)
        {
            evidence.correctionCandidate = nil
            evidence.holdReason = .retiredBoundary
            Self.logCodexBoundaryAdmission(reason: "retiredBoundary", current: current)
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: nil,
                withheldSuccess: result,
                weeklyBoundaryEvidence: evidence)
        }
        let previousBoundary = (comparableBaseline ? previousSnapshot : nil).flatMap {
            CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: $0)?.resetsAt
        }
        let regressed = if comparableBaseline, let boundary, let previousBoundary {
            boundary.timeIntervalSince(previousBoundary) < -CodexWeeklyBoundaryCorrection.boundaryEquivalenceTolerance
        } else {
            false
        }
        if regressed || evidence.correctionCandidate != nil {
            let evaluation = CodexWeeklyBoundaryCorrection.evaluate(
                previous: previousSnapshot,
                current: current,
                sourceEvidence: CodexWeeklyBoundaryCorrection.SourceEvidence(
                    previousIsExactOAuth: previousSourceLabel?.lowercased() == "oauth",
                    currentIsExactOAuth: result.strategyKind == .oauth
                        && result.sourceLabel.lowercased() == "oauth"),
                evidence: evidence,
                observedAt: observedAt)
            evidence = evaluation.evidence
            Self.logCodexBoundaryAdmission(reason: String(describing: evaluation.reason), current: current)
            if evaluation.decision == .publishCorrection {
                evidence = CodexWeeklyBoundaryCorrection.retiring(
                    previousBoundary: previousBoundary,
                    acceptedBoundary: boundary,
                    evidence: evidence,
                    observedAt: observedAt)
                evidence.pendingDetectorCorrection = current
                return CodexWeeklyResetPublicationAdmission(
                    outcome: missingWindowBackfillSnapshot.map {
                        initialOutcome.replacingUsage(Self.codexBackfillingResetWindows(current, from: $0))
                    } ?? initialOutcome,
                    pendingCandidate: nil,
                    weeklyBoundaryEvidence: evidence,
                    correctsWeeklyBoundary: true)
            }
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: nil,
                withheldSuccess: result,
                weeklyBoundaryEvidence: evidence)
        }
        let admission = await Self.codexOutcomeAdmittedByResetPolicy(
            initialOutcome: initialOutcome,
            previousSnapshot: previousSnapshot,
            previousSourceLabel: previousSourceLabel,
            missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
            pendingCandidate: pendingCandidate,
            observedAt: observedAt,
            fetchConfirmation: fetchConfirmation)
        if let outcome = admission.outcome, case let .success(accepted) = outcome.result {
            let acceptedBoundary = CodexConsumerProjection.sourceRateWindow(
                for: .weekly, snapshot: accepted.usage.scoped(to: .codex))?.resetsAt
            // Confirmation may differ from the first response. Apply retired-cycle protection again.
            if let acceptedBoundary, CodexWeeklyBoundaryCorrection.isRetiredBoundary(
                acceptedBoundary, evidence: evidence, observedAt: observedAt)
            {
                evidence.correctionCandidate = nil
                evidence.holdReason = .retiredBoundary
                return CodexWeeklyResetPublicationAdmission(
                    outcome: nil,
                    pendingCandidate: nil,
                    withheldSuccess: accepted,
                    weeklyBoundaryEvidence: evidence)
            }
            evidence = CodexWeeklyBoundaryCorrection.retiring(
                previousBoundary: previousBoundary,
                acceptedBoundary: acceptedBoundary,
                evidence: evidence,
                observedAt: observedAt)
        }
        return Self.codexAdmission(admission, evidence: evidence)
    }

    private nonisolated static func codexAdmission(
        _ admission: CodexWeeklyResetPublicationAdmission,
        evidence: CodexWeeklyBoundaryEvidence) -> CodexWeeklyResetPublicationAdmission
    {
        CodexWeeklyResetPublicationAdmission(
            outcome: admission.outcome,
            pendingCandidate: admission.pendingCandidate,
            suppressesWeeklyResetCelebration: admission.suppressesWeeklyResetCelebration,
            withheldSuccess: admission.withheldSuccess,
            weeklyBoundaryEvidence: evidence)
    }

    private nonisolated static func logCodexBoundaryAdmission(reason: String, current: UsageSnapshot) {
        CodexBarLog.logger(LogCategories.provider(.codex, scope: "weekly-boundary-publication")).debug(
            "Codex weekly boundary publication decision",
            metadata: [
                "reason": reason,
                "observedAt": String(format: "%.0f", current.updatedAt.timeIntervalSince1970),
            ])
    }
}
