import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
extension CodexAccountScopedRefreshTests {
    @Test
    func `prior reset credit from another plan cannot admit unchanged boundary`() async {
        let email = "shared-reset-owner@example.com"
        let now = Date()
        let boundary = now.addingTimeInterval(6 * 24 * 60 * 60)
        let creditExpiry = boundary.addingTimeInterval(24 * 60 * 60)
        let previousAt = now.addingTimeInterval(-180)
        let backfillAt = now.addingTimeInterval(-150)
        let initialAt = now.addingTimeInterval(-120)
        let confirmationAt = now.addingTimeInterval(-119)
        let previousPlanA = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 72,
            weeklyReset: boundary,
            updatedAt: previousAt,
            resetCredits: resetEvidenceCredits(at: previousAt, expiresAt: creditExpiry, available: true),
            dataConfidence: .exact)
            .withIdentity(self.codexIdentitySnapshot(email: email, loginMethod: "Plus"))
        let planBBackfill = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 72,
            weeklyReset: boundary,
            updatedAt: backfillAt,
            resetCredits: resetEvidenceCredits(at: backfillAt, expiresAt: creditExpiry, available: false),
            dataConfidence: .exact)
        let initialPlanB = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 0.2,
            weeklyReset: boundary,
            updatedAt: initialAt,
            resetCredits: resetEvidenceCredits(at: initialAt, expiresAt: creditExpiry, available: false),
            dataConfidence: .exact)
        let confirmationPlanB = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 0.7,
            weeklyReset: boundary,
            updatedAt: confirmationAt,
            resetCredits: resetEvidenceCredits(at: confirmationAt, expiresAt: creditExpiry, available: false),
            dataConfidence: .exact)

        let admission = await UsageStore.codexOutcomeAdmittedForPublication(
            initialOutcome: resetEvidenceOutcome(initialPlanB),
            previousSnapshot: previousPlanA,
            previousSourceLabel: "oauth",
            missingWindowBackfillSnapshot: planBBackfill,
            observedAt: initialAt,
            fetchConfirmation: { resetEvidenceOutcome(confirmationPlanB) })

        #expect(admission.outcome == nil)
        #expect(admission.pendingCandidate == nil)
        #expect(admission.withheldSuccess != nil)
    }
}

private func resetEvidenceCredits(
    at date: Date,
    expiresAt: Date,
    available: Bool) -> CodexRateLimitResetCreditsSnapshot
{
    let credits = available ? [CodexRateLimitResetCredit(
        id: "plan-a-credit",
        resetType: "codex_rate_limits",
        status: .available,
        grantedAt: date.addingTimeInterval(-24 * 60 * 60),
        expiresAt: expiresAt,
        redeemStartedAt: nil,
        redeemedAt: nil,
        title: nil,
        description: nil)] : []
    return CodexRateLimitResetCreditsSnapshot(
        credits: credits,
        availableCount: available ? 1 : 0,
        updatedAt: date)
}

private func resetEvidenceOutcome(_ snapshot: UsageSnapshot) -> ProviderFetchOutcome {
    ProviderFetchOutcome(
        result: .success(ProviderFetchResult(
            usage: snapshot,
            credits: nil,
            dashboard: nil,
            sourceLabel: "oauth",
            strategyID: "weekly-reset-test",
            strategyKind: .oauth)),
        attempts: [])
}
