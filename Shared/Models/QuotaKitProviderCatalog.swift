import Foundation

/// Canonical product-level provider inventory shared by the Mac-to-iPhone
/// payload layer and every iOS presentation surface.
///
/// Provider IDs are persisted in CloudKit records, widget preferences, and
/// historical payloads. Those readers must remain tolerant of other strings,
/// but current QuotaKit clients only surface these four providers.
public enum QuotaKitProviderCatalog {
    public static let providerIDs = ["codex", "claude", "cursor", "grok"]
    public static let providerIDSet = Set(providerIDs)

    public static func contains(_ providerID: String) -> Bool {
        self.providerIDSet.contains(providerID)
    }
}
