import CodexBarSync
import Foundation

/// Shared realistic-distribution fixtures for iOS tests.
///
/// Pre-Build-78 every merge test used toy data: `usedPercent: 50.0`,
/// `costUSD: $1.50`, three rate-limit entries. Round 3 of the 5-round
/// audit found every test file had **zero coverage** of realistic
/// production patterns: long idle · cross-reset boundary · cross-date ·
/// disordered timestamps · all-zero-but-tracked · bursty.
///
/// Build 80 added 6 fixtures inline in `CloudKitMergeTests`. Agent C
/// (Build 83 follow-up audit) identified 3 more test files that needed
/// the same treatment: `SwiftDataBridgeTests` / `DualZoneReaderTests` /
/// `SnapshotCacheTests`. To avoid re-duplicating the fixture code across
/// those files, they now share this file.
///
/// All fixtures use a **UTC calendar** to sidestep the DST trap that
/// made an earlier version of `burstySessionSeries` flaky on Europe/Paris
/// spring-forward (720 buckets would drop to 719 for one local day).
enum TestFixtures {
    /// UTC gregorian calendar — DST-proof fixture time base.
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: - Utilization series distributions

    /// 30 days × 24 hourly samples, a single `peakPercent` burst at
    /// `peakHour` each day, zeros elsewhere. Mimics a real Codex-style
    /// provider that the user hits in short bursts of activity and
    /// otherwise sits idle — the distribution that surfaced Build 77's
    /// Codex-0% aggregate bug.
    static func burstySessionSeries(
        anchor: Date,
        daysCount: Int = 30,
        peakHour: Int = 14,
        peakPercent: Double = 16,
        deviceOffsetMinutes: Int = 0) -> SyncUtilizationSeries
    {
        var entries: [SyncUtilizationEntry] = []
        let anchorStartOfDay = Self.utcCalendar.startOfDay(for: anchor)
        for dayOffset in 0..<daysCount {
            let day = Self.utcCalendar.date(byAdding: .day, value: -dayOffset, to: anchorStartOfDay)!
            for hour in 0..<24 {
                let captured = Self.utcCalendar.date(
                    byAdding: .minute, value: deviceOffsetMinutes,
                    to: Self.utcCalendar.date(byAdding: .hour, value: hour, to: day)!)!
                let used = (hour == peakHour) ? peakPercent : 0.0
                entries.append(SyncUtilizationEntry(
                    capturedAt: captured, usedPercent: used, resetsAt: nil))
            }
        }
        return SyncUtilizationSeries(
            name: "session", windowMinutes: 300, entries: entries)
    }

    /// All-zero pattern: idle device that keeps CodexBar running but never
    /// uses the tracked provider. 720 hourly samples all at 0%. Must
    /// survive every merge / persist / rehydrate pass — dropping zero-only
    /// providers would hide them from Subscription Utilization.
    static func allZeroSessionSeries(
        anchor: Date,
        daysCount: Int = 30) -> SyncUtilizationSeries
    {
        let anchorStartOfDay = Self.utcCalendar.startOfDay(for: anchor)
        let entries = (0..<daysCount * 24).map { i in
            SyncUtilizationEntry(
                capturedAt: anchorStartOfDay.addingTimeInterval(TimeInterval(i) * 3600),
                usedPercent: 0,
                resetsAt: nil)
        }
        return SyncUtilizationSeries(
            name: "session", windowMinutes: 300, entries: entries)
    }

    /// Two entries in the SAME clock hour straddling a session reset:
    /// - pre-reset (usedPercent=90%, resetsAt=T) — Mac just capped a session
    /// - post-reset (usedPercent=5%, resetsAt=T+5h) — new session started 10 min later
    ///
    /// `BucketKey(hourSlot, resetEpoch)` must keep these separate; a
    /// regression that drops `resetEpoch` would collapse them to a
    /// meaningless 47.5% average.
    static func crossResetBoundaryEntries(anchor: Date) -> [SyncUtilizationEntry] {
        let resetT = anchor.addingTimeInterval(2000)
        let resetTPlus5 = resetT.addingTimeInterval(5 * 3600)
        return [
            SyncUtilizationEntry(capturedAt: anchor, usedPercent: 90, resetsAt: resetT),
            SyncUtilizationEntry(
                capturedAt: anchor.addingTimeInterval(600),
                usedPercent: 5, resetsAt: resetTPlus5),
        ]
    }

    // MARK: - Provider snapshots

    /// Minimal `ProviderUsageSnapshot` with a session series of the given
    /// pattern. Most callers only care about the utilizationHistory shape —
    /// other fields nil'd out.
    static func provider(
        id: String = "codex",
        name: String? = nil,
        email: String? = "user@example.com",
        lastUpdated: Date,
        utilizationHistory: [SyncUtilizationSeries]? = nil) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name ?? id.capitalized,
            primary: nil, secondary: nil,
            accountEmail: email,
            loginMethod: nil, statusMessage: nil,
            isError: false, lastUpdated: lastUpdated,
            utilizationHistory: utilizationHistory)
    }

    /// Multi-account provider pair: two instances of the same `providerID`
    /// with distinct `accountEmail`s. Used for tests that verify the
    /// `providerID|accountEmail` composite key keeps accounts separate
    /// through merge / SwiftData roundtrip / cache priority logic.
    static func multiAccountProviders(
        id: String = "codex",
        emails: [String],
        lastUpdated: Date) -> [ProviderUsageSnapshot]
    {
        emails.map { email in
            self.provider(id: id, email: email, lastUpdated: lastUpdated)
        }
    }
}
