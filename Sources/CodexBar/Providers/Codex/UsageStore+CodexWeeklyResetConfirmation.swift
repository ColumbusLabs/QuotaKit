import CodexBarCore

extension UsageStore {
    typealias CodexWeeklyConfirmationFetch = @Sendable () async -> ProviderFetchOutcome

    struct CodexWeeklyPublicationAdmission: Sendable {
        let outcome: ProviderFetchOutcome
        /// Keeps a confirmed early rolling window from emitting a premature weekly-reset event.
        let suppressesWeeklyResetCelebration: Bool
    }

    nonisolated static func codexOutcomeAdmittedForPublication(
        initialOutcome: ProviderFetchOutcome,
        previousSnapshot: UsageSnapshot?,
        missingWindowBackfillSnapshot: UsageSnapshot?,
        fetchConfirmation: @escaping CodexWeeklyConfirmationFetch) async -> CodexWeeklyPublicationAdmission?
    {
        guard case let .success(rawInitialResult) = initialOutcome.result else {
            return CodexWeeklyPublicationAdmission(
                outcome: initialOutcome,
                suppressesWeeklyResetCelebration: false)
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
            guard rawInitialSnapshot.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                  previousSnapshot.map({
                      $0.updatedAt.timeIntervalSinceReferenceDate.isFinite &&
                          rawInitialSnapshot.updatedAt > $0.updatedAt
                  }) ?? true,
                  missingWindowBackfillSnapshot.map({
                      $0.updatedAt.timeIntervalSinceReferenceDate.isFinite &&
                          rawInitialSnapshot.updatedAt >= $0.updatedAt
                  }) ?? true
            else {
                return nil
            }
            if CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: publicationBaseline) != nil,
               case let .success(publicationResult) = publicationInitialOutcome.result,
               CodexConsumerProjection.sourceRateWindow(
                   for: .weekly,
                   snapshot: publicationResult.usage.scoped(to: .codex)) == nil
            {
                return nil
            }
            return CodexWeeklyPublicationAdmission(
                outcome: publicationInitialOutcome,
                suppressesWeeklyResetCelebration: false)
        }

        switch CodexWeeklyResetConfirmation.initialDecision(
            previous: publicationBaseline,
            initial: rawInitialSnapshot)
        {
        case .publishInitial:
            return CodexWeeklyPublicationAdmission(
                outcome: publicationInitialOutcome,
                suppressesWeeklyResetCelebration: false)
        case .preservePrevious:
            return nil
        case .requiresConfirmation:
            break
        }

        guard !Task.isCancelled else { return nil }
        let confirmationOutcome = await fetchConfirmation()
        guard !Task.isCancelled,
              case let .success(confirmationResult) = confirmationOutcome.result
        else {
            return nil
        }
        let confirmationSnapshot = confirmationResult.usage.scoped(to: .codex)
        guard CodexIdentityResolver.normalizeEmail(rawInitialSnapshot.accountEmail(for: .codex)) ==
            CodexIdentityResolver.normalizeEmail(confirmationSnapshot.accountEmail(for: .codex))
        else {
            return nil
        }
        switch CodexWeeklyResetConfirmation.confirmationDecision(
            previous: publicationBaseline,
            initial: rawInitialSnapshot,
            confirmation: confirmationSnapshot)
        {
        case .publishConfirmation:
            let outcome = if let missingWindowBackfillSnapshot {
                confirmationOutcome.replacingUsage(Self.codexBackfillingResetWindows(
                    confirmationSnapshot,
                    from: missingWindowBackfillSnapshot))
            } else {
                confirmationOutcome
            }
            return CodexWeeklyPublicationAdmission(
                outcome: outcome,
                suppressesWeeklyResetCelebration: false)
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
            return CodexWeeklyPublicationAdmission(
                outcome: outcome,
                suppressesWeeklyResetCelebration: true)
        case .publishManualResetConfirmation:
            let outcome = if let missingWindowBackfillSnapshot {
                confirmationOutcome.replacingUsage(Self.codexBackfillingResetWindows(
                    confirmationSnapshot,
                    from: missingWindowBackfillSnapshot))
            } else {
                confirmationOutcome
            }
            return CodexWeeklyPublicationAdmission(
                outcome: outcome,
                suppressesWeeklyResetCelebration: false)
        case .preservePrevious:
            return nil
        }
    }
}
