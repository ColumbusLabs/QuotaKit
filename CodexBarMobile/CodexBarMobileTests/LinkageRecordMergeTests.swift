import CloudKit
import CodexBarSync
import Foundation
import Testing

@testable import CodexBarMobile

/// Pins the Research/019 §7 (L3 user-confirmed LinkageRecord) + §7.4
/// (Unmerge) semantics in the iOS union-find merge.
///
/// Pairs with `AccountIdentityMergeTests` which covers §8.1–§8.10
/// (L1+L2 identifier-based merge). The L3 layer activates only when
/// L1+L2 leave at least two groups for what the user knows is one
/// account.
@Suite("LinkageRecord (§7 L3 user-confirmed merge)")
struct LinkageRecordMergeTests {

    // MARK: - §8.11 linkageRecordOverride

    @Test("§8.11 — User-confirmed LinkageRecord unions disjoint groups")
    func linkageOverrideUnionsGroups() throws {
        // Mac A writes only email:U; Mac B writes only sub:S. Without a
        // shared identifier, L1+L2 produces 2 groups. A LinkageRecord
        // listing both anchor IDs unions them into 1.
        let mA = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(id: "codex", email: "u@x.com",
                              identifiers: ["codex:email:u@x.com"]),
        ])
        let mB = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(id: "codex", email: nil,
                              identifiers: ["codex:sub:abc123"]),
        ])

        // Without linkage: 2 groups (pre-condition).
        let before = try #require(CloudSyncReader.mergeSnapshots([mA, mB]))
        #expect(before.providers.count == 2,
                "Pre-condition: disjoint identifiers → 2 cards.")

        // With linkage: 1 group.
        let linkage = ProviderAccountLinkage(
            providerID: "codex",
            linkedIdentifiers: ["codex:email:u@x.com", "codex:sub:abc123"],
            confirmedFromDeviceID: "iPhone-A",
            unmerge: false)
        let after = try #require(
            CloudSyncReader.mergeSnapshots([mA, mB], linkages: [linkage]))
        #expect(after.providers.count == 1,
                "LinkageRecord unions disjoint groups via shared providerID + listed identifiers.")
    }

    // MARK: - §7.4 Unmerge

    @Test("§7.4 — Inverse `unmerge=true` record nullifies the merge")
    func unmergeNullifiesMerge() throws {
        let mA = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(id: "codex", email: "u@x.com",
                              identifiers: ["codex:email:u@x.com"]),
        ])
        let mB = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(id: "codex", email: nil, identifiers: nil),
        ])

        let merge = ProviderAccountLinkage(
            recordID: "merge-1",
            providerID: "codex",
            linkedIdentifiers: ["codex:email:u@x.com", "codex:legacy-no-identity"],
            confirmedFromDeviceID: "iPhone-A",
            unmerge: false)
        let unmerge = merge.inverseUnmerge(confirmedFromDeviceID: "iPhone-A")

        // Merge alone → 1 group.
        let merged = try #require(
            CloudSyncReader.mergeSnapshots([mA, mB], linkages: [merge]))
        #expect(merged.providers.count == 1)

        // Merge + unmerge → back to 2 groups.
        let after = try #require(
            CloudSyncReader.mergeSnapshots([mA, mB], linkages: [merge, unmerge]))
        #expect(after.providers.count == 2,
                "Inverse `unmerge=true` linkage with matching identifier set cancels the merge.")
    }

    @Test("§7.4 — Unmerge order doesn't matter (inverse applies after all merges)")
    func unmergeOrderIndependent() throws {
        let mA = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(id: "codex", email: "u@x.com",
                              identifiers: ["codex:email:u@x.com"]),
        ])
        let mB = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(id: "codex", email: nil, identifiers: nil),
        ])

        let merge = ProviderAccountLinkage(
            providerID: "codex",
            linkedIdentifiers: ["codex:email:u@x.com", "codex:legacy-no-identity"],
            confirmedFromDeviceID: "iPhone-A",
            unmerge: false)
        let unmerge = ProviderAccountLinkage(
            providerID: "codex",
            // Same identifier set, different order — set-equality should hold.
            linkedIdentifiers: ["codex:legacy-no-identity", "codex:email:u@x.com"],
            confirmedFromDeviceID: "iPhone-A",
            unmerge: true)

        // Both orderings of (merge, unmerge) should produce the same outcome.
        let forward = try #require(
            CloudSyncReader.mergeSnapshots([mA, mB], linkages: [merge, unmerge]))
        let backward = try #require(
            CloudSyncReader.mergeSnapshots([mA, mB], linkages: [unmerge, merge]))

        #expect(forward.providers.count == backward.providers.count)
        #expect(forward.providers.count == 2,
                "Set-equality canonical key matches reversed identifier lists; unmerge cancels regardless of order.")
    }

    // MARK: - Concurrency (§11.5 row M)

    @Test("Two concurrent merge LinkageRecords from different iPhones are idempotent")
    func concurrentMergesIdempotent() throws {
        let mA = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(id: "codex", email: "u@x.com",
                              identifiers: ["codex:email:u@x.com"]),
        ])
        let mB = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(id: "codex", email: nil, identifiers: nil),
        ])

        // Two iPhones write near-simultaneously. Each writes its own
        // record with a unique recordID. Both linked the same identifiers.
        let phone1 = ProviderAccountLinkage(
            recordID: "from-iphone-1",
            providerID: "codex",
            linkedIdentifiers: ["codex:email:u@x.com", "codex:legacy-no-identity"],
            confirmedFromDeviceID: "iPhone-1",
            unmerge: false)
        let phone2 = ProviderAccountLinkage(
            recordID: "from-iphone-2",
            providerID: "codex",
            linkedIdentifiers: ["codex:email:u@x.com", "codex:legacy-no-identity"],
            confirmedFromDeviceID: "iPhone-2",
            unmerge: false)

        let merged = try #require(
            CloudSyncReader.mergeSnapshots([mA, mB], linkages: [phone1, phone2]))
        #expect(merged.providers.count == 1,
                "Duplicate merge edges in union-find are no-ops — both records produce 1 group.")
    }

    // MARK: - No-op cases

    @Test("Linkage with non-matching providerID is no-op")
    func linkageWrongProviderID() throws {
        let mA = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(id: "codex", email: "u@x.com",
                              identifiers: ["codex:email:u@x.com"]),
        ])
        let mB = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(id: "codex", email: nil, identifiers: nil),
        ])

        let linkage = ProviderAccountLinkage(
            providerID: "claude",  // wrong provider
            linkedIdentifiers: ["codex:email:u@x.com", "codex:legacy-no-identity"],
            confirmedFromDeviceID: "iPhone-A")
        let merged = try #require(
            CloudSyncReader.mergeSnapshots([mA, mB], linkages: [linkage]))
        #expect(merged.providers.count == 2,
                "Linkage for `claude` cannot touch codex snapshots.")
    }

    @Test("Linkage with no overlapping identifier is no-op")
    func linkageNoOverlap() throws {
        let mA = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(id: "codex", email: "u@x.com",
                              identifiers: ["codex:email:u@x.com"]),
        ])
        let mB = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(id: "codex", email: "v@x.com",
                              identifiers: ["codex:email:v@x.com"]),
        ])

        let linkage = ProviderAccountLinkage(
            providerID: "codex",
            // None of these match either snapshot's effective identifiers.
            linkedIdentifiers: ["codex:email:nobody@nowhere", "codex:sub:zzz"],
            confirmedFromDeviceID: "iPhone-A")
        let merged = try #require(
            CloudSyncReader.mergeSnapshots([mA, mB], linkages: [linkage]))
        #expect(merged.providers.count == 2,
                "Linkage that doesn't match any actual identifier is a no-op.")
    }

    // MARK: - Codable round-trip

    @Test("ProviderAccountLinkage round-trips through JSON")
    func linkageCodableRoundTrip() throws {
        let linkage = ProviderAccountLinkage(
            recordID: "abc-123",
            providerID: "codex",
            linkedIdentifiers: ["codex:email:a@x.com", "codex:legacy-no-identity"],
            confirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
            confirmedFromDeviceID: "iPhone-A",
            unmerge: false)

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let decoder = CloudSyncConstants.makeJSONDecoder()
        let data = try encoder.encode(linkage)
        let decoded = try decoder.decode(ProviderAccountLinkage.self, from: data)
        #expect(decoded == linkage)
    }

    @Test("Missing `unmerge` field in decoded JSON defaults to merge (false)")
    func linkageDecodeUnmergeBackwardCompat() throws {
        let payload: [String: Any] = [
            "recordID": "abc-123",
            "providerID": "codex",
            "linkedIdentifiers": ["codex:email:a@x.com"],
            "confirmedAt": "2025-11-14T22:13:20Z",
            "confirmedFromDeviceID": "iPhone-A",
            // no `unmerge` field
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(ProviderAccountLinkage.self, from: data)
        #expect(decoded.unmerge == false,
                "Decoder treats missing unmerge field as merge (additive).")
    }

    // MARK: - Inverse helper

    @Test("inverseUnmerge produces an unmerge record with same linked ids")
    func inverseUnmergeHelper() {
        let original = ProviderAccountLinkage(
            providerID: "codex",
            linkedIdentifiers: ["codex:email:a@x.com", "codex:legacy-no-identity"],
            confirmedFromDeviceID: "iPhone-A",
            unmerge: false)
        let inverse = original.inverseUnmerge(confirmedFromDeviceID: "iPhone-B")
        #expect(inverse.unmerge == true)
        #expect(inverse.providerID == original.providerID)
        #expect(inverse.linkedIdentifiers == original.linkedIdentifiers)
        #expect(inverse.confirmedFromDeviceID == "iPhone-B")
        #expect(inverse.recordID != original.recordID,
                "Inverse has its own UUID so both records survive in CloudKit.")
    }

    // MARK: - CKRecord encoding (regression for build 115 ObjC-exception crash)

    @Test("CKRecord encode→decode round-trips without the reserved `recordID` field")
    func ckRecordRoundTripNoReservedKeyCollision() {
        // Build 115 set `record["recordID"] = ...` which collides with the
        // built-in CKRecord.recordID property and raises an ObjC
        // NSException via `-[CKRecordValueStore setObject:forKey:]` — fatal
        // because Swift can't catch ObjC exceptions. Build 116 instead
        // encodes the linkage UUID into the CKRecord's name (the
        // `"linkage-{UUID}"` recordName prefix) and never sets a field
        // by that reserved name.
        let original = ProviderAccountLinkage(
            recordID: "F84A2B7C-AAAA-BBBB-CCCC-DDDDDDDDDDDD",
            providerID: "codex",
            linkedIdentifiers: ["codex:email:a@x.com", "codex:legacy-no-identity"],
            confirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
            confirmedFromDeviceID: "iPhone-A",
            unmerge: false)

        // Mirror the production save path's CKRecord construction.
        // Constructed without a server (no CloudKit auth needed for
        // in-memory CKRecord).
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.providerZoneName,
            ownerName: CKCurrentUserDefaultName)
        let ckRecordID = CKRecord.ID(
            recordName: ProviderAccountLinkage.recordName(for: original.recordID),
            zoneID: zoneID)
        let record = CKRecord(
            recordType: CloudSyncConstants.providerAccountLinkageRecordType,
            recordID: ckRecordID)
        // Populate ONLY the fields the production code sets. `recordID`
        // intentionally absent — derived from `record.recordID.recordName`.
        record["providerID"] = original.providerID as CKRecordValue
        record["linkedIdentifiers"] = original.linkedIdentifiers as CKRecordValue
        record["confirmedAt"] = original.confirmedAt as CKRecordValue
        record["confirmedFromDeviceID"] = original.confirmedFromDeviceID as CKRecordValue
        record["unmerge"] = (original.unmerge ? 1 : 0) as CKRecordValue

        let decoded = try? #require(CloudSyncManager.decodeLinkage(from: record))
        #expect(decoded?.recordID == original.recordID,
                "Linkage UUID survived round-trip via the `linkage-{UUID}` recordName.")
        #expect(decoded?.providerID == original.providerID)
        #expect(decoded?.linkedIdentifiers == original.linkedIdentifiers)
        #expect(decoded?.confirmedFromDeviceID == original.confirmedFromDeviceID)
        #expect(decoded?.unmerge == original.unmerge)
    }

    @Test("Records lacking the `linkage-` prefix decode as nil (not our records)")
    func ckRecordWrongNamePrefixRejected() {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.providerZoneName,
            ownerName: CKCurrentUserDefaultName)
        let ckRecordID = CKRecord.ID(
            recordName: "something-else-format",
            zoneID: zoneID)
        let record = CKRecord(
            recordType: CloudSyncConstants.providerAccountLinkageRecordType,
            recordID: ckRecordID)
        record["providerID"] = "codex" as CKRecordValue
        record["linkedIdentifiers"] = ["a"] as CKRecordValue
        record["confirmedAt"] = Date() as CKRecordValue
        record["confirmedFromDeviceID"] = "iPhone-A" as CKRecordValue
        record["unmerge"] = 0 as CKRecordValue

        let decoded = CloudSyncManager.decodeLinkage(from: record)
        #expect(decoded == nil,
                "Defensive: records that hit our query but don't follow the linkage-{UUID} naming aren't ours.")
    }

    // MARK: - Cold-start cache

    @Test("Cached linkages round-trip through UserDefaults")
    func cachedLinkageRoundTrip() {
        let cacheKey = "com.codexbar.linkageCache.v1"
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: cacheKey) }

        // Pinned timestamp avoids sub-second precision loss in the
        // ISO8601 JSON round-trip — `Date()` keeps nanoseconds that
        // `.iso8601` encoder/decoder normalize to seconds.
        let original = ProviderAccountLinkage(
            recordID: "test-linkage-1",
            providerID: "codex",
            linkedIdentifiers: ["codex:email:a@x.com", "codex:legacy-no-identity"],
            confirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
            confirmedFromDeviceID: "iPhone-A",
            unmerge: false)
        SyncedUsageData.saveCachedLinkages([original])

        let loaded = SyncedUsageData.loadCachedLinkages()
        #expect(loaded.count == 1)
        #expect(loaded.first == original)
    }

    @Test("Empty cache loads as empty array")
    func emptyLinkageCache() {
        let cacheKey = "com.codexbar.linkageCache.v1"
        UserDefaults.standard.removeObject(forKey: cacheKey)
        let loaded = SyncedUsageData.loadCachedLinkages()
        #expect(loaded.isEmpty)
    }

    // MARK: - Helpers

    private static func makeProvider(
        id: String,
        email: String?,
        identifiers: [String]?) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: id.capitalized,
            primary: SyncRateWindow(
                usedPercent: 25.0,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            accountIdentities: identifiers)
    }

    private static func makeMac(
        deviceID: String,
        providers: [ProviderUsageSnapshot]) -> SyncedUsageSnapshot
    {
        SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Mac \(deviceID)",
            deviceID: deviceID,
            appVersion: "0.23",
            mobileVersion: "1.5.0")
    }
}
