import CodexBarCore
import Foundation
import Testing

@Suite
struct OpenRouterUsageStatsTests {
    @Test
    func toUsageSnapshot_doesNotSetSyntheticResetDescription() {
        let snapshot = OpenRouterUsageSnapshot(
            totalCredits: 50,
            totalUsage: 45.3895596325,
            balance: 4.6104403675,
            usedPercent: 90.779119265,
            rateLimit: nil,
            updatedAt: Date(timeIntervalSince1970: 1_739_841_600))

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.resetsAt == nil)
        #expect(usage.primary?.resetDescription == nil)
    }
}
