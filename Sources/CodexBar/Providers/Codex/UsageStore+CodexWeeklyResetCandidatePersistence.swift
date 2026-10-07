import CodexBarCore
import Foundation

extension UsageStore {
    @discardableResult
    func persistCodexWeeklyResetPublicationCandidate(
        _ candidate: CodexWeeklyResetPublicationCandidate?,
        expectedGuard: CodexAccountScopedRefreshGuard?,
        previousSnapshot: UsageSnapshot?,
        weeklyBoundaryEvidence: CodexWeeklyBoundaryEvidence? = nil) -> CodexWeeklyResetPersistenceDecision
    {
        guard let expectedGuard else { return self.recordCodexWeeklyResetPersistenceDecision(.missingExpectedGuard) }
        let currentGuard = self.freshCodexAccountScopedRefreshGuard()
        guard Self.codexScopedRefreshGuardsMatchAccount(expectedGuard, currentGuard) else {
            return self.recordCodexWeeklyResetPersistenceDecision(.accountChanged)
        }

        let visibleAccounts = self.freshCodexVisibleAccountsForSnapshotHydration()
        let activeMatches = visibleAccounts.filter {
            $0.isActive && Self.codexScopedRefreshGuardsMatchAccount(
                currentGuard,
                Self.codexScopedRefreshGuard(for: $0))
        }
        guard activeMatches.count == 1, let account = activeMatches.first else {
            return self.recordCodexWeeklyResetPersistenceDecision(.ambiguousActiveAccount)
        }

        // Single-account refresh clears memory before admission; keep persisted rows and credits intact.
        var records = self.codexAccountSnapshots
        let persisted = self.codexAccountUsageSnapshotStore?.load(for: visibleAccounts) ?? []
        records += persisted.filter { row in !records.contains { $0.id == row.id } }
        if let index = records.firstIndex(where: { $0.id == account.id }) {
            let existing = records[index]
            guard Self.codexScopedRefreshGuardsMatchAccount(
                currentGuard,
                Self.codexScopedRefreshGuard(for: existing.account))
            else { return self.recordCodexWeeklyResetPersistenceDecision(.existingAccountChanged) }
            guard existing.weeklyResetCandidate != nil || candidate != nil
                || existing.weeklyBoundaryEvidence != nil || weeklyBoundaryEvidence != nil
            else {
                return self.recordCodexWeeklyResetPersistenceDecision(.noCandidateChange)
            }
            records[index] = CodexAccountUsageSnapshot(
                account: existing.account,
                snapshot: existing.snapshot,
                error: existing.error,
                sourceLabel: existing.sourceLabel,
                credits: existing.credits,
                weeklyResetCandidate: candidate,
                weeklyBoundaryEvidence: weeklyBoundaryEvidence ?? existing.weeklyBoundaryEvidence)
        } else {
            guard candidate != nil || weeklyBoundaryEvidence != nil, let previousSnapshot else {
                return self.recordCodexWeeklyResetPersistenceDecision(.missingCandidateOrBaseline)
            }
            let identity = previousSnapshot.identity(for: .codex)
            let relabeled = previousSnapshot.withIdentity(ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: account.email,
                accountOrganization: identity?.accountOrganization,
                loginMethod: identity?.loginMethod ?? account.workspaceLabel))
            records.append(CodexAccountUsageSnapshot(
                account: account,
                snapshot: relabeled,
                error: self.errors[.codex],
                sourceLabel: self.lastSourceLabels[.codex],
                credits: self.credits,
                weeklyResetCandidate: candidate,
                weeklyBoundaryEvidence: weeklyBoundaryEvidence))
        }
        self.codexAccountSnapshots = records
        guard let store = self.codexAccountUsageSnapshotStore else {
            return self.recordCodexWeeklyResetPersistenceDecision(.storeUnavailable)
        }
        store.store(records)
        return self.recordCodexWeeklyResetPersistenceDecision(.storeRequested)
    }

    private func recordCodexWeeklyResetPersistenceDecision(
        _ decision: CodexWeeklyResetPersistenceDecision) -> CodexWeeklyResetPersistenceDecision
    {
        CodexBarLog.logger(LogCategories.provider(.codex, scope: "weekly-reset-publication")).debug(
            "Codex weekly reset candidate persistence decision",
            metadata: decision.diagnosticMetadata)
        return decision
    }
}
