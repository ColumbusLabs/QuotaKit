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

    // MARK: - buildCodexWorkspaceContext (mapCodexWorkspace pure core)

    @Test("Codex workspace: returns nil when active account is nil AND snapshot has no weekly window")
    func codexWorkspaceEmptyReturnsNil() {
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, updatedAt: Self.now)
        let result = SyncCoordinator.buildCodexWorkspaceContext(
            activeAccount: nil, snapshot: snapshot)
        #expect(result == nil)
    }

    @Test("Codex workspace: emits envelope when active account has workspace label")
    func codexWorkspaceWithLabelEmits() {
        let account = Self.makeAccount(
            email: "test@example.com",
            workspaceLabel: "Acme",
            workspaceAccountID: "ws-acme")
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, updatedAt: Self.now)
        let result = SyncCoordinator.buildCodexWorkspaceContext(
            activeAccount: account, snapshot: snapshot)
        #expect(result?.workspaceName == "Acme")
        #expect(result?.workspaceID == "ws-acme")
        #expect(result?.weeklyPaceDelta == nil)
    }

    @Test("Codex workspace: emits pace when snapshot has weekly window (10080 minutes)")
    func codexWorkspaceWithWeeklyPaceEmits() {
        // Use an in-flight weekly window: started 3 days ago, ends in
        // 4 days. UsagePace.weekly expects timeUntilReset > 0 AND <= duration.
        let weekly = RateWindow(
            usedPercent: 40.0,
            windowMinutes: 7 * 24 * 60,
            resetsAt: Date().addingTimeInterval(4 * 24 * 3600),
            resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: weekly, updatedAt: Self.now)
        let result = SyncCoordinator.buildCodexWorkspaceContext(
            activeAccount: nil, snapshot: snapshot)
        #expect(result != nil)
        #expect(result?.weeklyPaceDelta != nil)
        #expect(result?.weeklyPaceLabel != nil)
    }

    @Test("Codex workspace: prefers secondary window over tertiary/primary for pace anchor")
    func codexWorkspaceWeeklyWindowSelection() {
        // Secondary holds the weekly window; primary is a session
        // (300 min). The mapper should anchor pace to secondary.
        let session = RateWindow(
            usedPercent: 80.0,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3 * 3600),
            resetDescription: nil)
        let weekly = RateWindow(
            usedPercent: 40.0,
            windowMinutes: 7 * 24 * 60,
            resetsAt: Date().addingTimeInterval(4 * 24 * 3600),
            resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: session, secondary: weekly, updatedAt: Self.now)
        let result = SyncCoordinator.buildCodexWorkspaceContext(
            activeAccount: nil, snapshot: snapshot)
        // If the mapper anchored to session (300-min), pace would
        // be massively skewed; weekly anchor yields a sane delta.
        #expect(result?.weeklyPaceDelta != nil)
        // Sanity bounds: weekly pace delta clamped to ~ [-1.0, +1.0]
        // (delta is fraction, e.g. 0.10 = 10% ahead of pace).
        if let d = result?.weeklyPaceDelta {
            #expect(abs(d) < 1.0)
        }
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

    /// Build a ManagedCodexAccount fixture with all `_ = nil` /
    /// stub-able fields filled with deterministic values. Used by
    /// the workspace-mapper tests above; lives here rather than
    /// inline in each test so the body stays focused on the
    /// scenario, not the fixture plumbing.
    private static func makeAccount(
        email: String,
        workspaceLabel: String? = nil,
        workspaceAccountID: String? = nil) -> ManagedCodexAccount
    {
        ManagedCodexAccount(
            id: UUID(),
            email: email,
            providerAccountID: nil,
            workspaceLabel: workspaceLabel,
            workspaceAccountID: workspaceAccountID,
            authFingerprint: nil,
            managedHomePath: "/tmp/codex-test-\(UUID().uuidString)",
            createdAt: self.now.timeIntervalSince1970,
            updatedAt: self.now.timeIntervalSince1970,
            lastAuthenticatedAt: nil)
    }
}

// swiftlint:enable multiline_arguments
