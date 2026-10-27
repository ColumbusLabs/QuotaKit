import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct TraeCNUsageItemVisibilityTests {
    @Test
    func `quota and credit details have distinct labels without changing visibility identities`() throws {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            details: [.makeSection(title: "Credits", rows: [
                .makeRow(label: "Used", value: "2,000"),
                .makeRow(label: "Total", value: "10,000"),
                .makeRow(label: "Remaining", value: "8,000"),
            ])],
            updatedAt: Date())
        let model = try UsageMenuCardView.Model.make(.init(
            provider: .traecn,
            metadata: #require(ProviderDefaults.metadata[.traecn]),
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
            now: Date()))
        let items = model.usageItemDescriptors
        #expect(items.map(\.id) == [.metric("primary"), .detailSection("Credits")])
        #expect(items.map(\.title) == ["Usage", "Credits"])
        #expect(model.applyingUsageItemVisibility(hiddenItemIDs: [.detailSection("Credits")]).providerDetails.isEmpty)
        #expect(model.applyingUsageItemVisibility(hiddenItemIDs: [.metric("primary")]).metrics.isEmpty)
    }
}
