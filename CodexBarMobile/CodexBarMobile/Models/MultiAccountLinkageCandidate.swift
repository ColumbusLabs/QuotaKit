import CodexBarSync
import Foundation

/// A "linkage candidate" describes a `ProviderUsageSnapshot` that probably
/// represents the same logical account as another snapshot on the user's
/// iCloud, but whose identifiers don't overlap so the union-find merge in
/// `CloudSyncReader.mergeSnapshots` left them in separate groups.
///
/// **When this fires.** Specifically:
/// 1. The user has ≥ 2 providers (post-merge) with the **same `providerID`**.
/// 2. At least one of those providers has `accountIdentities` (Tier-A,
///    upstream-extracted identifier) AND at least one ends up in the
///    legacy bucket (no `accountIdentities`, no `accountEmail`).
///
/// Pattern A: old Mac on a CodexBar version that didn't yet emit
/// `accountIdentities` for this provider + new Mac that does. Same login
/// underneath but iOS can't prove it, so it splits the card. The user
/// has to confirm via the inline button (Research/019 §7).
///
/// **When this does NOT fire** (genuine multi-account scenarios that
/// should keep splitting):
/// - Both providers ARE named (different emails) — that's actually two
///   accounts; iOS shouldn't bridge.
/// - Multiple named providers AND multiple legacy entries — too much
///   ambiguity; we'd guess wrong. Caller falls back to "no merge offered".
///
/// Returned candidates are paired (named, legacy) for inline UI presentation.
struct MultiAccountLinkageCandidate: Equatable {
    /// The named card (has accountIdentities or accountEmail). The merge
    /// proposal anchors here — its identifier set becomes the merge target.
    let named: ProviderUsageSnapshot
    /// The legacy card (no identifiers AND no accountEmail). Will be
    /// pulled into the named card's group upon user confirmation.
    let legacy: ProviderUsageSnapshot
    /// App version of the legacy card's source Mac, if known. Used for the
    /// §9 inline hint ("CodexBar 0.X reports this provider differently").
    let legacyMacVersion: String?

    /// Identifiers that the user's "Same account" confirmation links across.
    /// Persisted into the `linkedIdentifiers` field of the new
    /// `ProviderAccountLinkage` CKRecord; the union-find then unions any
    /// snapshot whose effective identifiers contain at least one.
    var linkedIdentifiers: [String] {
        // Anchor identifier from the named side (first element wins;
        // typically `accountIdentities` or synthesized email).
        let namedKey = MultiAccountLinkageCandidate.effectiveIdentifierKey(for: self.named)
        // Anchor identifier from the legacy side (legacy-no-identity bucket).
        let legacyKey = MultiAccountLinkageCandidate.effectiveIdentifierKey(for: self.legacy)
        return [namedKey, legacyKey]
    }

    /// Stable key used for SwiftUI ForEach and as the merge dedup signal.
    var hashKey: String {
        "\(self.named.cardIdentityKey)|\(self.legacy.cardIdentityKey)"
    }

    /// Mirrors `CloudSyncReader.effectiveIdentifiers` for a single snapshot
    /// — returns the FIRST identifier (the one most likely to anchor the
    /// group). Duplicates the synthesis logic here because we need it in
    /// the UI-side detector before the merge runs.
    static func effectiveIdentifierKey(for provider: ProviderUsageSnapshot) -> String {
        if let explicit = provider.accountIdentities, let first = explicit.first {
            return first
        }
        if let normalized = AccountIdentityNormalize.normalize(provider.accountEmail) {
            return "\(provider.providerID):email:\(normalized)"
        }
        return "\(provider.providerID):legacy-no-identity"
    }
}

/// Computes linkage candidates for a list of post-merge provider cards.
///
/// Input: the iOS-rendered list of provider cards (`liveProviders` after
/// `mergeSnapshots` + mock filtering).
///
/// Output: array of (named, legacy) candidate pairs. Empty array when no
/// ambiguous pair exists.
///
/// Algorithm:
/// 1. Group cards by `providerID`.
/// 2. Per group, classify each card as either NAMED (has accountIdentities
///    OR accountEmail) or LEGACY (neither).
/// 3. If exactly ONE named card + ≥1 legacy card → emit one candidate per
///    legacy card pairing each with the named card.
/// 4. If ≥2 named cards (multi-account on the named side) → ambiguous; no
///    candidates emitted (user would need to pick which named account
///    each legacy belongs to — out of scope for inline UI; UI would have
///    to be a sheet picker. Deferred to a later release).
/// 5. If 0 named + any number of legacy → all-legacy multi-Mac, already
///    merges via the shared legacy-no-identity bucket. No candidates.
enum MultiAccountLinkageDetector {
    static func candidates(
        among providers: [ProviderUsageSnapshot],
        appVersionForProvider: ((ProviderUsageSnapshot) -> String?)? = nil) -> [MultiAccountLinkageCandidate]
    {
        var byProviderID: [String: [ProviderUsageSnapshot]] = [:]
        for provider in providers {
            byProviderID[provider.providerID, default: []].append(provider)
        }

        var results: [MultiAccountLinkageCandidate] = []
        for (_, group) in byProviderID where group.count >= 2 {
            var named: [ProviderUsageSnapshot] = []
            var legacy: [ProviderUsageSnapshot] = []
            for provider in group {
                if Self.isNamed(provider) {
                    named.append(provider)
                } else {
                    legacy.append(provider)
                }
            }
            // Rule §7-A: exactly one named + ≥1 legacy → unambiguous bridge.
            guard named.count == 1, !legacy.isEmpty else { continue }
            let anchor = named[0]
            for legacyCard in legacy {
                results.append(MultiAccountLinkageCandidate(
                    named: anchor,
                    legacy: legacyCard,
                    legacyMacVersion: appVersionForProvider?(legacyCard)))
            }
        }
        // Deterministic order for UI stability (same input → same output).
        results.sort { $0.hashKey < $1.hashKey }
        return results
    }

    /// A card is NAMED when it carries either a non-empty
    /// `accountIdentities` list (Tier-A providers post-Research/019) OR
    /// a non-empty `accountEmail` (with whitespace trimmed — `" "` is
    /// effectively empty under `AccountIdentityNormalize.normalize`).
    /// Otherwise it's LEGACY.
    static func isNamed(_ provider: ProviderUsageSnapshot) -> Bool {
        if let explicit = provider.accountIdentities, !explicit.isEmpty {
            return true
        }
        if let email = provider.accountEmail,
           !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return true
        }
        return false
    }
}
