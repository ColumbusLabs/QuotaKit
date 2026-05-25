// swiftlint:disable multiline_arguments
//
// Mirrors `SyncCoordinatorV026MapperTests` for the 6 mappers added
// in v0.27.0 (Mac build 65.1 → 65.4 + iOS 1.8.0 build 132 → 136).
// Closes the integration-test gap flagged by the Opus 4.7 CR (build
// 135). Covers wrong-provider early-return and missing-payload
// early-return for each mapper, plus the nil-pruning behaviour that
// keeps iOS from rendering empty cards.
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore
@testable import CodexBarSync

@MainActor
@Suite("SyncCoordinator v0.27 mappers")
struct SyncCoordinatorV027MapperTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - mapClaudeAdminUsage

    @Test("Claude Admin mapper: returns nil when provider != .claude")
    func claudeAdminWrongProviderReturnsNil() {
        let admin = ClaudeAdminAPIUsageSnapshot(
            daily: [Self.adminBucket(day: "2026-05-01", cost: 1.0, total: 100)],
            updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, claudeAdminAPIUsage: admin, updatedAt: Self.now)
        #expect(SyncCoordinator.mapClaudeAdminUsage(
            provider: .openai, snapshot: snapshot) == nil)
    }

    @Test("Claude Admin mapper: returns nil when claudeAdminAPIUsage is missing")
    func claudeAdminMissingPayloadReturnsNil() {
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, updatedAt: Self.now)
        #expect(SyncCoordinator.mapClaudeAdminUsage(
            provider: .claude, snapshot: snapshot) == nil)
    }

    @Test("Claude Admin mapper: returns nil when last30Days has zero cost AND zero tokens")
    func claudeAdminEmptyWindowReturnsNil() {
        // Mapper SHOULD prune empty windows so iOS doesn't render a
        // "$0.00 / 0 tokens" section. Regression guard for that
        // nil-pruning behaviour.
        let admin = ClaudeAdminAPIUsageSnapshot(daily: [], updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, claudeAdminAPIUsage: admin, updatedAt: Self.now)
        #expect(SyncCoordinator.mapClaudeAdminUsage(
            provider: .claude, snapshot: snapshot) == nil)
    }

    @Test("Claude Admin mapper: emits envelope when last30Days has tokens")
    func claudeAdminPopulatedWindowEmitsEnvelope() {
        let admin = ClaudeAdminAPIUsageSnapshot(
            daily: [Self.adminBucket(day: "2026-05-01", cost: 12.5, total: 500_000)],
            updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, claudeAdminAPIUsage: admin, updatedAt: Self.now)
        let result = SyncCoordinator.mapClaudeAdminUsage(
            provider: .claude, snapshot: snapshot)
        #expect(result != nil)
        #expect(result?.last30Days.totalTokens == 500_000)
        #expect(result?.last30Days.costUSD == 12.5)
    }

    @Test("Claude Admin mapper: caps top-models + top-cost-items at 8")
    func claudeAdminCapsTopLists() {
        // Build a snapshot whose summary aggregation produces 10
        // models and 10 cost items, then assert the mapper truncates
        // to 8 entries each (wire-payload cap).
        let models = (0..<10).map { Self.adminModel(name: "model-\($0)", tokens: 1000 - $0) }
        let costItems = (0..<10).map { Self.adminCostItem(name: "item-\($0)", cost: Double(100 - $0)) }
        let admin = ClaudeAdminAPIUsageSnapshot(
            daily: [Self.adminBucket(
                day: "2026-05-01", cost: 1000.0, total: 100_000,
                models: models, costItems: costItems)],
            updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, claudeAdminAPIUsage: admin, updatedAt: Self.now)
        let result = SyncCoordinator.mapClaudeAdminUsage(
            provider: .claude, snapshot: snapshot)
        #expect(result?.topModels.count == 8)
        #expect(result?.topCostItems.count == 8)
    }

    // MARK: - mapMiniMaxBilling

    @Test("MiniMax billing mapper: returns nil when provider != .minimax")
    func minimaxBillingWrongProviderReturnsNil() {
        let billing = MiniMaxBillingSummary(
            todayTokens: 1000, last30DaysTokens: 30000,
            todayCash: 1.5, last30DaysCash: 45.0,
            daily: [MiniMaxBillingDay(day: "2026-05-01", tokens: 1000, cash: 1.5)],
            topMethods: [], topModels: [], updatedAt: Self.now)
        let mini = MiniMaxUsageSnapshot(
            planName: "Pro", availablePrompts: nil, currentPrompts: nil,
            remainingPrompts: nil, windowMinutes: nil, usedPercent: nil,
            resetsAt: nil, updatedAt: Self.now, services: nil,
            billingSummary: billing)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, minimaxUsage: mini, updatedAt: Self.now)
        #expect(SyncCoordinator.mapMiniMaxBilling(
            provider: .claude, snapshot: snapshot) == nil)
    }

    @Test("MiniMax billing mapper: returns nil when billingSummary is missing")
    func minimaxBillingMissingSummaryReturnsNil() {
        let mini = MiniMaxUsageSnapshot(
            planName: "Pro", availablePrompts: nil, currentPrompts: nil,
            remainingPrompts: nil, windowMinutes: nil, usedPercent: nil,
            resetsAt: nil, updatedAt: Self.now, services: nil,
            billingSummary: nil)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, minimaxUsage: mini, updatedAt: Self.now)
        #expect(SyncCoordinator.mapMiniMaxBilling(
            provider: .minimax, snapshot: snapshot) == nil)
    }

    @Test("MiniMax billing mapper: returns nil for empty 30-day window")
    func minimaxBillingEmptyWindowReturnsNil() {
        let billing = MiniMaxBillingSummary(
            todayTokens: 0, last30DaysTokens: 0,
            todayCash: nil, last30DaysCash: nil,
            daily: [], topMethods: [], topModels: [],
            updatedAt: Self.now)
        let mini = MiniMaxUsageSnapshot(
            planName: nil, availablePrompts: nil, currentPrompts: nil,
            remainingPrompts: nil, windowMinutes: nil, usedPercent: nil,
            resetsAt: nil, updatedAt: Self.now, services: nil,
            billingSummary: billing)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, minimaxUsage: mini, updatedAt: Self.now)
        #expect(SyncCoordinator.mapMiniMaxBilling(
            provider: .minimax, snapshot: snapshot) == nil)
    }

    @Test("MiniMax billing mapper: caps method+model lists at top-3")
    func minimaxBillingCapsBreakdowns() {
        let methods = (0..<5).map {
            MiniMaxBillingBreakdown(name: "method-\($0)", tokens: 100 - $0, cash: nil)
        }
        let models = (0..<5).map {
            MiniMaxBillingBreakdown(name: "model-\($0)", tokens: 100 - $0, cash: nil)
        }
        let billing = MiniMaxBillingSummary(
            todayTokens: 100, last30DaysTokens: 3000,
            todayCash: nil, last30DaysCash: nil,
            daily: [MiniMaxBillingDay(day: "2026-05-01", tokens: 100, cash: nil)],
            topMethods: methods, topModels: models, updatedAt: Self.now)
        let mini = MiniMaxUsageSnapshot(
            planName: nil, availablePrompts: nil, currentPrompts: nil,
            remainingPrompts: nil, windowMinutes: nil, usedPercent: nil,
            resetsAt: nil, updatedAt: Self.now, services: nil,
            billingSummary: billing)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, minimaxUsage: mini, updatedAt: Self.now)
        let result = SyncCoordinator.mapMiniMaxBilling(
            provider: .minimax, snapshot: snapshot)
        #expect(result?.topMethods.count == 3)
        #expect(result?.topModels.count == 3)
    }

    // MARK: - mapOpenCodeGoZenBalance

    @Test("OpenCodeGo Zen mapper: returns nil when provider != .opencodego")
    func zenBalanceWrongProviderReturnsNil() {
        let cost = ProviderCostSnapshot(
            used: 42.5, limit: 0, currencyCode: "USD",
            period: "Zen balance", updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, providerCost: cost, updatedAt: Self.now)
        #expect(SyncCoordinator.mapOpenCodeGoZenBalance(
            provider: .claude, snapshot: snapshot,
            providerCost: cost, workspaceID: nil) == nil)
    }

    @Test("OpenCodeGo Zen mapper: returns nil when providerCost period is not 'Zen balance'")
    func zenBalanceWrongPeriodReturnsNil() {
        let cost = ProviderCostSnapshot(
            used: 42.5, limit: 100.0, currencyCode: "USD",
            period: "Monthly", updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, providerCost: cost, updatedAt: Self.now)
        #expect(SyncCoordinator.mapOpenCodeGoZenBalance(
            provider: .opencodego, snapshot: snapshot,
            providerCost: cost, workspaceID: nil) == nil)
    }

    @Test("OpenCodeGo Zen mapper: emits envelope when period matches + currency USD")
    func zenBalanceMatchEmitsEnvelope() {
        let cost = ProviderCostSnapshot(
            used: 42.5, limit: 0, currencyCode: "USD",
            period: "Zen balance", updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, providerCost: cost, updatedAt: Self.now)
        let result = SyncCoordinator.mapOpenCodeGoZenBalance(
            provider: .opencodego, snapshot: snapshot,
            providerCost: cost, workspaceID: "ws-acme")
        #expect(result?.balanceUSD == 42.5)
        #expect(result?.workspaceID == "ws-acme")
    }

    // MARK: - Fixture builders

    private static func adminBucket(
        day: String,
        cost: Double,
        total: Int,
        models: [ClaudeAdminAPIUsageSnapshot.ModelBreakdown] = [],
        costItems: [ClaudeAdminAPIUsageSnapshot.CostBreakdown] = []) -> ClaudeAdminAPIUsageSnapshot.DailyBucket
    {
        ClaudeAdminAPIUsageSnapshot.DailyBucket(
            day: day,
            startTime: self.now,
            endTime: self.now,
            costUSD: cost,
            inputTokens: total / 2,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: total / 2,
            totalTokens: total,
            costItems: costItems,
            models: models)
    }

    private static func adminModel(name: String, tokens: Int) -> ClaudeAdminAPIUsageSnapshot.ModelBreakdown {
        ClaudeAdminAPIUsageSnapshot.ModelBreakdown(
            name: name,
            inputTokens: tokens / 2,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: tokens / 2,
            totalTokens: tokens)
    }

    private static func adminCostItem(name: String, cost: Double) -> ClaudeAdminAPIUsageSnapshot.CostBreakdown {
        ClaudeAdminAPIUsageSnapshot.CostBreakdown(name: name, costUSD: cost)
    }
}

// swiftlint:enable multiline_arguments
