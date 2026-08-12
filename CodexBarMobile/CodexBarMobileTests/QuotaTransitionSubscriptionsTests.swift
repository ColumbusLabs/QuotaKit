import CloudKit
import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@MainActor
private final class InMemoryQuotaTransitionSubscriptionDatabase:
    QuotaTransitionSubscriptionDatabase
{
    enum StubError: Error {
        case zoneModificationFailed
    }

    private(set) var subscriptionsByID: [CKSubscription.ID: CKSubscription]
    private(set) var deletedSubscriptionIDs: [CKSubscription.ID] = []
    private(set) var savedSubscriptionBatches: [[CKSubscription]] = []
    private(set) var deletedSubscriptionBatches: [[CKSubscription.ID]] = []
    private(set) var savedZoneBatches: [[CKRecordZone]] = []
    var zoneModificationError: Error?

    init(existingSubscriptions: [CKSubscription] = []) {
        self.subscriptionsByID = Dictionary(
            uniqueKeysWithValues: existingSubscriptions.map {
                ($0.subscriptionID, $0)
            })
    }

    func deleteSubscription(withID subscriptionID: CKSubscription.ID) async throws {
        self.deletedSubscriptionIDs.append(subscriptionID)
        self.subscriptionsByID.removeValue(forKey: subscriptionID)
    }

    func modifyRecordZones(saving zonesToSave: [CKRecordZone]) async throws {
        self.savedZoneBatches.append(zonesToSave)
        if let zoneModificationError {
            throw zoneModificationError
        }
    }

    func allSubscriptions() async throws -> [CKSubscription] {
        Array(self.subscriptionsByID.values)
    }

    func modifySubscriptions(
        saving subscriptionsToSave: [CKSubscription],
        deleting subscriptionIDsToDelete: [CKSubscription.ID]) async throws
    {
        self.savedSubscriptionBatches.append(subscriptionsToSave)
        self.deletedSubscriptionBatches.append(subscriptionIDsToDelete)
        for subscription in subscriptionsToSave {
            self.subscriptionsByID[subscription.subscriptionID] = subscription
        }
        for subscriptionID in subscriptionIDsToDelete {
            self.subscriptionsByID.removeValue(forKey: subscriptionID)
        }
    }
}

/// Pins the `CKSubscription.NotificationInfo` payload used by every quota
/// transition subscription. The `shouldSendMutableContent = true` bit in
/// particular regressed silently in 1.6.0 build ≤121 — every quota push
/// landed without `mutable-content: 1`, so iOS never woke the NSE, and
/// the rich body (`"Codex session usage at 50% threshold"`) was never
/// substituted for the static fallback (`"Codex usage warning"`). If this
/// test fails, all quota push body / title rewrites are dead.
@Suite("Quota transition subscriptions")
struct QuotaTransitionSubscriptionsTests {
    private func makeValidManagedSubscription(
        providerID: String,
        state: String) throws -> CKRecordZoneSubscription
    {
        let provider = try #require(QuotaProviderList.providers.first {
            $0.id == providerID
        })
        let template = switch state {
        case "depleted": String(localized: "Push.QuotaDepleted.bodyWithProvider")
        case "restored": String(localized: "Push.QuotaRestored.bodyWithProvider")
        case "warning": String(localized: "Push.QuotaWarning.bodyWithProvider")
        default: ""
        }
        let body = String(format: template, provider.displayName)
        let zoneID = CKRecordZone.ID(
            zoneName: QuotaProviderList.quotaZoneName(
                providerID: providerID,
                state: state),
            ownerName: CKCurrentUserDefaultName)
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: "quota-\(providerID)-\(state)-sub")
        subscription.recordType = CloudSyncConstants.quotaTransitionRecordType
        subscription.notificationInfo = QuotaTransitionSubscriptions.makeNotificationInfo(
            alertBody: body)
        return subscription
    }

    private func makeZoneSubscription(
        zoneName: String,
        subscriptionID: CKSubscription.ID) -> CKRecordZoneSubscription
    {
        CKRecordZoneSubscription(
            zoneID: CKRecordZone.ID(
                zoneName: zoneName,
                ownerName: CKCurrentUserDefaultName),
            subscriptionID: subscriptionID)
    }

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
    @MainActor
    func `restored reconciliation expands build 176 subscriptions from 12 to 183 without data loss`() async throws {
        let build176ProviderIDs = ["codex", "claude", "cursor", "grok"]
        let states = ["depleted", "restored", "warning"]
        let build176Managed = try build176ProviderIDs.flatMap { providerID in
            try states.map { state in
                try self.makeValidManagedSubscription(
                    providerID: providerID,
                    state: state)
            }
        }
        #expect(build176Managed.count == 12)

        let silentSubscription = self.makeZoneSubscription(
            zoneName: CloudSyncConstants.providerZoneName,
            subscriptionID: DeviceProviderZoneSubscription.subscriptionID)
        let silentInfo = CKSubscription.NotificationInfo()
        silentInfo.shouldSendContentAvailable = true
        silentSubscription.notificationInfo = silentInfo
        let unrelatedSubscription = self.makeZoneSubscription(
            zoneName: "UnrelatedZone",
            subscriptionID: "unrelated-subscription")
        let database = InMemoryQuotaTransitionSubscriptionDatabase(
            existingSubscriptions: build176Managed + [
                silentSubscription,
                unrelatedSubscription,
            ])

        await QuotaTransitionSubscriptions.shared.setupIfNeeded(using: database)

        let allManagedIDs = Set(QuotaTransitionSubscriptions.managedSubscriptionIDs(
            providerIDs: QuotaProviderList.providers.map(\.id)))
        let build176ManagedIDs = Set(build176Managed.map(\.subscriptionID))
        let savedIDs = Set(database.savedSubscriptionBatches.flatMap {
            $0.map(\.subscriptionID)
        })
        let deletedIDs = Set(
            database.deletedSubscriptionIDs
                + database.deletedSubscriptionBatches.flatMap(\.self))
        let finalIDs = Set(database.subscriptionsByID.keys)
        let expectedLegacyCleanupIDs: Set<CKSubscription.ID> = [
            CloudSyncConstants.quotaTransitionLegacySubscriptionID,
            CloudSyncConstants.quotaTransitionDepletedSubscriptionID,
            CloudSyncConstants.quotaTransitionRestoredSubscriptionID,
        ]

        #expect(allManagedIDs.count == 183)
        #expect(database.savedSubscriptionBatches.count == 1)
        #expect(database.savedSubscriptionBatches.first?.count == 171)
        #expect(savedIDs.count == 171)
        #expect(savedIDs == allManagedIDs.subtracting(build176ManagedIDs))
        #expect(deletedIDs == expectedLegacyCleanupIDs)
        #expect(deletedIDs.isDisjoint(with: build176ManagedIDs))
        #expect(!deletedIDs.contains(DeviceProviderZoneSubscription.subscriptionID))
        #expect(!deletedIDs.contains("unrelated-subscription"))
        #expect(finalIDs.count == 185)
        #expect(finalIDs.intersection(allManagedIDs).count == 183)
        #expect(finalIDs.contains(DeviceProviderZoneSubscription.subscriptionID))
        #expect(finalIDs.contains("unrelated-subscription"))
    }

    @Test
    @MainActor
    func `zone creation failure fails soft and still restores subscriptions`() async {
        let database = InMemoryQuotaTransitionSubscriptionDatabase()
        database.zoneModificationError =
            InMemoryQuotaTransitionSubscriptionDatabase.StubError.zoneModificationFailed

        await QuotaTransitionSubscriptions.shared.setupIfNeeded(using: database)

        let finalManagedIDs = Set(database.subscriptionsByID.keys).intersection(
            QuotaTransitionSubscriptions.managedSubscriptionIDs(
                providerIDs: QuotaProviderList.providers.map(\.id)))
        #expect(database.savedZoneBatches.count == 1)
        #expect(database.savedSubscriptionBatches.count == 1)
        #expect(database.savedSubscriptionBatches.first?.count == 183)
        #expect(finalManagedIDs.count == 183)
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
