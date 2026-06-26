import CodexBarSync
import Foundation
import SwiftUI
import Testing
@testable import CodexBarMobile

/// Regression tests for the iOS 1.5.3 multi-account `ForEach` id collision.
///
/// **The bug.** Two `ProviderUsageSnapshot` rows for the same provider but
/// different `accountEmail` (e.g. a user with two Codex accounts on two
/// Macs, one Mac on a version that extracts accountEmail and another that
/// doesn't) used to collide on three downstream identity sites:
///   1. `CostBreakdownRow.id` (provider name)
///   2. `CostBudgetRow.id` (raw providerID)
///   3. `UtilizationProviderShare.id` (raw providerID) and
///      the per-day `UtilizationDaySegment.providerID` ForEach key
///
/// All three now key on `cardIdentityKey = providerID|accountEmail`. These
/// tests pin that contract so a future refactor that "simplifies" the id
/// back to `providerID` immediately breaks the test rather than silently
/// corrupting the Cost dashboard.
@Suite("Multi-account ForEach identity (1.5.3 collision fix)")
struct MultiAccountForEachIdentityTests {
    // MARK: - Test fixtures

    private static func makeCodexSnapshot(accountEmail: String?, thirtyDayCost: Double) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: accountEmail,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: thirtyDayCost,
                last30DaysTokens: 1000,
                daily: []),
            budget: SyncBudgetSnapshot(
                usedAmount: thirtyDayCost,
                limitAmount: 5000,
                currencyCode: "USD",
                period: "monthly",
                resetsAt: nil))
    }

    private static func makeCodexSnapshotWithUtilization(
        accountEmail: String?,
        peakPercentPerDay: Double) -> ProviderUsageSnapshot
    {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var entries: [SyncUtilizationEntry] = []
        for dayOffset in 0..<5 {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            entries.append(SyncUtilizationEntry(
                capturedAt: day,
                usedPercent: peakPercentPerDay,
                resetsAt: nil))
        }
        return ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: accountEmail,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            utilizationHistory: [SyncUtilizationSeries(
                name: "session", windowMinutes: 300, entries: entries)])
    }

    // MARK: - CostDashboardInsights.ProviderRow

    @Test("Two Codex accounts produce two ProviderRows with distinct ids")
    func providerRowsHaveDistinctIDsForMultiAccount() {
        let snapshot = SyncedUsageSnapshot(
            providers: [
                Self.makeCodexSnapshot(accountEmail: "user@example.com", thirtyDayCost: 18.40),
                Self.makeCodexSnapshot(accountEmail: nil, thirtyDayCost: 1592.89),
            ],
            syncTimestamp: Date(),
            deviceName: "Test")

        let insights = CostDashboardInsights(snapshot: snapshot)
        #expect(insights.providerRows.count == 2)

        let ids = Set(insights.providerRows.map(\.id))
        #expect(
            ids.count == 2,
            "ProviderRow.id must be unique across multi-account same-provider rows; got duplicates: \(insights.providerRows.map(\.id))")
        #expect(ids.contains("codex|user@example.com"))
        #expect(ids.contains("codex|"))
    }

    @Test("ProviderRow.id encodes providerID and accountEmail")
    func providerRowIdFormat() {
        let snapshot = SyncedUsageSnapshot(
            providers: [Self.makeCodexSnapshot(accountEmail: "user@example.com", thirtyDayCost: 100)],
            syncTimestamp: Date(),
            deviceName: "Test")
        let insights = CostDashboardInsights(snapshot: snapshot)
        let row = try? #require(insights.providerRows.first)
        #expect(row?.id == "codex|user@example.com")
    }

    // MARK: - CostBreakdownRow

    @Test("CostBreakdownRow without identityOverride falls back to label-as-id")
    func breakdownRowFallsBackToLabel() {
        let row = CostBreakdownRow(
            label: "claude-opus-4-7",
            amountUSD: 100,
            subtitle: nil,
            color: .blue)
        #expect(
            row.id == "claude-opus-4-7",
            "Existing Model Mix / Service Mix call sites still key on label")
    }

    @Test("CostBreakdownRow with identityOverride uses override as id")
    func breakdownRowUsesOverride() {
        let row = CostBreakdownRow(
            label: "Codex",
            amountUSD: 18.40,
            subtitle: nil,
            color: .purple,
            identityOverride: "codex|user@example.com")
        #expect(
            row.id == "codex|user@example.com",
            "Provider Share call site must supply cardIdentityKey to avoid multi-account collision")
    }

    @Test("Two Codex breakdown rows with same label but different identityOverride have distinct ids")
    func breakdownRowMultiAccountDistinctIDs() {
        let withEmail = CostBreakdownRow(
            label: "Codex", amountUSD: 18.40, subtitle: nil, color: .purple,
            identityOverride: "codex|user@example.com")
        let noEmail = CostBreakdownRow(
            label: "Codex", amountUSD: 1592.89, subtitle: nil, color: .purple,
            identityOverride: "codex|")

        #expect(
            withEmail.id != noEmail.id,
            "Identity override must keep multi-account Codex rows distinguishable in ForEach")
    }

    // MARK: - CostBudgetRow

    @Test("CostBudgetRow.id uses cardIdentityKey, not raw providerID")
    func budgetRowMultiAccountDistinctIDs() throws {
        let withEmail = Self.makeCodexSnapshot(accountEmail: "user@example.com", thirtyDayCost: 18.40)
        let noEmail = Self.makeCodexSnapshot(accountEmail: nil, thirtyDayCost: 1592.89)

        let budget1 = try CostBudgetRow(provider: withEmail, budget: #require(withEmail.budget))
        let budget2 = try CostBudgetRow(provider: noEmail, budget: #require(noEmail.budget))

        #expect(budget1.id == "codex|user@example.com")
        #expect(budget2.id == "codex|")
        #expect(
            budget1.id != budget2.id,
            "Two Codex budgets from different accounts must not collide on a single ForEach slot")
    }

    // MARK: - UtilizationProviderShare

    @Test("Two Codex providers in UtilizationAggregateView build distinct ProviderShare ids")
    func utilizationProviderSharesHaveDistinctIDs() throws {
        let withEmail = Self.makeCodexSnapshotWithUtilization(
            accountEmail: "user@example.com", peakPercentPerDay: 25)
        let noEmail = Self.makeCodexSnapshotWithUtilization(
            accountEmail: nil, peakPercentPerDay: 75)

        let model = try #require(UtilizationAggregateModelBuilder.buildModel(
            from: [withEmail, noEmail], windowSize: 30))

        #expect(
            model.providerShares.count == 2,
            "Both Codex accounts must surface as separate share entries")
        let ids = Set(model.providerShares.map(\.id))
        #expect(
            ids.count == 2,
            "ProviderShare.id must be unique across multi-account rows; got \(model.providerShares.map(\.id))")
        #expect(ids.contains("codex|user@example.com"))
        #expect(ids.contains("codex|"))
    }

    @Test("DaySegments for two Codex accounts on the same day carry distinct identifiers")
    func utilizationDaySegmentsHaveDistinctIDs() throws {
        let withEmail = Self.makeCodexSnapshotWithUtilization(
            accountEmail: "user@example.com", peakPercentPerDay: 25)
        let noEmail = Self.makeCodexSnapshotWithUtilization(
            accountEmail: nil, peakPercentPerDay: 75)

        let model = try #require(UtilizationAggregateModelBuilder.buildModel(
            from: [withEmail, noEmail], windowSize: 30))

        // The chart code does `ForEach(bar.segments, id: \.providerID)`; the
        // `providerID` field now carries cardIdentityKey for uniqueness.
        for bar in model.dayBars where !bar.isPadding && !bar.segments.isEmpty {
            let segmentIDs = bar.segments.map(\.providerID)
            #expect(
                Set(segmentIDs).count == segmentIDs.count,
                "Day \(bar.dayLabel ?? "?") has duplicate segment ids: \(segmentIDs)")
            // Both Codex accounts must have contributed to this day's stack.
            #expect(segmentIDs.contains("codex|user@example.com"))
            #expect(segmentIDs.contains("codex|"))
        }
    }
}
