import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ClaudeMenuCardCostTests {
    private static let now = Date(timeIntervalSince1970: 1_782_000_000)

    @Test(arguments: [false, true])
    func `capped extra usage uses one metric with caption reset and pace`(showUsed: Bool) throws {
        let model = try Self.makeModel(
            cost: Self.cost(used: 25, limit: 100, balance: 20), showUsed: showUsed)
        let metric = try #require(model.metrics.first)

        #expect(model.providerCost == nil)
        #expect(model.metrics.count == 1)
        #expect(metric.id == "claude-extra-usage")
        #expect(metric.percent == (showUsed ? 25 : 75))
        #expect(metric.percentStyle == (showUsed ? .used : .left))
        #expect(metric.detailText == "Monthly cap: $25.00 / $100.00 · Balance: $20.00")
        #expect(metric.resetText == "Resets in 10d")
        #expect(metric.detailRightText == "Lasts until reset")
        #expect(metric.pacePercent != nil)
        #expect(metric.helpText?.contains("00:00 UTC on the 1st") == true)
    }

    @MainActor
    @Test
    func `monthly cap keeps the extra usage visibility and pace gates`() throws {
        let model = try Self.makeModel(
            cost: Self.cost(used: 40, limit: 100), showUsed: true, paceVisible: false)
        let metric = try #require(model.metrics.first)

        #expect(metric.detailText == "Monthly cap: $40.00 / $100.00")
        #expect(metric.resetText != nil)
        #expect(metric.pacePercent == nil)
        #expect(metric.detailRightText == nil)
        #expect(model.usageItemDescriptors.contains { $0.id == .claudeExtraUsage && $0.requiresOptionalUsage })
        #expect(model.applyingUsageItemVisibility(hiddenItemIDs: [.claudeExtraUsage]).metrics.isEmpty)
    }

    @Test(arguments: [false, true])
    func `globally hidden extra usage has no meter`(showUsed: Bool) throws {
        let model = try Self.makeModel(
            cost: Self.cost(used: 25, limit: 100), showUsed: showUsed, showOptional: false)

        #expect(model.providerCost == nil)
        #expect(model.metrics.isEmpty)
    }

    @Test(arguments: [false, true])
    func `uncapped Claude balance stays a compact cost row`(showUsed: Bool) throws {
        let model = try Self.makeModel(
            cost: Self.cost(used: 0, limit: 0, balance: 100), showUsed: showUsed)

        #expect(model.providerCost?.title == "Credits")
        #expect(model.providerCost?.spendLine == "$100.00")
        #expect(model.providerCost?.balanceLine == nil)
        #expect(model.providerCost?.percentUsed == nil)
        #expect(model.metrics.isEmpty)
    }

    @Test
    func `Claude admin API spend remains visible without a quota meter`() throws {
        let model = try Self.makeModel(
            cost: Self.cost(used: 12.34, limit: 0, period: "Last 30 days"),
            showUsed: false,
            showOptional: false,
            isAdminAPI: true,
            costSummaryInlineEnabled: true)

        #expect(model.providerCost?.title == "API spend")
        #expect(model.providerCost?.spendLine == "Last 30 days: $12.34")
        #expect(model.providerCost?.presentation == .detail)
        #expect(model.providerCost?.showsInProviderDetails == true)
        #expect(model.metrics.isEmpty)
        #expect(model.tokenUsage == nil)
    }

    @Test(arguments: [false, true])
    func `other capped provider costs keep used fill`(showUsed: Bool) throws {
        let section = try #require(UsageMenuCardView.Model.providerCostSection(
            cost: Self.cost(used: 25, limit: 100),
            style: .generic,
            percentStyle: showUsed ? .used : .left,
            preferredCurrencyCode: "USD"))

        #expect(section.percentStyle == .used)
        #expect(section.displayPercent == 25)
        #expect(section.progressAccessibilityLabel == "Extra usage spent")
    }

    private static func makeModel(
        cost: ProviderCostSnapshot,
        showUsed: Bool,
        showOptional: Bool = true,
        isAdminAPI: Bool = false,
        costSummaryInlineEnabled: Bool? = nil,
        paceVisible: Bool = true) throws -> UsageMenuCardView.Model
    {
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: cost,
            updatedAt: self.now,
            identity: isAdminAPI ? ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: "admin@example.com",
                accountOrganization: nil,
                loginMethod: "Admin API") : nil)

        return UsageMenuCardView.Model.make(.init(
            provider: .claude,
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
            usageBarsShowUsed: showUsed,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            costSummaryInlineEnabled: costSummaryInlineEnabled,
            showOptionalCreditsAndExtraUsage: showOptional,
            hidePersonalInfo: false,
            paceVisible: paceVisible,
            preferredCurrencyCode: "USD",
            now: self.now))
    }

    private static func cost(
        used: Double,
        limit: Double,
        period: String = "Monthly cap",
        balance: Double? = nil) -> ProviderCostSnapshot
    {
        ProviderCostSnapshot(
            used: used,
            limit: limit,
            currencyCode: "USD",
            period: period,
            balance: balance,
            updatedAt: self.now)
    }
}
