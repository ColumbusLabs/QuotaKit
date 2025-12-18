import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@Suite
struct MenuCardModelTests {
    @Test
    func buildsMetricsUsingRemainingPercent() {
        let now = Date()
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 22,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3000),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 40,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(6000),
                resetDescription: nil),
            updatedAt: now,
            accountEmail: "codex@example.com",
            loginMethod: "Plus Plan")
        let metadata = ProviderDefaults.metadata[.codex]!
        let updatedSnap = UsageSnapshot(
            primary: snapshot.primary,
            secondary: RateWindow(
                usedPercent: snapshot.secondary!.usedPercent,
                windowMinutes: snapshot.secondary!.windowMinutes,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil),
            tertiary: snapshot.tertiary,
            updatedAt: now,
            accountEmail: snapshot.accountEmail,
            accountOrganization: snapshot.accountOrganization,
            loginMethod: snapshot.loginMethod)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: updatedSnap,
            credits: CreditsSnapshot(remaining: 12, events: [], updatedAt: now),
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            account: AccountInfo(email: "codex@example.com", plan: "Plus Plan"),
            isRefreshing: false,
            lastError: nil))

        #expect(model.providerName == "Codex")
        #expect(model.metrics.count == 2)
        #expect(model.metrics.first?.percentLeft == 78)
        #expect(model.planText == "Plus")
        #expect(model.subtitleText.hasPrefix("Updated"))
        #expect(model.progressColor != Color.clear)
        #expect(model.metrics[1].resetText?.isEmpty == false)
    }

    @Test
    func showsCodeReviewMetricWhenDashboardPresent() {
        let now = Date()
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now,
            accountEmail: "codex@example.com",
            accountOrganization: nil,
            loginMethod: nil)
        let metadata = ProviderDefaults.metadata[.codex]!

        let dashboard = OpenAIDashboardSnapshot(
            signedInEmail: "codex@example.com",
            codeReviewRemainingPercent: 73,
            creditEvents: [],
            dailyBreakdown: [],
            updatedAt: now)
        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: dashboard,
            dashboardError: nil,
            account: AccountInfo(email: "codex@example.com", plan: nil),
            isRefreshing: false,
            lastError: nil))

        #expect(model.metrics.contains { $0.title == "Code review" && $0.percentLeft == 73 })
    }

    @Test
    func claudeModelHidesWeeklyWhenUnavailable() {
        let now = Date()
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 2,
                windowMinutes: nil,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "Max")
        let metadata = ProviderDefaults.metadata[.claude]!
        let model = UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            account: AccountInfo(email: "codex@example.com", plan: "plus"),
            isRefreshing: false,
            lastError: nil))

        #expect(model.metrics.count == 1)
        #expect(model.metrics.first?.title == "Session")
        #expect(model.planText == "Max")
    }

    @Test
    func showsErrorSubtitleWhenPresent() {
        let metadata = ProviderDefaults.metadata[.codex]!
        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: nil,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: "Probe failed for Codex"))

        #expect(model.subtitleStyle == .error)
        #expect(model.subtitleText.contains("Probe failed"))
        #expect(model.placeholder == nil)
    }

    @Test
    func claudeModelDoesNotLeakCodexPlan() {
        let metadata = ProviderDefaults.metadata[.claude]!
        let model = UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: metadata,
            snapshot: nil,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            account: AccountInfo(email: "codex@example.com", plan: "plus"),
            isRefreshing: false,
            lastError: nil))

        #expect(model.planText == nil)
        #expect(model.email.isEmpty)
    }
}
