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
}
