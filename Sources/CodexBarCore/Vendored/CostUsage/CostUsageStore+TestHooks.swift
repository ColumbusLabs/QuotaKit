import Foundation

#if DEBUG
/// Immutable instrumentation for one test, including work handed to the scan queue.
struct CostUsageStoreTestHooks: Sendable {
    @TaskLocal static var current = CostUsageStoreTestHooks()

    /// Invoked after each persisted file, inside the save transaction, for crash-safety proof.
    var saveCycleCheckpoint: (@Sendable (Int) -> Void)?
    var identicalContentPreLockCheckpoint: (databaseURL: URL, checkpoint: @Sendable () -> Void)?
    var identicalContentPostCommitCheckpoint: (databaseURL: URL, checkpoint: @Sendable () -> Void)?
    var codexCatchUpReconciliationVisit: (@Sendable () -> Void)?
    var codexPrefixComparisonVisit: (@Sendable (String, Int) -> Void)?
    var codexCatchUpDeltaFailure: (@Sendable (URL) throws -> Void)?
    var budgetMutationFailure: (@Sendable (URL) throws -> Void)?
    var verifiedLedgerMigrationFailure: (@Sendable (URL) throws -> Void)?
    var verifiedLedgerMigrationAttempt: (@Sendable (URL) -> Void)?

    var snapshotRead: (@Sendable (URL) -> Void)?
    var codexReadViewIntegrityCheck: (@Sendable (URL) -> Void)?
    var codexReadViewSnapshot: (@Sendable (URL, CostUsageStoreReadPurpose) -> Void)?
    var codexReadViewDecode: (@Sendable (URL, CostUsageStoreReadPurpose) -> Void)?
    var codexReadViewUsageRows: (@Sendable (URL) -> Void)?
    var codexReadViewCheckpoint: (@Sendable (URL) throws -> Void)?
    var codexStreamedUsageRow: (@Sendable (String, Int, Int, Bool) -> Void)?
    var tokenSnapshotsRead: (@Sendable (URL) -> Void)?
    var tokenSnapshotPathRead: (@Sendable (URL, String?) -> Void)?
    var codexTokenSnapshotHydrationFailure: (@Sendable (URL, Set<String>) -> Bool)?
    var codexBaselineReadCheckpoint: (databaseURL: URL, checkpoint: @Sendable () throws -> Void)?
    var codexTokenHydrationCheckpoint: (databaseURL: URL, checkpoint: @Sendable () throws -> Void)?
    var codexCacheReadCheckpoint: (databaseURL: URL, checkpoint: @Sendable () throws -> Void)?
}
#endif
