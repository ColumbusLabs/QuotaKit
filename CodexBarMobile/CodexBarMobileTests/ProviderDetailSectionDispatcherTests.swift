import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Provider detail section dispatcher")
struct ProviderDetailSectionDispatcherTests {
    @Test("Perplexity credits claim the primary section")
    func perplexityPrimarySection() {
        let credits = SyncPerplexityCreditSummary(planName: "Pro")
        let provider = Self.snapshot(
            providerID: "perplexity",
            providerName: "Perplexity",
            perplexityCredits: credits)

        if case .perplexity(let actual) = ProviderDetailSectionDispatcher.primarySection(for: provider) {
            #expect(actual == credits)
        } else {
            Issue.record("Expected Perplexity primary section")
        }
    }

    @Test("Dedicated Kiro card suppresses generic rate window primary")
    func dedicatedKiroPrimarySuppression() {
        let credits = SyncKiroCredits(
            planName: "Pro",
            creditsUsed: 10,
            creditsTotal: 100,
            creditsPercent: 10,
            bonusUsed: nil,
            bonusTotal: nil,
            bonusExpiryDays: nil,
            resetsAt: nil)
        let provider = Self.snapshot(providerID: "kiro", providerName: "Kiro", kiroCredits: credits)

        if case .suppressedByDedicatedCard = ProviderDetailSectionDispatcher.primarySection(for: provider) {
            #expect(true)
        } else {
            Issue.record("Expected dedicated-card primary suppression")
        }
        #expect(ProviderDetailSectionDispatcher.sections(for: provider, hasRateWindowPace: false).map(\.id) == ["kiro"])
    }

    @Test("Codex workspace pace only renders when rate windows do not already show pace")
    func codexWorkspacePaceGating() {
        let context = SyncCodexWorkspaceContext(
            workspaceID: "workspace-1",
            workspaceName: nil,
            weeklyPaceDelta: 0.12,
            weeklyPaceLabel: "Ahead of pace",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let provider = Self.snapshot(providerID: "codex", providerName: "Codex", codexWorkspace: context)

        #expect(ProviderDetailSectionDispatcher.sections(for: provider, hasRateWindowPace: false).map(\.id) == ["codex-workspace"])
        #expect(ProviderDetailSectionDispatcher.sections(for: provider, hasRateWindowPace: true).isEmpty)
    }

    @Test("Antigravity account section requires more than one account")
    func antigravityRequiresMultipleAccounts() {
        let one = SyncMultiAccountList(
            accounts: [SyncMultiAccountEntry(email: "one@example.com", isActive: true, expiresAt: nil)],
            activeIndex: 0)
        let two = SyncMultiAccountList(
            accounts: [
                SyncMultiAccountEntry(email: "one@example.com", isActive: true, expiresAt: nil),
                SyncMultiAccountEntry(email: "two@example.com", isActive: false, expiresAt: nil),
            ],
            activeIndex: 0)

        let single = Self.snapshot(providerID: "antigravity", providerName: "Antigravity", antigravityAccounts: one)
        let multiple = Self.snapshot(providerID: "antigravity", providerName: "Antigravity", antigravityAccounts: two)

        #expect(ProviderDetailSectionDispatcher.sections(for: single, hasRateWindowPace: false).isEmpty)
        #expect(ProviderDetailSectionDispatcher.sections(for: multiple, hasRateWindowPace: false).map(\.id) == ["antigravity"])
    }

    private static func snapshot(
        providerID: String,
        providerName: String,
        perplexityCredits: SyncPerplexityCreditSummary? = nil,
        kiroCredits: SyncKiroCredits? = nil,
        antigravityAccounts: SyncMultiAccountList? = nil,
        codexWorkspace: SyncCodexWorkspaceContext? = nil) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerName,
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
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            perplexityCredits: perplexityCredits,
            kiroCredits: kiroCredits,
            antigravityAccounts: antigravityAccounts,
            codexWorkspace: codexWorkspace)
    }
}
