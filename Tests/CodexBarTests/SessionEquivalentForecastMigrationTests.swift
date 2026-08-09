import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

extension SessionEquivalentForecastTests {
    @MainActor
    @Test
    func `retained generic provider adopts matching unscoped history`() async throws {
        let store = UsageStorePlanUtilizationTests.makeStore()
        store.settings.historicalTrackingEnabled = true
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 20,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 40,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(3 * 24 * 3600),
                resetDescription: nil),
            updatedAt: now)
        let identity = try #require(store.sessionEquivalentWindows(
            provider: .cursor,
            snapshot: snapshot)?.historyIdentity)
        store.planUtilizationHistory[.cursor] = PlanUtilizationHistoryBuckets(unscoped: [
            planSeries(
                name: .session,
                windowMinutes: 300,
                entries: [planEntry(at: now.addingTimeInterval(-3600), usedPercent: 10)]),
            planSeries(
                name: .weekly,
                windowMinutes: 10080,
                entries: [planEntry(at: now.addingTimeInterval(-3600), usedPercent: 30)]),
        ])
        store.settings.userDefaults.set(
            [
                "cursor|\(UsageStore.planUtilizationUnscopedPreferredKey)": identity,
                "grok|\(UsageStore.planUtilizationUnscopedPreferredKey)": "unrelated-pair",
            ],
            forKey: UsageStore.legacySessionEquivalentHistoryIdentityDefaultsKey)
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "Cursor test",
            token: "fixture",
            addedAt: 0,
            lastUsed: nil)
        let accountKey = try #require(UsageStore._planUtilizationTokenAccountKeyForTesting(
            provider: .cursor,
            account: account))

        await store.recordPlanUtilizationHistorySample(
            provider: .cursor,
            snapshot: snapshot,
            account: account,
            now: now)

        let migrated = try #require(store.planUtilizationHistory[.cursor])
        let histories = migrated.histories(for: accountKey)
        #expect(migrated.unscoped.isEmpty)
        #expect(migrated.sessionEquivalentWindowPairIdentity(for: nil) == nil)
        #expect(migrated.sessionEquivalentWindowPairIdentity(for: accountKey) == identity)
        #expect(findSeries(histories, name: .session, windowMinutes: 300)?.entries.map(\.usedPercent) == [10, 20])
        #expect(findSeries(histories, name: .weekly, windowMinutes: 10080)?.entries.map(\.usedPercent) == [30, 40])
        #expect(store.legacySessionEquivalentHistoryIdentity(provider: .grok, accountKey: nil) == "unrelated-pair")
    }
}
