import Foundation
import Testing
@testable import CodexBarCore

struct StepFunCreditPresentationTests {
    @Test
    func `credit balance without a reset keeps its label and unknown reset`() throws {
        let payload = #"{"status":1,"plan_family":2,"plan_credit_rate_limit":{"subscription_credit_left_rate":0.25}}"#
        let parsed = try StepFunUsageFetcher._parseSnapshotForTesting(Data(payload.utf8))
        let usage = parsed.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 75)
        #expect(usage.primary?.windowMinutes == nil)
        #expect(usage.primary?.resetsAt == nil)
        #expect(usage.primary?.resetDescription == nil)
        let metadata = try #require(ProviderDefaults.metadata[.stepfun])
        let labels = StepFunProviderDescriptor.descriptor.presentation.rateWindowLabels(
            metadata: metadata,
            snapshot: usage)
        #expect(labels.primary == "Credit")
    }

    @Test
    func `coding plan keeps its rolling window labels`() throws {
        let payload = #"""
        {"status":1,"five_hour_usage_left_rate":0.7,"five_hour_usage_reset_time":"1790812800",
         "weekly_usage_left_rate":0.8,"weekly_usage_reset_time":"1790899200"}
        """#
        let parsed = try StepFunUsageFetcher._parseSnapshotForTesting(Data(payload.utf8))
        let usage = parsed.toUsageSnapshot()
        let metadata = try #require(ProviderDefaults.metadata[.stepfun])
        let labels = StepFunProviderDescriptor.descriptor.presentation.rateWindowLabels(
            metadata: metadata,
            snapshot: usage)

        #expect(labels.primary == "5h Window")
        #expect(labels.secondary == "Weekly Window")
    }
}
