import CodexBarSync
import Foundation

/// Single source of truth for "is this synthetic mock data?" detection on
/// iOS. Mac 0.23.5+ injects synthetic provider snapshots when the user
/// opts in (Settings → Mobile → Debug · Mock Provider Data, or env var,
/// or `defaults write`). Those snapshots are normal `ProviderUsageSnapshot`
/// values from iOS's perspective — the only signal that distinguishes
/// them from real data is the universal `*-mock@*.test` email TLD
/// convention, augmented by the `_mock_*` synthetic providerID prefix
/// for the 2 fallback-test mocks.
///
/// **Detection contract** (mirror of Mac-side `MockProviderInjector`):
/// - REAL providerID + email matches `*-mock@*.test` → mock (first-class
///   path: e.g. `codex` + `alice-mock@codex.test`)
/// - synthetic `_mock_*` providerID prefix → mock (fallback path: e.g.
///   `_mock_cursor_unknown` + `expired-mock@cursor.test`)
/// - everything else → real data
///
/// Either signal is sufficient; we OR them together so a future Mac that
/// drops one signal but keeps the other still works. Real users without
/// mock activation will never have either signal in their data.
///
/// **Used by** (iOS 1.5.2+):
/// - `ProviderUsageView` — adds MOCK pill badge + purple accent
/// - `ProviderDetailView` — adds MOCK badge in detail header
/// - `MockProviderBanner` — top banner when any mock detected
/// - Settings → Diagnostics — count of active mocks + Mac version
enum MockProviderDetector {
    /// RFC 6761 reserved TLD that Mac 0.23.5+ uses for every mock
    /// account email. Matches `MockProviderInjector.mockEmailTLD`.
    static let mockEmailTLD = ".test"

    /// Synthetic providerID prefix that Mac 0.23.5+ uses for the 2
    /// fallback-test mocks. Matches `MockProviderInjector.syntheticProviderIDs`.
    static let mockProviderIDPrefix = "_mock_"

    /// True when this snapshot is synthetic mock data injected by Mac's
    /// `MockProviderInjector`. Either the email TLD OR the providerID
    /// prefix is sufficient; both are typically present.
    static func isMock(_ snapshot: ProviderUsageSnapshot) -> Bool {
        if snapshot.providerID.hasPrefix(Self.mockProviderIDPrefix) {
            return true
        }
        if let email = snapshot.accountEmail, email.hasSuffix(Self.mockEmailTLD) {
            return true
        }
        return false
    }

    /// Filters a snapshot to just its mock providers.
    static func mockSnapshots(in snapshot: SyncedUsageSnapshot?) -> [ProviderUsageSnapshot] {
        guard let snapshot else { return [] }
        return snapshot.providers.filter { Self.isMock($0) }
    }

    /// True when at least one provider in this snapshot is a mock.
    /// Drives the top banner + Settings Diagnostics row visibility.
    static func hasAnyMock(in snapshot: SyncedUsageSnapshot?) -> Bool {
        !Self.mockSnapshots(in: snapshot).isEmpty
    }

    /// Counts mock providers in the current snapshot. Used by the
    /// Settings Diagnostics row ("Mock data: 8 active").
    static func mockCount(in snapshot: SyncedUsageSnapshot?) -> Int {
        Self.mockSnapshots(in: snapshot).count
    }

    /// Extinct mock providerIDs from earlier mock-injector designs that
    /// are no longer emitted by current Mac code but may linger in
    /// CloudKit as zombie CKRecords (the L1 ghost-records cleanup
    /// doesn't catch them across Mac process restarts because
    /// `lastPushedRecordNames` resets to empty on launch).
    ///
    /// These IDs MUST be filtered out by iOS to prevent duplicate cards
    /// on Cost / Usage pages while the Mac-side cleanup catches up
    /// (which may take longer if the user toggles mock off but the
    /// extinct IDs were never in the current cycle's lastPushedRecordNames
    /// to begin with).
    ///
    /// Maintained as code, NOT data — adding/removing extinct IDs
    /// requires an iOS release. List grows over time as mock-injector
    /// design evolves; entries can be removed once Mac-side cleanup
    /// confirms zero records remain in CloudKit for a given ID.
    static let extinctMockProviderIDs: Set<String> = [
        // Mac 0.23.5 P0 (initial mock-injector) — replaced by mix-mode
        // design in P2. These IDs no longer emitted; CloudKit zombies
        // still surface here without this filter.
        "_mock_codex_multi",
        "_mock_claude_multi",
        "_mock_perplexity_credit",
        "_mock_cursor_error",
        "_mock_synthetic_3lane",
    ]

    /// Returns the providers list with extinct-mock zombies filtered
    /// out. Use at every iOS reader site that pulls a `SyncedUsageSnapshot`
    /// before display (Usage list, Cost dashboard aggregator, Provider
    /// Share, Daily Spend). Real (non-mock) provider entries pass
    /// through unmodified.
    static func filteredProviders(
        from snapshot: SyncedUsageSnapshot) -> [ProviderUsageSnapshot]
    {
        snapshot.providers.filter { provider in
            !Self.extinctMockProviderIDs.contains(provider.providerID)
        }
    }
}
