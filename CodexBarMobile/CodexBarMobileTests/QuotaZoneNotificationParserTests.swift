import CloudKit
import CodexBarSync
import Foundation
import Testing

@Suite("QuotaZoneNotificationParser Tests")
struct QuotaZoneNotificationParserTests {
    @Test
    func `isQuotaPushZone accepts depleted zone`() {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.quotaDepletedZoneName,
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test
    func `isQuotaPushZone accepts restored zone`() {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.quotaRestoredZoneName,
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test
    func `isQuotaPushZone rejects legacy QuotaTransitionsZone`() {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.quotaTransitionsZoneName,
            ownerName: CKCurrentUserDefaultName)
        #expect(!QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test
    func `isQuotaPushZone rejects unrelated zone`() {
        let zoneID = CKRecordZone.ID(
            zoneName: "DeviceSnapshotsZone", ownerName: CKCurrentUserDefaultName)
        #expect(!QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test
    func `isQuotaPushZone rejects arbitrary zone name`() {
        let zoneID = CKRecordZone.ID(
            zoneName: "FooBarZone", ownerName: CKCurrentUserDefaultName)
        #expect(!QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test
    func `extractQuotaZoneID returns nil for empty userInfo`() {
        #expect(QuotaZoneNotificationParser.extractQuotaZoneID(from: [:]) == nil)
    }

    @Test
    func `extractQuotaZoneID returns nil for non-CK userInfo`() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": "Test"],
            "custom": "value",
        ]
        #expect(QuotaZoneNotificationParser.extractQuotaZoneID(from: userInfo) == nil)
    }

    // MARK: - Per-provider zone recognition (Build 54+)

    @Test
    func `isQuotaPushZone accepts per-provider depleted zone`() {
        let zoneID = CKRecordZone.ID(
            zoneName: "Quota-codex-depletedZone",
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test
    func `isQuotaPushZone accepts per-provider restored zone`() {
        let zoneID = CKRecordZone.ID(
            zoneName: "Quota-claude-restoredZone",
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test
    func `isQuotaPushZone accepts per-provider warning zone (iOS 1.6.0)`() {
        let zoneID = CKRecordZone.ID(
            zoneName: "Quota-perplexity-warningZone",
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test
    func `parseQuotaZoneName extracts (providerID, state) for warning`() {
        let parsed = QuotaZoneNotificationParser.parseQuotaZoneName(
            "Quota-codex-warningZone")
        #expect(parsed?.providerID == "codex")
        #expect(parsed?.state == .warning)
    }

    @Test
    func `parseQuotaZoneName extracts (providerID, state) for depleted`() {
        let parsed = QuotaZoneNotificationParser.parseQuotaZoneName(
            "Quota-claude-depletedZone")
        #expect(parsed?.providerID == "claude")
        #expect(parsed?.state == .depleted)
    }

    @Test
    func `parseQuotaZoneName rejects malformed names`() {
        #expect(QuotaZoneNotificationParser.parseQuotaZoneName("NotAQuotaZone") == nil)
        #expect(QuotaZoneNotificationParser.parseQuotaZoneName("Quota-no-state-Zone") == nil)
        #expect(QuotaZoneNotificationParser.parseQuotaZoneName("") == nil)
    }

    @Test
    func `parseQuotaZoneName rejects legacy global zone names`() {
        // The legacy QuotaDepletedZone / QuotaRestoredZone names are
        // matched by `isQuotaPushZone` via the constants, NOT by
        // `parseQuotaZoneName` which only handles per-provider format.
        // Pinning this so the NSE branch on `parsed?.state == .warning`
        // doesn't accidentally fire for legacy depleted zones.
        #expect(QuotaZoneNotificationParser.parseQuotaZoneName(
            "QuotaDepletedZone") == nil)
        #expect(QuotaZoneNotificationParser.parseQuotaZoneName(
            "QuotaRestoredZone") == nil)
    }

    // MARK: - Warning recordName parsing

    @Test
    func `parseWarningRecordName extracts window + threshold`() {
        let parsed = QuotaZoneNotificationParser.parseWarningRecordName(
            "codex-session-t50-477312")
        #expect(parsed?.providerID == "codex")
        #expect(parsed?.window == "session")
        #expect(parsed?.threshold == 50)
    }

    @Test
    func `parseWarningRecordName handles weekly window`() {
        let parsed = QuotaZoneNotificationParser.parseWarningRecordName(
            "claude-weekly-t20-477500")
        #expect(parsed?.providerID == "claude")
        #expect(parsed?.window == "weekly")
        #expect(parsed?.threshold == 20)
    }

    @Test
    func `parseWarningRecordName rejects malformed names`() {
        #expect(QuotaZoneNotificationParser.parseWarningRecordName(
            "codex-session-477312") == nil) // missing threshold
        #expect(QuotaZoneNotificationParser.parseWarningRecordName(
            "codex-session-tABC-477312") == nil) // non-numeric threshold
        #expect(QuotaZoneNotificationParser.parseWarningRecordName("") == nil)
    }
}
