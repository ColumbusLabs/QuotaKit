import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

struct MenuCardModelTests {
    @Test
    func `overview hides cards that only contain an error`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.cursor])
        let model = UsageMenuCardView.Model.make(.init(
            provider: .cursor,
            metadata: metadata,
            snapshot: nil,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: "No Cursor session found.",
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: Date()))

        #expect(model.isOverviewErrorOnly)
    }

    @Test
    func `claude subscription-only quota keeps local cost content`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tokenSnapshot = CostUsageTokenSnapshot(
            sessionTokens: 4200,
            sessionCostUSD: 1.25,
            last30DaysTokens: 42000,
            last30DaysCostUSD: 12.50,
            daily: [],
            updatedAt: now)
        let quotaError = ClaudeStatusProbeError.parseFailed(
            ClaudeStatusProbe.subscriptionQuotaUnavailableDescription).localizedDescription
        let model = UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: metadata,
            snapshot: nil,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: tokenSnapshot,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: quotaError,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: true,
            tokenCostMenuSectionEnabled: true,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.placeholder == "Limits not available")
        #expect(model.subtitleStyle == .info)
        #expect(model.tokenUsage != nil)
        #expect(model.metrics.isEmpty)
        #expect(!model.isOverviewErrorOnly)
    }

    @Test
    func `codex model builds remaining metrics and warning markers`() throws {
        let now = Date()
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "codex@example.com",
            accountOrganization: nil,
            loginMethod: "Plus Plan")
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 22,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3000),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 40,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil),
            updatedAt: now,
            identity: identity)
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let codexProjection = CodexConsumerProjection.make(
            surface: .liveCard,
            context: CodexConsumerProjection.Context(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: nil,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: now))
        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: snapshot,
            codexProjection: codexProjection,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: "codex@example.com", plan: "Plus Plan"),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            quotaWarningThresholds: [.session: [50, 20], .weekly: [25, 0]],
            now: now))

        #expect(model.providerName == "Codex")
        #expect(model.metrics.map(\.percent) == [78, 60])
        #expect(model.metrics.first?.warningMarkerPercents == [50, 20])
        #expect(model.metrics[1].warningMarkerPercents == [25])
        #expect(model.planText == "Plus")
        #expect(model.progressColor != Color.clear)
    }

    @Test
    func `claude model hides weekly when unavailable`() throws {
        let now = Date()
        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "Max")
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 2,
                windowMinutes: nil,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now,
            identity: identity)
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let model = UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: "codex@example.com", plan: "plus"),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.metrics.count == 1)
        #expect(model.metrics.first?.title == "Session")
        #expect(model.planText == "Max")
    }

    @Test
    func `hides email when personal info hidden`() throws {
        let now = Date()
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "codex@example.com",
            accountOrganization: nil,
            loginMethod: nil)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now,
            identity: identity)
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: "OpenAI dashboard signed in as codex@example.com.",
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: "codex@example.com", plan: nil),
            isRefreshing: false,
            lastError: "OpenAI dashboard signed in as codex@example.com.",
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: true,
            now: now))

        #expect(model.email.isEmpty)
        #expect(!model.subtitleText.contains("codex@example.com"))
        #expect(model.creditsHintCopyText?.isEmpty == true)
        #expect(model.creditsHintText?.contains("codex@example.com") == false)
    }
}
