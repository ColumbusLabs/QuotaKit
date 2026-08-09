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
    func `retired subscription tombstones cover exactly 168 old IDs`() {
        let ids = QuotaTransitionSubscriptions.retiredSubscriptionIDs

        #expect(ids.count == 168)
        #expect(Set(ids).count == 168)
        #expect(ids.contains("quota-perplexity-depleted-sub"))
        #expect(ids.contains("quota-notion-warning-sub"))
        #expect(!ids.contains("quota-codex-depleted-sub"))
        #expect(!ids.contains("quota-claude-restored-sub"))
        #expect(!ids.contains("quota-cursor-warning-sub"))
        #expect(!ids.contains("quota-grok-warning-sub"))
    }

    @Test
    func `cleanup selects retired and legacy IDs but preserves live and unrelated subscriptions`() {
        let retiredID = "quota-perplexity-warning-sub"
        let legacyID = "legacy-quota-sub"
        let ids = QuotaTransitionSubscriptions.subscriptionIDsToDelete(
            existingIDs: [
                retiredID,
                legacyID,
                "quota-codex-warning-sub",
                "device-provider-zone-sub",
            ],
            legacyIDs: [legacyID])

        #expect(ids == [retiredID, legacyID])
    }

    @Test
    func `notification plan always enables sync and quota alerts`() {
        let plan = NotificationSetupPlanner.plan()

        #expect(plan.shouldSetupSilentSync)
        #expect(plan.shouldRequestAlertPermission)
        #expect(plan.shouldSetupQuotaAlerts)
    }
}
