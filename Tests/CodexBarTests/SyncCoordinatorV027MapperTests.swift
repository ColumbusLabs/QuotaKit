// swiftlint:disable multiline_arguments
//
// Coverage for the retained Codex, Claude, and Grok companion mappers.
// Includes provider gating, nil pruning, field conversion, and pace mapping.
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore
@testable import CodexBarSync

@MainActor
@Suite("SyncCoordinator v0.27 mappers")
struct SyncCoordinatorV027MapperTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - mapCodexCreditLimit

    @Test
    func `Codex credit-limit mapper emits monthly credit summary`() {
        let resetsAt = Date(timeIntervalSince1970: 1_700_086_400)
        let credits = CreditsSnapshot(
            remaining: 92239,
            events: [],
            updatedAt: Self.now,
            codexCreditLimit: CodexCreditLimitSnapshot(
                used: 7761,
                limit: 100_000,
                remainingPercent: 92.239,
                resetsAt: resetsAt,
                updatedAt: Self.now))

        let result = SyncCoordinator.mapCodexCreditLimit(provider: .codex, credits: credits)

        #expect(result?.title == "Monthly credit limit")
        #expect(result?.used == 7761)
        #expect(result?.limit == 100_000)
        #expect(result?.remaining == 92239)
        #expect(result?.remainingPercent == 92.239)
        #expect(abs((result?.usedPercent ?? 0) - 7.761) < 0.001)
        #expect(result?.resetsAt == resetsAt)
    }

    @Test
    func `Codex credit-limit mapper prunes non-Codex and missing payloads`() {
        let credits = CreditsSnapshot(
            remaining: 92239,
            events: [],
            updatedAt: Self.now,
            codexCreditLimit: CodexCreditLimitSnapshot(
                used: 7761,
                limit: 100_000,
                remainingPercent: 92.239,
                resetsAt: nil,
                updatedAt: Self.now))

        #expect(SyncCoordinator.mapCodexCreditLimit(provider: .claude, credits: credits) == nil)
        #expect(SyncCoordinator.mapCodexCreditLimit(provider: .codex, credits: nil) == nil)
        #expect(SyncCoordinator.mapCodexCreditLimit(
            provider: .codex,
            credits: CreditsSnapshot(remaining: 0, events: [], updatedAt: Self.now)) == nil)
    }

    // MARK: - mapClaudeAdminUsage

    @Test
    func `Claude Admin mapper: returns nil when provider != .claude`() {
        let admin = ClaudeAdminAPIUsageSnapshot(
            daily: [Self.adminBucket(day: "2026-05-01", cost: 1.0, total: 100)],
            updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, claudeAdminAPIUsage: admin, updatedAt: Self.now)
        #expect(SyncCoordinator.mapClaudeAdminUsage(
            provider: .codex, snapshot: snapshot) == nil)
    }

    @Test
    func `Claude Admin mapper: returns nil when claudeAdminAPIUsage is missing`() {
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, updatedAt: Self.now)
        #expect(SyncCoordinator.mapClaudeAdminUsage(
            provider: .claude, snapshot: snapshot) == nil)
    }

    @Test
    func `Claude Admin mapper: returns nil when last30Days has zero cost AND zero tokens`() {
        // Mapper SHOULD prune empty windows so iOS doesn't render a
        // "$0.00 / 0 tokens" section. Regression guard for that
        // nil-pruning behaviour.
        let admin = ClaudeAdminAPIUsageSnapshot(daily: [], updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, claudeAdminAPIUsage: admin, updatedAt: Self.now)
        #expect(SyncCoordinator.mapClaudeAdminUsage(
            provider: .claude, snapshot: snapshot) == nil)
    }

    @Test
    func `Claude Admin mapper: emits envelope when last30Days has tokens`() {
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

    @Test
    func `Claude Admin mapper: caps top-models + top-cost-items at 8`() {
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

    // MARK: - mapGrokBilling

    @Test
    func `Grok billing mapper converts cents and preserves billing period`() throws {
        let billing = GrokBillingResponse(
            billingCycle: GrokBillingCycle(
                billingPeriodStart: "2026-05-01T00:00:00Z",
                billingPeriodEnd: "2026-06-01T00:00:00Z"),
            monthlyLimit: GrokCent(val: 5000),
            onDemandCap: nil,
            onDemandEnabled: false,
            disabledByConfig: false,
            usage: GrokBillingUsage(
                includedUsed: GrokCent(val: 1250),
                onDemandUsed: nil,
                totalUsed: GrokCent(val: 1250)))
        let grok = GrokUsageSnapshot(
            billing: billing,
            credentials: nil,
            localSummary: nil,
            cliVersion: nil,
            updatedAt: Self.now)

        let result = try #require(SyncCoordinator.mapGrokBilling(
            provider: .grok,
            snapshot: grok.toUsageSnapshot()))

        #expect(result.monthlyUsedPercent == 25)
        #expect(result.monthlySpendUSD == 12.50)
        #expect(result.monthlyLimitUSD == 50)
        #expect(result.billingPeriodEndDate != nil)
        #expect(result.updatedAt == Self.now)
    }

    @Test
    func `Grok billing mapper prunes wrong provider and empty payload`() {
        let webOnly = GrokUsageSnapshot(
            billing: nil,
            webBilling: GrokWebBillingSnapshot(usedPercent: nil, resetsAt: nil),
            credentials: nil,
            localSummary: nil,
            cliVersion: nil,
            updatedAt: Self.now)
        let snapshot = webOnly.toUsageSnapshot()

        #expect(SyncCoordinator.mapGrokBilling(provider: .claude, snapshot: snapshot) == nil)
        #expect(SyncCoordinator.mapGrokBilling(provider: .grok, snapshot: snapshot) == nil)
    }

    // MARK: - buildCodexWorkspaceContext (mapCodexWorkspace pure core)

    @Test
    func `Codex workspace: returns nil when active account is nil AND snapshot has no weekly window`() {
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, updatedAt: Self.now)
        let result = SyncCoordinator.buildCodexWorkspaceContext(
            activeAccount: nil, snapshot: snapshot)
        #expect(result == nil)
    }

    @Test
    func `Codex workspace: emits envelope when active account has workspace label`() {
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

    @Test
    func `Codex workspace: emits pace when snapshot has weekly window (10080 minutes)`() {
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

    @Test
    func `Codex workspace: anchors pace to secondary when BOTH secondary + primary are ≥ 1-day windows`() {
        // Both primary AND secondary pass the `codexWeeklyWindow`
        // ≥ 1-day filter; the mapper must pick secondary (per the
        // `[secondary, tertiary, primary]` priority order in
        // `SyncCoordinator.codexWeeklyWindow`). Construct two
        // windows with distinct `usedPercent` so the anchored
        // result is visibly different — the test then proves
        // selection by checking the resulting pace delta matches
        // the secondary's actualUsedPercent (40%), not the
        // primary's (80%).
        //
        // Both windows have ~50% elapsed (started 3.5d ago, end in
        // 3.5d), so expected pace is ~50%. Secondary at 40% used
        // → delta ≈ -10% (= -0.10 fraction). Primary at 80% used
        // → delta ≈ +30% (= +0.30 fraction). If the test sees a
        // delta < 0 we proved the mapper picked the secondary's
        // 40% over the primary's 80%.
        let now = Date()
        let resetIn3Days = now.addingTimeInterval(3.5 * 24 * 3600)
        let primaryHighUse = RateWindow(
            usedPercent: 80.0,
            windowMinutes: 7 * 24 * 60,
            resetsAt: resetIn3Days,
            resetDescription: nil)
        let secondaryLowUse = RateWindow(
            usedPercent: 40.0,
            windowMinutes: 7 * 24 * 60,
            resetsAt: resetIn3Days,
            resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: primaryHighUse, secondary: secondaryLowUse, updatedAt: Self.now)
        let result = SyncCoordinator.buildCodexWorkspaceContext(
            activeAccount: nil, snapshot: snapshot)
        // Secondary anchor → delta is negative (40% used vs ~50%
        // expected). Primary anchor would have produced positive
        // delta (80% used vs ~50% expected).
        #expect(result?.weeklyPaceDelta != nil)
        if let d = result?.weeklyPaceDelta {
            #expect(
                d < 0,
                "expected secondary anchor (40% used → negative delta); got \(d) — primary anchor was picked instead")
        }
    }

    @Test
    func `Sync pace mapper preserves Mac session deficit text and numeric fields`() throws {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 80,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 3600),
            resetDescription: nil)
        let pace = try #require(UsagePaceText.sessionPace(provider: .claude, window: window, now: now))
        let detail = try #require(UsagePaceText.sessionDetail(provider: .claude, window: window, now: now))

        let syncPace = SyncCoordinator.syncUsagePace(from: pace, detail: detail)

        #expect(syncPace.stage == .farAhead)
        #expect(syncPace.deltaPercent == 20)
        #expect(syncPace.expectedUsedPercent == 60)
        #expect(syncPace.actualUsedPercent == 80)
        #expect(syncPace.leftLabel == "20% in deficit")
        #expect(syncPace.rightLabel == "Projected empty in 45m")
    }

    @Test
    func `Sync pace mapper preserves Mac weekly reserve text`() throws {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 10,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(4 * 24 * 3600),
            resetDescription: nil)
        let pace = try #require(UsagePace.weekly(window: window, now: now))
        let detail = UsagePaceText.weeklyDetail(provider: .claude, pace: pace, now: now)

        let syncPace = SyncCoordinator.syncUsagePace(from: pace, detail: detail)

        #expect(syncPace.stage == .farBehind)
        #expect(syncPace.leftLabel == "33% in reserve")
        #expect(syncPace.rightLabel == "Lasts until reset")
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
