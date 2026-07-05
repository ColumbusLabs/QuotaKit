import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Tests for identity-key correctness across the five hotspot views refactored in P1.
/// Cache invalidation relies on stable identity keys — same inputs must hash identically,
/// changed inputs must produce different keys, and unrelated state changes must not
/// affect the key.
@Suite("View Cache Identity Keys")
struct ViewCacheIdentityTests {
    // MARK: - Fixtures

    private static func makeProvider(
        id: String = "claude",
        name: String = "Claude",
        lastUpdated: Date = Date(timeIntervalSince1970: 1_700_000_000),
        utilization: [SyncUtilizationSeries]? = nil) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated,
            costSummary: nil,
            budget: nil,
            rateWindows: [],
            utilizationHistory: utilization)
    }

    private static func makeSeries(
        name: String = "session",
        windowMinutes: Int = 300,
        entries: [SyncUtilizationEntry] = [
            SyncUtilizationEntry(
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                usedPercent: 42,
                resetsAt: nil),
        ]) -> SyncUtilizationSeries
    {
        SyncUtilizationSeries(name: name, windowMinutes: windowMinutes, entries: entries)
    }

    private static func makeSnapshot(
        providers: [ProviderUsageSnapshot] = [makeProvider()],
        syncTimestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        deviceID: String? = "mac-1") -> SyncedUsageSnapshot
    {
        SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: syncTimestamp,
            deviceName: "Test Mac",
            deviceID: deviceID,
            appVersion: "0.20.0",
            mobileVersion: "1.3.0",
            notificationPushEnabled: true)
    }

    // MARK: - Hotspot 1: UtilizationAggregateView

    @Test
    func `UtilizationAggregateView: same input → same key`() {
        let providers = [Self.makeProvider(id: "a"), Self.makeProvider(id: "b")]
        let k1 = UtilizationAggregateModelBuilder.identityKey(for: providers, windowSize: 30)
        let k2 = UtilizationAggregateModelBuilder.identityKey(for: providers, windowSize: 30)
        #expect(k1 == k2)
    }

    @Test
    func `UtilizationAggregateView: changed providerID → different key`() {
        let k1 = UtilizationAggregateModelBuilder.identityKey(
            for: [Self.makeProvider(id: "a")], windowSize: 30)
        let k2 = UtilizationAggregateModelBuilder.identityKey(
            for: [Self.makeProvider(id: "b")], windowSize: 30)
        #expect(k1 != k2)
    }

    @Test
    func `UtilizationAggregateView: changed lastUpdated → different key`() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let k1 = UtilizationAggregateModelBuilder.identityKey(
            for: [Self.makeProvider(lastUpdated: base)], windowSize: 30)
        let k2 = UtilizationAggregateModelBuilder.identityKey(
            for: [Self.makeProvider(lastUpdated: base.addingTimeInterval(60))], windowSize: 30)
        #expect(k1 != k2)
    }

    @Test
    func `UtilizationAggregateView: provider order does not affect key`() {
        let a = Self.makeProvider(id: "a")
        let b = Self.makeProvider(id: "b")
        let k1 = UtilizationAggregateModelBuilder.identityKey(for: [a, b], windowSize: 30)
        let k2 = UtilizationAggregateModelBuilder.identityKey(for: [b, a], windowSize: 30)
        #expect(k1 == k2)
    }

    @Test
    func `UtilizationAggregateView: different windowSize → different key`() {
        let p = [Self.makeProvider()]
        #expect(UtilizationAggregateModelBuilder.identityKey(for: p, windowSize: 30)
            != UtilizationAggregateModelBuilder.identityKey(for: p, windowSize: 7))
    }

    // MARK: - Hotspot 2: UtilizationHistoryView

    @Test
    func `UtilizationHistoryView: same series & index → same key`() {
        let s = [Self.makeSeries()]
        let k1 = UtilizationHistoryView.identityKey(series: s, selectedSeriesIndex: 0)
        let k2 = UtilizationHistoryView.identityKey(series: s, selectedSeriesIndex: 0)
        #expect(k1 == k2)
    }

    @Test
    func `UtilizationHistoryView: changed selectedSeriesIndex → different key`() {
        let s = [
            Self.makeSeries(name: "session"),
            Self.makeSeries(name: "weekly", windowMinutes: 10080),
        ]
        let k1 = UtilizationHistoryView.identityKey(series: s, selectedSeriesIndex: 0)
        let k2 = UtilizationHistoryView.identityKey(series: s, selectedSeriesIndex: 1)
        #expect(k1 != k2)
    }

    @Test
    func `UtilizationHistoryView: new entry appended → different key`() {
        let base = [
            SyncUtilizationEntry(
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                usedPercent: 10,
                resetsAt: nil),
        ]
        let extended = base + [
            SyncUtilizationEntry(
                capturedAt: Date(timeIntervalSince1970: 1_700_000_060),
                usedPercent: 20,
                resetsAt: nil),
        ]
        let k1 = UtilizationHistoryView.identityKey(
            series: [Self.makeSeries(entries: base)], selectedSeriesIndex: 0)
        let k2 = UtilizationHistoryView.identityKey(
            series: [Self.makeSeries(entries: extended)], selectedSeriesIndex: 0)
        #expect(k1 != k2)
    }

    // MARK: - Hotspot 3: CostShareCardView / ShareCardData.displayProviders

    @Test
    func `ShareCardData.displayProviders is deterministic for the same provider list`() {
        let providers: [ShareCardData.ProviderRow] = [
            ShareCardData.ProviderRow(name: "A", cost: 10, share: 0.5, color: .red),
            ShareCardData.ProviderRow(name: "B", cost: 6, share: 0.3, color: .blue),
            ShareCardData.ProviderRow(name: "C", cost: 3, share: 0.15, color: .green),
            ShareCardData.ProviderRow(name: "D", cost: 1, share: 0.05, color: .orange),
        ]
        let data = ShareCardData(
            totalCost: 20, todayCost: 5, totalTokens: 1000, activeDays: 7, avgDailyCost: 3,
            providers: providers, topModels: [], dailyBars: [])
        let first = data.displayProviders
        let second = data.displayProviders
        #expect(first.count == second.count)
        #expect(first.map(\.name) == second.map(\.name))
        #expect(first.map(\.cost) == second.map(\.cost))
    }

    @Test
    func `ShareCardData.displayProviders collapses tail to 'Others' when 6 or more providers`() {
        // iOS 1.9.0 cap: top 5 + an aggregated "Others" row, only when count >= 6.
        let rows: [ShareCardData.ProviderRow] = (0..<6).map {
            ShareCardData.ProviderRow(name: "P\($0)", cost: Double(6 - $0), share: 0.1, color: .gray)
        }
        let data = ShareCardData(
            totalCost: 21, todayCost: 0, totalTokens: 0, activeDays: 0, avgDailyCost: 0,
            providers: rows, topModels: [], dailyBars: [])
        let display = data.displayProviders
        #expect(display.count == 6)
        #expect(display.prefix(5).map(\.name) == ["P0", "P1", "P2", "P3", "P4"])
        #expect(display.last?.name == String(localized: "Others"))
        // The Others bucket aggregates only the tail beyond the top 5 (P5, cost 1).
        #expect(display.last?.cost == 1)
    }

    @Test
    func `ShareCardData.displayProviders shows all when 5 or fewer providers (no 'Others')`() {
        let rows: [ShareCardData.ProviderRow] = (0..<5).map {
            ShareCardData.ProviderRow(name: "P\($0)", cost: Double(5 - $0), share: 0.2, color: .gray)
        }
        let data = ShareCardData(
            totalCost: 15, todayCost: 0, totalTokens: 0, activeDays: 0, avgDailyCost: 0,
            providers: rows, topModels: [], dailyBars: [])
        let display = data.displayProviders
        #expect(display.count == 5)
        #expect(display.last?.name == "P4")
    }

    // MARK: - Hotspot 5: CostTab insights memo key

    //
    // History: the first CostTab cache attempt used async `.task(id:)` and was
    // reverted — first render had cachedInsights=nil and rendered nothing until
    // the task fired, breaking UI tests. The current memo uses the
    // synchronous-resolve-on-miss + `.onChange(initial: true)` store pattern
    // (same as UtilizationHistoryView.resolvedPoints), so the first frame
    // always computes inline and these tests only need to pin key semantics.

    @Test
    func `CostTab key: same inputs → same key`() {
        let snapshotKey = SnapshotIdentityKey.make(
            providerIDs: ["claude", "codex"],
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
        let k1 = CostTab.insightsCacheKey(
            isDemoMode: false, snapshotKey: snapshotKey,
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-11")
        let k2 = CostTab.insightsCacheKey(
            isDemoMode: false, snapshotKey: snapshotKey,
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-11")
        #expect(k1 == k2)
    }

    @Test
    func `CostTab key: snapshot refresh (lastUpdated bump) → different key`() {
        let k1 = CostTab.insightsCacheKey(
            isDemoMode: false,
            snapshotKey: SnapshotIdentityKey.make(
                providerIDs: ["claude"],
                lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)),
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-11")
        let k2 = CostTab.insightsCacheKey(
            isDemoMode: false,
            snapshotKey: SnapshotIdentityKey.make(
                providerIDs: ["claude"],
                lastUpdated: Date(timeIntervalSince1970: 1_700_000_060)),
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-11")
        #expect(k1 != k2)
    }

    @Test
    func `CostTab key: CWL toggle and window changes → different keys`() {
        let snapshotKey = SnapshotIdentityKey.make(
            providerIDs: ["claude"],
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
        let blob = CostTab.insightsCacheKey(
            isDemoMode: false, snapshotKey: snapshotKey,
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-11")
        let cwl30 = CostTab.insightsCacheKey(
            isDemoMode: false, snapshotKey: snapshotKey,
            cwlEnabled: true, cwlWindowDays: 30, todayKey: "2026-06-11")
        let cwl90 = CostTab.insightsCacheKey(
            isDemoMode: false, snapshotKey: snapshotKey,
            cwlEnabled: true, cwlWindowDays: 90, todayKey: "2026-06-11")
        #expect(blob != cwl30)
        #expect(cwl30 != cwl90)
    }

    @Test
    func `CostTab key: CWL window is irrelevant while CWL is off`() {
        let snapshotKey = SnapshotIdentityKey.make(
            providerIDs: ["claude"],
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
        let k1 = CostTab.insightsCacheKey(
            isDemoMode: false, snapshotKey: snapshotKey,
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-11")
        let k2 = CostTab.insightsCacheKey(
            isDemoMode: false, snapshotKey: snapshotKey,
            cwlEnabled: false, cwlWindowDays: 90, todayKey: "2026-06-11")
        #expect(k1 == k2)
    }

    @Test
    func `CostTab key: day rollover → different key`() {
        let snapshotKey = SnapshotIdentityKey.make(
            providerIDs: ["claude"],
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
        let k1 = CostTab.insightsCacheKey(
            isDemoMode: false, snapshotKey: snapshotKey,
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-11")
        let k2 = CostTab.insightsCacheKey(
            isDemoMode: false, snapshotKey: snapshotKey,
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-12")
        #expect(k1 != k2)
    }

    @Test
    func `CostTab key: demo mode masks snapshot identity and CWL source`() {
        let k1 = CostTab.insightsCacheKey(
            isDemoMode: true,
            snapshotKey: SnapshotIdentityKey.make(
                providerIDs: ["claude"],
                lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)),
            cwlEnabled: true, cwlWindowDays: 90, todayKey: "2026-06-11")
        let k2 = CostTab.insightsCacheKey(
            isDemoMode: true,
            snapshotKey: nil,
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-11")
        #expect(k1 == k2)
    }

    @Test
    func `CostTab key: nil snapshot vs demo vs real snapshot are distinct`() {
        let real = CostTab.insightsCacheKey(
            isDemoMode: false,
            snapshotKey: SnapshotIdentityKey.make(
                providerIDs: ["claude"],
                lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)),
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-11")
        let none = CostTab.insightsCacheKey(
            isDemoMode: false, snapshotKey: nil,
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-11")
        let demo = CostTab.insightsCacheKey(
            isDemoMode: true, snapshotKey: nil,
            cwlEnabled: false, cwlWindowDays: 30, todayKey: "2026-06-11")
        #expect(real != none)
        #expect(none != demo)
        #expect(real != demo)
    }
}
