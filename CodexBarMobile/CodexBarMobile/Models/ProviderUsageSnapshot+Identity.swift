import CodexBarSync
import Foundation

/// iOS-only identity helpers for `ProviderUsageSnapshot`.
///
/// The Shared layer has always keyed providers by `providerID` alone, but
/// `CloudSyncReader.mergeSnapshots` keys by `providerID|accountEmail` so
/// multi-account providers (Codex, in particular, after upstream 0.20's
/// workspace / system-account refactor) correctly split into distinct
/// cards. iOS render layer needs a matching key to avoid SwiftUI's ForEach
/// collapsing duplicates back into one view instance — this extension
/// exposes it without touching the Shared module (kept iOS-scoped because
/// the Mac target doesn't render cards).
extension ProviderUsageSnapshot {
    /// Account label shown in regular iPhone views. Legacy Enterprise
    /// Copilot records keep a full local UUID in `accountEmail` so separate
    /// Macs cannot merge ambiguous accounts; only this exact generated
    /// suffix is hidden from presentation. Raw sync/debug views retain it.
    var displayAccountLabel: String? {
        guard let accountEmail = self.accountEmail,
              self.providerID == "copilot",
              accountEmail.hasSuffix(")"),
              let marker = accountEmail.range(of: " (local ", options: .backwards),
              marker.lowerBound != accountEmail.startIndex
        else { return self.accountEmail }
        let closingParen = accountEmail.index(before: accountEmail.endIndex)
        let rawUUID = String(accountEmail[marker.upperBound..<closingParen])
        guard let uuid = UUID(uuidString: rawUUID),
              rawUUID == uuid.uuidString.lowercased()
        else { return accountEmail }
        let visibleLabel = String(accountEmail[..<marker.lowerBound])
        guard visibleLabel.contains(" @ api.") else { return accountEmail }
        return visibleLabel
    }

    /// Identity used by SwiftUI `ForEach` and view-scoped accessibility
    /// identifiers. Matches `CloudSyncReader.mergeSnapshots`'s bucket key
    /// so that two `providerID == "codex"` entries with different
    /// `accountEmail`s get distinct view identities. Empty string falls back
    /// when `accountEmail == nil` — consistent with the merger's own
    /// fallback.
    var cardIdentityKey: String {
        "\(self.providerID)|\(self.accountEmail ?? "")"
    }
}
