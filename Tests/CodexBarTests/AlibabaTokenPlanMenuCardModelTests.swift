import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct AlibabaTokenPlanMenuCardModelTests {
    @Test
    func `restored Personal monthly-only usage keeps the Monthly label`() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let snapshot = try AlibabaTokenPlanPersonalUsageParser.parse(
            from: Data(#"{"per1MonthPercentage":0.25}"#.utf8),
            subscriptionData: nil,
            quotaConfigData: nil,
            now: now).toUsageSnapshot()
        let restored = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored.alibabaTokenPlanUsage == nil)
        let metadata = try #require(ProviderDefaults.metadata[.alibabatokenplan])
        let model = UsageMenuCardView.Model.make(.init(
            provider: .alibabatokenplan,
            metadata: metadata,
            snapshot: restored,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.metrics.map(\.title) == ["Monthly"])
        #expect(AlibabaTokenPlanProviderDescriptor.descriptor.presentation
            .rateWindowLabels(metadata: metadata, snapshot: restored).primary == "Monthly")
        #expect(AlibabaTokenPlanProviderDescriptor.primaryLabel(snapshot: restored) == "Monthly")
    }

    @Test
    func `Personal rolling windows use duration labels`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = AlibabaTokenPlanUsageSnapshot(
            planName: "Pro",
            usedQuota: nil,
            totalQuota: nil,
            remainingQuota: nil,
            resetsAt: nil,
            fiveHourUsedPercent: 0,
            weeklyUsedPercent: 10,
            updatedAt: now)
            .toUsageSnapshot()
        let metadata = try #require(ProviderDefaults.metadata[.alibabatokenplan])

        let model = UsageMenuCardView.Model.make(.init(
            provider: .alibabatokenplan,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.metrics.map(\.title) == ["5-hour", "7-day"])
    }

    @Test
    func `monthly quota shows deficit and run out details`() throws {
        let now = Date(timeIntervalSince1970: 10_368_000) // 1970-05-01T00:00:00Z
        let snapshot = AlibabaTokenPlanUsageSnapshot(
            planName: "TOKEN PLAN",
            usedQuota: 900,
            totalQuota: 1000,
            remainingQuota: nil,
            resetsAt: now.addingTimeInterval(6 * 24 * 3600),
            updatedAt: now)
            .toUsageSnapshot()
        let metadata = try #require(ProviderDefaults.metadata[.alibabatokenplan])

        let model = UsageMenuCardView.Model.make(.init(
            provider: .alibabatokenplan,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.metrics.map(\.title) == ["Monthly"])
        let monthly = try #require(model.metrics.first { $0.id == "primary" })
        #expect(monthly.percentLabel == "10% left")
        #expect(monthly.detailText == "900 / 1,000 credits used")
        #expect(monthly.detailLeftText == "10% in deficit")
        #expect(monthly.detailRightText == "Runs out in 2d 16h")
        #expect(monthly.pacePercent == 20)
        #expect(monthly.paceOnTop == false)
    }
}
