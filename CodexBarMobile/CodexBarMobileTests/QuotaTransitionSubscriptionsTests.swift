import CloudKit
import Testing
@testable import CodexBarMobile

/// Pins the `CKSubscription.NotificationInfo` payload used by every quota
/// transition subscription. The `shouldSendMutableContent = true` bit in
/// particular regressed silently in 1.6.0 build ≤121 — every quota push
/// landed without `mutable-content: 1`, so iOS never woke the NSE, and
/// the rich body (`"Codex session usage at 50% threshold"`) was never
/// substituted for the static fallback (`"Codex usage warning"`). If this
/// test fails, all quota push body / title rewrites are dead.
@Suite("Quota transition subscriptions")
struct QuotaTransitionSubscriptionsTests {
    @Test
    func `notification info sets alertBody from input`() {
        let info = QuotaTransitionSubscriptions.makeNotificationInfo(
            alertBody: "Codex 用量警告")
        #expect(info.alertBody == "Codex 用量警告")
    }

    @Test
    func `notification info wakes NSE via mutable-content flag`() {
        let info = QuotaTransitionSubscriptions.makeNotificationInfo(
            alertBody: "anything")
        // shouldSendMutableContent translates into `mutable-content: 1`
        // in the APNS payload, which is the ONLY way to wake the
        // NotificationService extension to rewrite the push body.
        #expect(info.shouldSendMutableContent == true)
    }

    @Test
    func `notification info plays default sound`() {
        let info = QuotaTransitionSubscriptions.makeNotificationInfo(
            alertBody: "anything")
        #expect(info.soundName == "default")
    }

    @Test
    func `notification info leaves localization-args empty`() {
        // titleLocalizationArgs / alertLocalizationArgs are intentionally
        // unused on this CloudKit container; the localized body is baked
        // into `alertBody` at setup time. The drift-detection logic in
        // setupIfNeeded() rejects subs whose info has either of these
        // populated, so leaving them nil here is part of the contract.
        let info = QuotaTransitionSubscriptions.makeNotificationInfo(
            alertBody: "anything")
        #expect((info.titleLocalizationArgs ?? []).isEmpty)
        #expect((info.alertLocalizationArgs ?? []).isEmpty)
    }

    @Test
    func `managed subscription IDs cover every provider state`() {
        let ids = QuotaTransitionSubscriptions.managedSubscriptionIDs(providerIDs: ["codex", "claude"])

        #expect(ids == [
            "quota-codex-depleted-sub",
            "quota-codex-restored-sub",
            "quota-codex-warning-sub",
            "quota-claude-depleted-sub",
            "quota-claude-restored-sub",
            "quota-claude-warning-sub",
        ])
    }

    @Test
    func `locked Pro notification plan keeps silent sync and removes quota alerts`() {
        let plan = ProNotificationSetupPlanner.plan(isProUnlocked: false)

        #expect(plan.shouldSetupSilentSync)
        #expect(!plan.shouldRequestAlertPermission)
        #expect(!plan.shouldSetupQuotaAlerts)
        #expect(plan.shouldRemoveQuotaAlerts)
    }

    @Test
    func `unlocked Pro notification plan keeps silent sync and creates quota alerts`() {
        let plan = ProNotificationSetupPlanner.plan(isProUnlocked: true)

        #expect(plan.shouldSetupSilentSync)
        #expect(plan.shouldRequestAlertPermission)
        #expect(plan.shouldSetupQuotaAlerts)
        #expect(!plan.shouldRemoveQuotaAlerts)
    }
}
