import CloudKit
import Foundation

/// Parses CloudKit remote-notification payloads to identify whether they
/// correspond to one of our quota push zones. Used by the iOS
/// `UNNotificationServiceExtension` to decide whether to enrich the push with
/// provider data — and unit-testable independent of the extension target.
public enum QuotaZoneNotificationParser {

    /// Returns `true` if the given zone is one of the quota push zones whose
    /// notifications we want the service extension to enrich.
    ///
    /// Built as a small predicate so the extension's payload-parsing path and
    /// our unit tests can both validate against it without having to construct
    /// a full `CKNotification` from a synthetic dict.
    public static func isQuotaPushZone(_ zoneID: CKRecordZone.ID) -> Bool {
        return zoneID.zoneName == CloudSyncConstants.quotaDepletedZoneName
            || zoneID.zoneName == CloudSyncConstants.quotaRestoredZoneName
    }

    /// Extracts the quota zone ID from a CloudKit remote-notification user-info
    /// dictionary. Returns `nil` if the payload isn't a `CKRecordZoneNotification`
    /// or the zone isn't one of our quota push zones (defensive against future
    /// zone additions, the legacy `QuotaTransitionsZone`, and non-CloudKit pushes).
    public static func extractQuotaZoneID(
        from userInfo: [AnyHashable: Any]) -> CKRecordZone.ID?
    {
        guard
            let notif = CKNotification(fromRemoteNotificationDictionary: userInfo),
            let zoneNotif = notif as? CKRecordZoneNotification,
            let zoneID = zoneNotif.recordZoneID,
            self.isQuotaPushZone(zoneID)
        else { return nil }
        return zoneID
    }
}
