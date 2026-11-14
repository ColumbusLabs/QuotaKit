import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct OpenCodeGoPendingHistoryPublicationTests {
    @Test(arguments: [false, true])
    func `normal refresh retains prior cost while local history is pending`(hasPriorHistory: Bool) async throws {
        let settings = testSettingsStore(
            suiteName: "OpenCodeGoPendingHistoryRefreshTests", userDefaults: InMemoryUserDefaults())
        settings.costUsageEnabled = true
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.costUsageBucketTimeZoneIdentifier = "UTC"
        let metadata = try #require(ProviderRegistry.shared.metadata[.opencodego])
        settings.setProviderEnabled(provider: .opencodego, metadata: metadata, enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let now = Date()
        let day = String(ISO8601DateFormatter().string(from: now).prefix(10))
        let entry = CostUsageDailyReport.Entry(
            date: day,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: 100,
            costUSD: 3,
            modelsUsed: ["fixture-model"],
            modelBreakdowns: nil)
        if hasPriorHistory {
            let local = try OpenCodeGoUsageFetcher.parseAPIUsage(
                text: #"{"usage":{"rolling":{"percent":40}}}"#, now: now).withDaily([entry])
            store.publishProviderDerivedTokenSnapshot(from: local.toUsageSnapshot(), for: .opencodego)
        }
        let before = store.tokenSnapshotPublicationForCurrentProviderConfig(for: .opencodego)
        let beforeRevision = store.tokenSnapshotPublicationRevision(for: .opencodego)
        var remote = try OpenCodeGoUsageFetcher.parseAPIUsage(
            text: #"{"usage":{"rolling":{"percent":50}}}"#, now: now)
        remote.localHistoryPending = true
        let pendingUsage = remote.toUsageSnapshot()
        store._test_providerFetchOutcomeOverride = { _ in Self.outcome(pendingUsage) }
        await store.refreshProvider(.opencodego, allowDisabled: true)
        let pending = store.tokenSnapshotPublicationForCurrentProviderConfig(for: .opencodego)
        #expect(pending?.publicationRevision == before?.publicationRevision)
        #expect(pending?.snapshot == before?.snapshot)
        #expect(store.snapshot(for: .opencodego)?.primary?.usedPercent == 50)

        remote.localHistoryPending = false
        let completeUsage = remote.toUsageSnapshot()
        store._test_providerFetchOutcomeOverride = { _ in Self.outcome(completeUsage) }
        await store.refreshProvider(.opencodego, allowDisabled: true)
        let completed = try #require(store.tokenSnapshotPublicationForCurrentProviderConfig(for: .opencodego))
        #expect(completed.snapshot == nil)
        #expect(completed.publicationRevision == beforeRevision + 1)
    }

    private static func outcome(_ snapshot: UsageSnapshot) -> ProviderFetchOutcome {
        ProviderFetchOutcome(
            result: .success(ProviderFetchResult(
                usage: snapshot,
                credits: nil,
                dashboard: nil,
                sourceLabel: "fixture",
                strategyID: "fixture",
                strategyKind: .localProbe)),
            attempts: [])
    }

    @Test
    func `pending local history does not publish a confirmed empty cost snapshot`() throws {
        let settings = testSettingsStore(
            suiteName: "OpenCodeGoPendingHistoryPublicationTests", userDefaults: InMemoryUserDefaults())
        settings.costUsageEnabled = true
        settings.refreshFrequency = .manual
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let now = Date()
        settings.costUsageBucketTimeZoneIdentifier = "UTC"
        let day = String(ISO8601DateFormatter().string(from: now).prefix(10))
        let entry = CostUsageDailyReport.Entry(
            date: day,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: 100,
            costUSD: 3,
            modelsUsed: ["fixture-model"],
            modelBreakdowns: nil)
        let local = try OpenCodeGoUsageFetcher.parseAPIUsage(
            text: #"{"usage":{"rolling":{"percent":40}}}"#, now: now).withDaily([entry])
        store.publishProviderDerivedTokenSnapshot(from: local.toUsageSnapshot(), for: .opencodego)
        let before = try #require(store.tokenSnapshotPublicationForCurrentProviderConfig(for: .opencodego))
        #expect(before.snapshot?.last30DaysCostUSD == 3)
        var remote = try OpenCodeGoUsageFetcher.parseAPIUsage(
            text: #"{"usage":{"rolling":{"percent":50}}}"#, now: now)
        remote.localHistoryPending = true
        store.installProviderDerivedTokenSnapshot(from: remote.toUsageSnapshot(), for: .opencodego)
        #expect(store.tokenSnapshotPublicationForCurrentProviderConfig(for: .opencodego)?.snapshot == before.snapshot)
        store.publishProviderDerivedTokenSnapshot(from: remote.toUsageSnapshot(), for: .opencodego)
        let after = try #require(store.tokenSnapshotPublicationForCurrentProviderConfig(for: .opencodego))
        print(
            "[opencode-history-publication] before=\(before.snapshot?.last30DaysCostUSD as Any) " +
                "after=\(after.snapshot?.last30DaysCostUSD as Any)")
        #expect(after.publicationRevision == before.publicationRevision)
        #expect(after.snapshot == before.snapshot)
        remote.localHistoryPending = false
        store.publishProviderDerivedTokenSnapshot(from: remote.toUsageSnapshot(), for: .opencodego)
        #expect(store.tokenSnapshotPublicationForCurrentProviderConfig(for: .opencodego)?.snapshot == nil)
    }
}
