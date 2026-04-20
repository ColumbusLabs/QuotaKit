import CloudKit
import CodexBarSync
import Foundation

/// P7 — silent-push subscription for the per-provider zone.
///
/// A single `CKRecordZoneSubscription` on `DeviceProvidersZone` with
/// `shouldSendContentAvailable = true` tells CloudKit to wake the iOS app
/// silently every time a Mac writes or deletes a `DeviceProviderSnapshot`
/// record. The app responds by running `fetchAllDeviceSnapshotsIncremental`,
/// applying the change-token delta to SwiftData, and letting views refresh.
///
/// Separate from `QuotaTransitionSubscriptions` because those carry
/// user-visible `alertBody`; this one is strictly silent and shouldn't
/// surface any notification UI.
///
/// Idempotency mirrors the quota setup: diff server state, only save when
/// drifted.
@MainActor
final class DeviceProviderZoneSubscription {
    static let shared = DeviceProviderZoneSubscription()

    /// Subscription ID for the DeviceProvidersZone silent push. Stable across
    /// app launches so repeated setup overwrites rather than duplicates.
    nonisolated static let subscriptionID = "device-provider-zone-sub"

    private let containerIdentifier = CloudSyncConstants.containerIdentifier
    private let zoneName = CloudSyncConstants.providerZoneName
    private let recordType = CloudSyncConstants.providerRecordType

    private init() {}

    /// Creates or overwrites the silent-push subscription on
    /// `DeviceProvidersZone`. Safe to call on every launch and every
    /// `CKAccountChangedNotification`.
    func setupIfNeeded() async {
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase

        // Ensure the zone exists. If no Mac has written here yet the zone
        // may still be absent; pre-create so the subscription save doesn't
        // fail with .zoneNotFound.
        do {
            _ = try await database.recordZone(for: CKRecordZone.ID(
                zoneName: zoneName, ownerName: CKCurrentUserDefaultName))
        } catch let error as CKError where error.code == .zoneNotFound {
            let zone = CKRecordZone(zoneName: zoneName)
            _ = try? await database.modifyRecordZones(saving: [zone], deleting: [])
        } catch {
            // Non-fatal — subscription save below will surface the error.
            print("[CodexBar P7] recordZone lookup failed: \(error.localizedDescription)")
        }

        // Diff server state: only save if missing or drifted.
        let existing: [CKSubscription]
        do {
            existing = try await database.allSubscriptions()
        } catch {
            print("[CodexBar P7] allSubscriptions failed: \(error.localizedDescription)")
            return
        }

        let zoneID = CKRecordZone.ID(
            zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        if let zoneSub = existing.first(where: {
            $0.subscriptionID == Self.subscriptionID
        }) as? CKRecordZoneSubscription,
           zoneSub.zoneID == zoneID,
           zoneSub.notificationInfo?.shouldSendContentAvailable == true
        {
            print("[CodexBar P7] device-provider subscription already correct")
            return
        }

        let sub = CKRecordZoneSubscription(
            zoneID: zoneID, subscriptionID: Self.subscriptionID)
        // recordType filter is optional on a zone sub; leaving it nil means
        // any record-type change in the zone triggers the push. That's
        // exactly what we want since the zone only ever contains
        // DeviceProviderSnapshot.
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true // silent push — wakes app, no UI
        sub.notificationInfo = info

        do {
            _ = try await database.modifySubscriptions(saving: [sub], deleting: [])
            print("[CodexBar P7] device-provider silent subscription saved")
        } catch {
            print("[CodexBar P7] subscription save failed: \(error.localizedDescription)")
        }
    }

    /// Returns `true` if the given remote-notification userInfo originated
    /// from the device-provider zone subscription. Used by the AppDelegate
    /// to route pushes to the incremental-sync path. Pure function — no
    /// actor isolation required.
    nonisolated static func isPushForThisSubscription(userInfo: [AnyHashable: Any]) -> Bool {
        // CloudKit nests the metadata under the "ck" key; subscription ID
        // lives under "sid" in the "qry"/"fet" sub-dictionaries depending
        // on sub type. Robust cross-check: look for our subscriptionID
        // anywhere in the userInfo.
        guard let ck = userInfo["ck"] as? [AnyHashable: Any] else { return false }
        if let sid = ck["sid"] as? String, sid == subscriptionID { return true }
        for value in ck.values {
            if let dict = value as? [AnyHashable: Any],
               let sid = dict["sid"] as? String, sid == subscriptionID
            {
                return true
            }
        }
        return false
    }
}
