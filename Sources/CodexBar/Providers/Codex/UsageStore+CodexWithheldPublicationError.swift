import CodexBarCore
import Foundation

extension UsageStore {
    func codexRefreshStillCurrent(_ generation: UInt64?) -> Bool {
        !Task.isCancelled && self.isCurrentProviderRefreshGeneration(.codex, generation: generation)
    }

    func handleCodexWithheldAdmission(
        _ admission: CodexWeeklyResetPublicationAdmission,
        expectedGuard: CodexAccountScopedRefreshGuard?,
        generation: UInt64)
    {
        if let expectedGuard {
            self.retireCodexStateIfRefreshOwnerChanged(
                expectedGuard: expectedGuard,
                generation: generation)
        }
        if let success = admission.withheldSuccess, let expectedGuard {
            self.clearCodexFetchErrorAfterWithheldPublication(
                success: success,
                expectedGuard: expectedGuard,
                generation: generation)
        }
    }

    /// Record successful Codex connectivity when a quota reading is withheld by reset admission.
    ///
    /// A withheld publication still represents a successful, account-scoped fetch. The caller must
    /// provide the fetch result and generation so a late result cannot clear a newer account's error
    /// or failure gate. Only the connectivity error associated with the matching account is cleared;
    /// authentication, workspace, and parsing errors remain visible.
    func clearCodexFetchErrorAfterWithheldPublication(
        success: ProviderFetchResult,
        expectedGuard: CodexAccountScopedRefreshGuard,
        generation: UInt64)
    {
        guard !Task.isCancelled,
              !Self.isCodexPATResult(success),
              self.isCurrentProviderRefreshGeneration(.codex, generation: generation),
              self.shouldApplyCodexUsageResult(
                  expectedGuard: expectedGuard,
                  usage: success.usage.scoped(to: .codex))
        else { return }

        let visibleAccounts = self.freshCodexVisibleAccountsForSnapshotHydration()
        let matches = visibleAccounts.filter {
            $0.isActive && Self.codexScopedRefreshGuardsMatchAccount(
                expectedGuard,
                Self.codexScopedRefreshGuard(for: $0))
        }
        guard matches.count == 1, let account = matches.first else { return }

        self.recordCodexWithheldFetchSuccess()
        if let index = self.codexAccountSnapshots.firstIndex(where: {
            $0.id == account.id && Self.codexScopedRefreshGuardsMatchAccount(
                expectedGuard,
                Self.codexScopedRefreshGuard(for: $0.account))
        }) {
            self.codexAccountSnapshots[index] = Self.clearingCodexConnectivityError(
                self.codexAccountSnapshots[index])
        }

        // A single-account refresh can clear the in-memory rows before admission. Amend the
        // persisted records directly so preserved usage, credits, candidates, and siblings survive.
        guard let snapshotStore = self.codexAccountUsageSnapshotStore else { return }
        var persisted = snapshotStore.load(for: visibleAccounts)
        guard let index = persisted.firstIndex(where: {
            $0.id == account.id && Self.codexScopedRefreshGuardsMatchAccount(
                expectedGuard,
                Self.codexScopedRefreshGuard(for: $0.account))
        }), let error = persisted[index].error,
        Self.shouldPreserveCodexAccountSnapshotOnFailure(error)
        else { return }
        persisted[index] = Self.clearingCodexConnectivityError(persisted[index])
        snapshotStore.store(persisted)
    }

    /// Failure suppression tracks successful fetches, even when quota publication is withheld.
    func recordCodexWithheldFetchSuccess() {
        self.failureGates[.codex]?.recordSuccess()
        if let error = self.errors[.codex], Self.shouldPreserveCodexAccountSnapshotOnFailure(error) {
            self.errors[.codex] = nil
        }
    }

    static func clearingCodexConnectivityError(
        _ record: CodexAccountUsageSnapshot) -> CodexAccountUsageSnapshot
    {
        guard let error = record.error,
              shouldPreserveCodexAccountSnapshotOnFailure(error)
        else { return record }
        return CodexAccountUsageSnapshot(
            account: record.account,
            snapshot: record.snapshot,
            error: nil,
            sourceLabel: record.sourceLabel,
            credits: record.credits,
            weeklyResetCandidate: record.weeklyResetCandidate)
    }
}
