import Foundation
import Testing
@testable import CodexBarMobile

/// Pins the staleness gate behind `SyncedUsageData.refreshIfStale()` — the
/// foreground auto-refresh added so reopening the app shows current Mac data
/// without a manual pull-to-refresh. The decision is a pure static function
/// so it can be tested without touching CloudKit.
@Suite("Foreground Refresh Gate")
struct ForegroundRefreshGateTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test
    func `No completed refresh yet → always refresh`() {
        #expect(SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: nil, now: self.now))
    }

    @Test
    func `Fresh data (just refreshed) → skip`() {
        #expect(!SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: self.now.addingTimeInterval(-1), now: self.now))
    }

    @Test
    func `Quick app switch inside the threshold → skip`() {
        #expect(!SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: self.now.addingTimeInterval(-59), now: self.now))
    }

    @Test
    func `Exactly at the threshold → refresh`() {
        #expect(SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: self.now.addingTimeInterval(
                -SyncedUsageData.foregroundStaleThreshold),
            now: self.now))
    }

    @Test
    func `Backgrounded for minutes → refresh`() {
        #expect(SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: self.now.addingTimeInterval(-600), now: self.now))
    }

    @Test
    func `Clock skew (last refresh in the future) → skip, no thrash`() {
        // A device clock jumping backwards must not cause a refresh storm;
        // negative elapsed time is simply "not stale yet".
        #expect(!SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: self.now.addingTimeInterval(120), now: self.now))
    }

    @Test
    func `Custom threshold is honored`() {
        let last = self.now.addingTimeInterval(-30)
        #expect(SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: last, now: self.now, threshold: 15))
        #expect(!SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: last, now: self.now, threshold: 45))
    }
}
