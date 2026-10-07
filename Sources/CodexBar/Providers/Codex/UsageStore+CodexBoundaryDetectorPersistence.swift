import CodexBarCore
import Foundation

extension UsageStore {
    /// Complete an accepted correction's detector update before admitting another observation.
    /// The marker is committed with the accepted snapshot so ordinary restart can replay the update.
    /// Detector preferences retain the existing UserDefaults best-effort durability contract.
    func consumePendingCodexBoundaryDetectorCorrections() {
        let projection = self.settings.codexVisibleAccountProjection
        var records = self.codexAccountSnapshots
        var changed = false
        for index in records.indices {
            let row = records[index]
            guard var evidence = row.weeklyBoundaryEvidence,
                  let correction = evidence.pendingDetectorCorrection,
                  let current = row.snapshot,
                  CodexWeeklyResetConfirmation.accountsAreCompatible(correction, current),
                  CodexWeeklyResetConfirmation.plansAreCompatible(correction, current),
                  let account = Self.currentCodexVisibleAccount(matching: row.account, projection: projection),
                  let ownerKey = self.codexLimitResetOwnerKey(
                      forVisibleAccount: account, visibleAccounts: projection.visibleAccounts)
            else { continue }
            self.normalizeCodexWeeklyBoundaryCorrection(snapshot: correction, ownerKey: ownerKey)
            evidence.pendingDetectorCorrection = nil
            records[index] = CodexAccountUsageSnapshot(
                account: row.account,
                snapshot: row.snapshot,
                error: row.error,
                sourceLabel: row.sourceLabel,
                credits: row.credits,
                weeklyResetCandidate: row.weeklyResetCandidate,
                weeklyBoundaryEvidence: evidence)
            changed = true
        }
        guard changed else { return }
        self.codexAccountSnapshots = records
        self.codexAccountUsageSnapshotStore?.store(records)
    }
}
