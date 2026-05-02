import CodexBarSync
import Foundation

/// Captures per-account snapshots for providers that support multi-account
/// (Codex today; token-based providers in R2) so SyncCoordinator can emit
/// one CKRecord per known account on every push.
///
/// **Why this class exists.** Mac's `UsageStore.snapshots[.codex]` only ever
/// holds the **active** account's snapshot. When the user switches from
/// account-A to account-B, `prepareCodexAccountScopedRefreshIfNeeded()` wipes
/// A's data and refreshes B. By itself, that means SyncCoordinator can only
/// see one account at a time, which is why "I added 3 Codex accounts on Mac
/// but iOS shows 1" was the reported bug.
///
/// **What we do.** SyncCoordinator observes both `store.snapshots` and the
/// active managed account ID. Whenever the snapshot for a multi-account
/// provider is fresh, we capture it into this cache keyed by `(provider,
/// accountID)`. On the next push, we emit the active account's snapshot **and**
/// every cached non-active snapshot. As the user uses each account at least
/// once, the cache fills up and all N accounts are visible on iOS.
///
/// **Cold start.** A fresh Mac process starts with an empty cache. Until the
/// user has activated each Codex account at least once during the session,
/// inactive accounts remain hidden on iOS (matching the pre-fix behavior for
/// those specific accounts only — never worse). Future iterations may add
/// "fan-out fetch on first push" to eagerly populate; for now we accept this
/// trade-off in exchange for zero added RPC latency on every push.
///
/// **Cache lifecycle.** The cache is in-memory only. It rebuilds when:
/// - The Mac process restarts (snapshots come back via natural refresh cycle)
/// - The user removes a managed account on Mac (SyncCoordinator purges via
///   `purgeStaleAccounts` when its set of stored accounts shrinks)
/// - The user disables a multi-account provider entirely (SyncCoordinator
///   purges with `livingAccountIDs: []`)
///
/// `reset()` is exposed for tests and future use (e.g., explicit "wipe
/// sync state" admin command). It is currently NOT called from
/// SyncCoordinator's regular push flow.
///
/// The cache key is intentionally a generic `String` so R2 can reuse this
/// class for token-based providers without redesign.
@MainActor
final class SyncMultiAccountSnapshotCache {
    /// Composite key `"<providerID>|<accountID>"` → most recent snapshot
    /// captured for that account.
    private var snapshotByCompositeKey: [String: ProviderUsageSnapshot] = [:]

    /// Records `snapshot` against `(providerID, accountID)`. Replaces any
    /// previous entry for that pair.
    func record(
        _ snapshot: ProviderUsageSnapshot,
        providerID: String,
        accountID: String)
    {
        let key = Self.compositeKey(providerID: providerID, accountID: accountID)
        self.snapshotByCompositeKey[key] = snapshot
    }

    /// Returns all cached snapshots for `providerID` whose accountID is NOT
    /// equal to `excludingAccountID`. Use this to merge cached non-active
    /// snapshots alongside the freshly-built active snapshot during a push.
    func cachedSnapshots(
        providerID: String,
        excludingAccountID: String) -> [ProviderUsageSnapshot]
    {
        let prefix = "\(providerID)|"
        let exclude = Self.compositeKey(
            providerID: providerID, accountID: excludingAccountID)
        return self.snapshotByCompositeKey.compactMap { key, snapshot in
            guard key.hasPrefix(prefix), key != exclude else { return nil }
            return snapshot
        }
    }

    /// Drops cache entries for `providerID` whose accountID is not in
    /// `livingAccountIDs`. Called by SyncCoordinator when the set of stored
    /// managed accounts changes (account removed on Mac).
    func purgeStaleAccounts(
        providerID: String,
        livingAccountIDs: Set<String>)
    {
        let prefix = "\(providerID)|"
        let livingComposites = Set(livingAccountIDs.map {
            Self.compositeKey(providerID: providerID, accountID: $0)
        })
        let staleKeys = self.snapshotByCompositeKey.keys.filter {
            $0.hasPrefix(prefix) && !livingComposites.contains($0)
        }
        for key in staleKeys {
            self.snapshotByCompositeKey.removeValue(forKey: key)
        }
    }

    /// Number of cached entries for `providerID`. Test/diagnostic accessor.
    func count(forProvider providerID: String) -> Int {
        let prefix = "\(providerID)|"
        return self.snapshotByCompositeKey.keys.count(where: { $0.hasPrefix(prefix) })
    }

    /// Wipes the entire cache. Exposed for tests and future use; no
    /// production call site as of R3. (R3 P3, Research/020 H9.)
    func reset() {
        self.snapshotByCompositeKey.removeAll()
    }

    private static func compositeKey(providerID: String, accountID: String) -> String {
        "\(providerID)|\(accountID)"
    }
}
