import CloudKit
import CodexBarSync
import Foundation

/// Sets up a `CKRecordZoneSubscription` on the `QuotaTransitionsZone` to receive
/// visible alert push notifications when Mac writes a `QuotaTransition` record.
///
/// **Why CKRecordZoneSubscription, not CKQuerySubscription:**
/// A/B testing confirmed that CKQuerySubscription saves without error but never
/// persists on this CloudKit container (allSubscriptions returns empty immediately
/// after a successful save). CKRecordZoneSubscription DOES persist — the old
/// `device-snapshot-changes` subscription proves this.
///
/// **Why a dedicated zone:**
/// CKRecordZoneSubscription fires on all record changes in the zone. Using the
/// same zone as DeviceSnapshot (which updates every ~60s) would spam the user.
/// A dedicated `QuotaTransitionsZone` + `recordType = "QuotaTransition"` ensures
/// pushes only fire for quota change events.
///
/// **How notification text works:**
/// Mac writes `notificationTitle` and `notificationBody` fields into each record.
/// The subscription's `titleLocalizationArgs` and `alertLocalizationArgs` reference
/// these field names. CloudKit reads the values at push time and populates the
/// notification — Mac decides the text, iOS just displays it.
@MainActor
final class QuotaTransitionSubscriptions {
    static let shared = QuotaTransitionSubscriptions()

    private let containerIdentifier = CloudSyncConstants.containerIdentifier
    private let zoneName = CloudSyncConstants.quotaTransitionsZoneName
    private let recordType = CloudSyncConstants.quotaTransitionRecordType
    private let subscriptionID = "quota-transition-zone-sub"

    private init() {}

    /// Configures the subscription if needed. Idempotent and safe to call on every
    /// launch and on every `CKAccountChangedNotification`.
    func setupIfNeeded() async {
        let diag = await PushSetupDiagnostic.shared
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(
            zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

        // Step 1: ensure QuotaTransitionsZone exists
        do {
            try await self.ensureZoneExists(database: database, zoneID: zoneID)
            await diag.recordZone("✓ \(zoneName) exists")
        } catch {
            let msg = "ensureZoneExists failed: \(error.localizedDescription)"
            print("[CodexBar Push v4] \(msg)")
            await diag.recordZone("✗ \(msg)")
            await diag.recordError(msg)
            return
        }

        // Step 2: configure the CKRecordZoneSubscription
        do {
            let created = try await self.configureSubscription(
                database: database, zoneID: zoneID)
            let msg = created ? "✓ created" : "✓ already correct"
            print("[CodexBar Push v4] Subscription \(msg)")
            await diag.recordDepletedSub(msg)
            await diag.recordRestoredSub(msg)
        } catch {
            let msg = "✗ subscription setup failed: \(error.localizedDescription)"
            print("[CodexBar Push v4] \(msg)")
            await diag.recordDepletedSub(msg)
            await diag.recordRestoredSub(msg)
            await diag.recordError(msg)
        }

        // Step 3: refresh subscription list from iOS perspective
        await diag.refreshSubscriptionList()
    }

    /// Runs a persistence test: create a temporary CKRecordZoneSubscription, check
    /// if allSubscriptions returns it, then delete. Returns a human-readable result.
    func runPersistenceTest() async -> String {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let testID = "ios-persistence-test"
        let zoneID = CKRecordZone.ID(
            zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

        do {
            try await self.ensureZoneExists(database: database, zoneID: zoneID)
        } catch {
            return "✗ zone creation failed: \(error.localizedDescription)"
        }

        // Create — always clean up on exit regardless of success/failure
        defer {
            Task { try? await database.deleteSubscription(withID: testID) }
        }

        do {
            try? await database.deleteSubscription(withID: testID)
            let sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: testID)
            sub.recordType = recordType
            let info = CKSubscription.NotificationInfo()
            info.alertBody = "Persistence test"
            info.soundName = "default"
            sub.notificationInfo = info
            _ = try await database.modifySubscriptions(saving: [sub], deleting: [])
        } catch {
            return "✗ save failed: \(error.localizedDescription)"
        }

        // Verify
        let persisted: Bool
        do {
            let all = try await database.allSubscriptions()
            persisted = all.contains(where: { $0.subscriptionID == testID })
        } catch {
            return "✗ allSubscriptions failed: \(error.localizedDescription)"
        }

        return persisted
            ? "✓ CKRecordZoneSubscription persists from iOS!"
            : "✗ NOT FOUND after save — same issue as CKQuerySubscription"
    }

    // MARK: - Internals

    private func ensureZoneExists(
        database: CKDatabase, zoneID: CKRecordZone.ID) async throws
    {
        do {
            _ = try await database.recordZone(for: zoneID)
            return
        } catch let error as CKError where error.code == .zoneNotFound {
            // Fall through to create
        }
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
        print("[CodexBar Push v4] Created zone: \(zoneID.zoneName)")
    }

    /// Creates or repairs the subscription. Returns true if created, false if
    /// already correct (no-op).
    private func configureSubscription(
        database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> Bool
    {
        // Fetch existing
        let existing: CKSubscription?
        do {
            existing = try await database.subscription(for: subscriptionID)
        } catch let error as CKError where error.code == .unknownItem {
            existing = nil
        }
        // Other errors propagate (don't destructively modify on transient failures)

        // Check if already correct
        if let zoneSub = existing as? CKRecordZoneSubscription,
           zoneSub.zoneID == zoneID,
           zoneSub.recordType == recordType,
           zoneSub.notificationInfo?.alertBody != nil
        {
            return false // already correct
        }

        // Delete stale subscription if exists
        if existing != nil {
            try? await database.deleteSubscription(withID: subscriptionID)
        }

        // Create new CKRecordZoneSubscription
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID, subscriptionID: subscriptionID)
        subscription.recordType = recordType

        let info = CKSubscription.NotificationInfo()
        info.alertBody = "Session quota changed"  // static fallback
        info.titleLocalizationKey = "%@"
        info.titleLocalizationArgs = ["notificationTitle"]
        info.alertLocalizationKey = "%@"
        info.alertLocalizationArgs = ["notificationBody"]
        info.soundName = "default"
        info.shouldBadge = true
        subscription.notificationInfo = info

        _ = try await database.modifySubscriptions(
            saving: [subscription], deleting: [])
        return true
    }
}
