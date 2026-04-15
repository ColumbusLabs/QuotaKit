import CloudKit
import CodexBarSync
import Foundation
import Testing

@Suite("QuotaZoneNotificationParser Tests")
struct QuotaZoneNotificationParserTests {

    @Test("isQuotaPushZone accepts depleted zone")
    func acceptsDepletedZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.quotaDepletedZoneName,
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("isQuotaPushZone accepts restored zone")
    func acceptsRestoredZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.quotaRestoredZoneName,
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("isQuotaPushZone rejects legacy QuotaTransitionsZone")
    func rejectsLegacyZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.quotaTransitionsZoneName,
            ownerName: CKCurrentUserDefaultName)
        #expect(!QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("isQuotaPushZone rejects unrelated zone")
    func rejectsUnrelatedZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: "DeviceSnapshotsZone", ownerName: CKCurrentUserDefaultName)
        #expect(!QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("isQuotaPushZone rejects arbitrary zone name")
    func rejectsArbitraryZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: "FooBarZone", ownerName: CKCurrentUserDefaultName)
        #expect(!QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("extractQuotaZoneID returns nil for empty userInfo")
    func emptyUserInfoReturnsNil() {
        #expect(QuotaZoneNotificationParser.extractQuotaZoneID(from: [:]) == nil)
    }

    @Test("extractQuotaZoneID returns nil for non-CK userInfo")
    func nonCloudKitUserInfoReturnsNil() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": "Test"],
            "custom": "value",
        ]
        #expect(QuotaZoneNotificationParser.extractQuotaZoneID(from: userInfo) == nil)
    }
}
