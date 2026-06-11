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

    @Test("No completed refresh yet → always refresh")
    func nilLastRefresh_refreshes() {
        #expect(SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: nil, now: self.now))
    }

    @Test("Fresh data (just refreshed) → skip")
    func freshData_skips() {
        #expect(!SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: self.now.addingTimeInterval(-1), now: self.now))
    }

    @Test("Quick app switch inside the threshold → skip")
    func quickAppSwitch_skips() {
        #expect(!SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: self.now.addingTimeInterval(-59), now: self.now))
    }

    @Test("Exactly at the threshold → refresh")
    func atThreshold_refreshes() {
        #expect(SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: self.now.addingTimeInterval(
                -SyncedUsageData.foregroundStaleThreshold),
            now: self.now))
    }

    @Test("Backgrounded for minutes → refresh")
    func staleData_refreshes() {
        #expect(SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: self.now.addingTimeInterval(-600), now: self.now))
    }

    @Test("Clock skew (last refresh in the future) → skip, no thrash")
    func futureTimestamp_skips() {
        // A device clock jumping backwards must not cause a refresh storm;
        // negative elapsed time is simply "not stale yet".
        #expect(!SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: self.now.addingTimeInterval(120), now: self.now))
    }

    @Test("Custom threshold is honored")
    func customThreshold() {
        let last = self.now.addingTimeInterval(-30)
        #expect(SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: last, now: self.now, threshold: 15))
        #expect(!SyncedUsageData.shouldAutoRefresh(
            lastRefreshCompletedAt: last, now: self.now, threshold: 45))
    }
}
