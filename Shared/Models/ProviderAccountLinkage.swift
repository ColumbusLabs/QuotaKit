import Foundation

/// User-confirmed bridge between provider snapshots whose union-find
/// identifiers don't naturally overlap.
///
/// See `Research/019-account-identity-multi-version-merge.md` §7 + §7.4 for the
/// architecture. Quick summary:
///
/// - L1 (Mac writes `accountIdentities`) + L2 (iOS union-find over identifiers)
///   handle ~99% of cross-Mac, cross-version sync cases automatically.
/// - L3 (this record) handles the residual case: an old Mac that doesn't yet
///   emit `accountIdentities` for a provider sits in the legacy bucket while a
///   newer Mac for the same logical account sits in a named bucket. With no
///   shared identifier, iOS can't safely auto-merge — it asks the user once,
///   writes this record, and applies the merge on every subsequent read.
///
/// **Wire-format invariants** (CKRecord field names):
/// - `recordID: String` (UUIDv4) — primary key, also used as the CKRecord name
///   prefixed with `"linkage-"`.
/// - `providerID: String` — narrows the merge scope; identifiers from
///   different providers never cross-merge even if a `linkedIdentifiers` list
///   accidentally contained a foreign string.
/// - `linkedIdentifiers: [String]` — the `effectiveIdentifiers` (composite
///   keys or `cardIdentityKey`-style strings) iOS uses to add a virtual edge
///   in the union-find graph.
/// - `confirmedAt: Date` — when the user confirmed. Used for audit and to pick
///   the latest record when concurrent iPhones write.
/// - `confirmedFromDeviceID: String` — which iPhone confirmed. Pure metadata
///   for the diagnostics view; never affects merge semantics.
/// - `unmerge: Bool` — `false` for merge (the default), `true` for an
///   user-issued unmerge (additive inverse). See §7.4.
///
/// **Idempotence.** Two iPhones can confirm the same merge concurrently. Each
/// writes its own `LinkageRecord` with a fresh `recordID`. iOS reads ALL
/// linkage records for the provider and unions them — duplicate edges in the
/// union-find graph are harmless. Concurrent unmerges follow the same rule.
public struct ProviderAccountLinkage: Codable, Sendable, Equatable, Identifiable {
    public let recordID: String
    public let providerID: String
    public let linkedIdentifiers: [String]
    public let confirmedAt: Date
    public let confirmedFromDeviceID: String
    /// `false` (or missing in legacy decode) = additive merge edge.
    /// `true` = inverse "unmerge" record that nullifies an earlier merge for
    /// the same `linkedIdentifiers` set. Applied after all merge edges so the
    /// unmerge is order-independent.
    public let unmerge: Bool

    public var id: String { self.recordID }

    public init(
        recordID: String = UUID().uuidString,
        providerID: String,
        linkedIdentifiers: [String],
        confirmedAt: Date = Date(),
        confirmedFromDeviceID: String,
        unmerge: Bool = false)
    {
        self.recordID = recordID
        self.providerID = providerID
        self.linkedIdentifiers = linkedIdentifiers
        self.confirmedAt = confirmedAt
        self.confirmedFromDeviceID = confirmedFromDeviceID
        self.unmerge = unmerge
    }

    /// Backward-compat decoder: an iOS build that ships without the
    /// `unmerge` field (none in the wild yet, but the policy is to plan
    /// for it) decodes any future record as a plain merge edge.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.recordID = try container.decode(String.self, forKey: .recordID)
        self.providerID = try container.decode(String.self, forKey: .providerID)
        self.linkedIdentifiers = try container.decode([String].self, forKey: .linkedIdentifiers)
        self.confirmedAt = try container.decode(Date.self, forKey: .confirmedAt)
        self.confirmedFromDeviceID = try container.decode(String.self, forKey: .confirmedFromDeviceID)
        self.unmerge = try container.decodeIfPresent(Bool.self, forKey: .unmerge) ?? false
    }

    /// CKRecord name format. `"linkage-"` prefix keeps these records visually
    /// distinct from `DeviceProviderSnapshot` records in CloudKit Dashboard
    /// and lets the existing `SnapshotCache.splitRecordName` parser skip
    /// linkage records cleanly.
    public static func recordName(for recordID: String) -> String {
        "linkage-\(recordID)"
    }

    /// Inverse linkage record for unmerge. Carries the SAME
    /// `linkedIdentifiers` as the original; `unmerge=true` flag flips its
    /// effect when iOS applies the graph reduction.
    public func inverseUnmerge(confirmedFromDeviceID: String) -> ProviderAccountLinkage {
        ProviderAccountLinkage(
            providerID: self.providerID,
            linkedIdentifiers: self.linkedIdentifiers,
            confirmedFromDeviceID: confirmedFromDeviceID,
            unmerge: true)
    }
}
