import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct SpendDashboardTokenProvenanceTests {
    @Test
    func `token publication counter remains monotonic across clear and identical republish`() {
        let store = Self.makeStore()
        let snapshot = Self.tokenSnapshot(cost: 9)
        store._setTokenSnapshotForTesting(snapshot, provider: .claude)
        let firstRevision = store.tokenSnapshotPublicationRevision(for: .claude)

        store._setTokenSnapshotForTesting(nil, provider: .claude)
        store._setTokenSnapshotForTesting(snapshot, provider: .claude)

        #expect(store.tokenSnapshotPublicationRevision(for: .claude) > firstRevision)
        #expect(store.tokenSnapshotForCurrentProviderConfig(for: .claude)?.snapshot == snapshot)
    }

    private static func makeStore() -> UsageStore {
        let settings = testSettingsStore(suiteName: "SpendDashboardTokenProvenanceTests")
        settings.costUsageEnabled = true
        for provider in UsageProvider.allCases {
            guard let metadata = ProviderRegistry.shared.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == .claude)
        }
        return UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
    }

    private static func tokenSnapshot(cost: Double) -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: cost,
            last30DaysTokens: 10,
            last30DaysCostUSD: cost,
            currencyCode: "USD",
            daily: [CostUsageDailyReport.Entry(
                date: "2026-07-16",
                inputTokens: 4,
                outputTokens: 6,
                totalTokens: 10,
                costUSD: cost,
                modelsUsed: nil,
                modelBreakdowns: nil)],
            updatedAt: Date(timeIntervalSince1970: 1_784_203_200))
    }
}
