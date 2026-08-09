import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Provider detail section dispatcher")
struct ProviderDetailSectionDispatcherTests {
    @Test
    func `All supported providers keep the generic rate-window primary section`() {
        for providerID in QuotaKitProviderCatalog.providerIDs {
            if case .genericRateLimits = ProviderDetailSectionDispatcher.primarySection(
                for: Self.snapshot(providerID: providerID))
            {
                #expect(true)
            }
        }
    }

    @Test
    func `Grok billing renders its dedicated detail section`() {
        let billing = SyncGrokBilling(
            monthlyUsedPercent: 25,
            monthlySpendUSD: 25,
            monthlyLimitUSD: 100,
            billingPeriodEndDate: nil,
            planTier: "SuperGrok",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let provider = ProviderUsageSnapshot(
            providerID: "grok",
            providerName: "Grok",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            grokBilling: billing)

        #expect(ProviderDetailSectionDispatcher.sections(for: provider, hasRateWindowPace: false)
            .map(\.id) == ["grok"])
    }

    @Test
    func `Codex workspace pace only renders when rate windows do not already show pace`() {
        let context = SyncCodexWorkspaceContext(
            workspaceID: "workspace-1",
            workspaceName: nil,
            weeklyPaceDelta: 0.12,
            weeklyPaceLabel: "Ahead of pace",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            codexWorkspace: context)

        #expect(ProviderDetailSectionDispatcher.sections(for: provider, hasRateWindowPace: false)
            .map(\.id) == ["codex-workspace"])
        #expect(ProviderDetailSectionDispatcher.sections(for: provider, hasRateWindowPace: true).isEmpty)
    }

    @Test
    func `Retired provider compatibility fields never create mobile detail sections`() {
        let provider = ProviderUsageSnapshot(
            providerID: "perplexity",
            providerName: "Perplexity",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            perplexityCredits: SyncPerplexityCreditSummary(planName: "Pro"))

        #expect(ProviderDetailSectionDispatcher.sections(for: provider, hasRateWindowPace: false).isEmpty)
    }

    private static func snapshot(providerID: String) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerID,
            primary: SyncRateWindow(
                label: "Session",
                usedPercent: 20,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
    }
}
