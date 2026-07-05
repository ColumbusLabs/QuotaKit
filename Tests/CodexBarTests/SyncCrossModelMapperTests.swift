import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

@Suite("CrossModel sync mapper")
struct SyncCrossModelMapperTests {
    @Test
    @MainActor
    func `CrossModel mapper preserves balance and usage windows`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let source = CrossModelUsageSnapshot(
            currency: "usd",
            balance: 8.059489,
            uncollected: 1.25,
            daily: CrossModelUsageWindow(
                cost: 0.42,
                promptTokens: 8100,
                completionTokens: 4367,
                totalTokens: 12467,
                requestCount: 42,
                successCount: 40),
            weekly: nil,
            monthly: CrossModelUsageWindow(
                cost: 5.368746,
                promptTokens: 410_000,
                completionTokens: 119_000,
                totalTokens: 529_000,
                requestCount: 3166,
                successCount: 3112),
            updatedAt: now)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            crossModelUsage: source,
            updatedAt: now)

        let mapped = try #require(SyncCoordinator.mapCrossModelUsage(provider: .crossmodel, snapshot: snapshot))

        #expect(mapped.currency == "USD")
        #expect(mapped.balance == 8.059489)
        #expect(mapped.uncollected == 1.25)
        #expect(mapped.daily?.totalTokens == 12467)
        #expect(mapped.weekly == nil)
        #expect(mapped.monthly?.requestCount == 3166)
        #expect(mapped.updatedAt == now)
        #expect(SyncCoordinator.mapCrossModelUsage(provider: .codex, snapshot: snapshot) == nil)
    }
}
