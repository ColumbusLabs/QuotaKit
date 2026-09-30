import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct UsageStoreMenuCardModelTests {
    @Test(arguments: [UsageDataConfidence.estimated, .exact])
    func `account pace uses its own confidence instead of the live account`(confidence: UsageDataConfidence) {
        let store = self.makeStore()
        let now = OpenCodeGoPaceTestSupport.now
        store.snapshots[.opencodego] = OpenCodeGoPaceTestSupport.snapshot(
            confidence: confidence == .estimated ? .exact : .estimated)
        let input = store.menuCardInput(
            for: .opencodego,
            context: .account(.init(snapshot: OpenCodeGoPaceTestSupport.snapshot(confidence: confidence))),
            now: now)

        #expect((input.weeklyPace != nil) == (confidence != .estimated))
    }

    @Test
    func `shared card inputs preserve scoped weekly observations without changing history`() throws {
        let store = self.makeStore()
        let snapshot = self.snapshot()
        store.snapshots[.claude] = snapshot
        let accountKey = try #require(UsageStore.planUtilizationIdentityAccountKey(
            provider: .claude, snapshot: snapshot))
        let reset = try #require(snapshot.secondary?.resetsAt)
        let history = PlanUtilizationSeriesHistory(name: .weekly, windowMinutes: 10080, entries: [
            .init(capturedAt: snapshot.updatedAt, usedPercent: 50, resetsAt: reset),
        ])
        store.planUtilizationHistory[.claude] = PlanUtilizationHistoryBuckets(
            preferredAccountKey: accountKey,
            accounts: [accountKey: [history]])
        let original = store.planUtilizationHistory
        let revision = store.planUtilizationHistoryRevision
        let expected = [CostUsageQuotaResetObservation(capturedAt: snapshot.updatedAt, resetsAt: reset)]

        let menu = store.menuCardInput(for: .claude, context: .menu, now: snapshot.updatedAt)
        let settings = store.menuCardInput(for: .claude, context: .settings, now: snapshot.updatedAt)
        let empty = store.menuCardInput(for: .claude, context: .account(.init()), now: snapshot.updatedAt)
        let identityless = store.menuCardInput(
            for: .claude,
            context: .account(.init(snapshot: UsageSnapshot(
                primary: snapshot.primary,
                secondary: snapshot.secondary,
                updatedAt: snapshot.updatedAt))),
            now: snapshot.updatedAt)
        let selected = store.menuCardInput(
            for: .claude,
            context: .account(.init(historySelection: .init(accountKey: accountKey, histories: [history]))),
            now: snapshot.updatedAt)

        #expect(menu.observedWeeklyResets == expected)
        #expect(settings.observedWeeklyResets == expected)
        #expect(empty.observedWeeklyResets.isEmpty)
        #expect(identityless.observedWeeklyResets.isEmpty)
        #expect(selected.observedWeeklyResets == expected)
        #expect(store.planUtilizationHistory == original)
        #expect(store.planUtilizationHistoryRevision == revision)
    }

    private func makeStore() -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "UsageStoreMenuCardModelTests",
            userDefaults: InMemoryUserDefaults())
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._cancelPlanUtilizationHistoryLoadForTesting()
        store.planUtilizationHistory = [:]
        return store
    }

    private func snapshot() -> UsageSnapshot {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return UsageSnapshot(
            primary: .init(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: .init(
                usedPercent: 50,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(86400),
                resetDescription: nil),
            updatedAt: now,
            identity: .init(
                providerID: .claude,
                accountEmail: "fixture@example.com",
                accountOrganization: nil,
                loginMethod: "max"))
    }
}
