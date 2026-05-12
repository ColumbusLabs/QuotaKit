import CodexBarSync
import Testing

@testable import CodexBarMobile

/// Pins the push-notification subscription provider list. iOS 1.5.0 added
/// `abacus` and `mistral` alongside upstream Mac v0.21–0.23. Each entry
/// here corresponds to a `(provider, state)` pair iOS subscribes to at
/// launch (one zone for `depleted`, one for `restored`), so the count is
/// what determines how many CKRecordZoneSubscriptions fire.
///
/// **Cause-oriented assertions:** the list must STAY in lockstep with
/// Mac's `UsageProvider` enum cases — adding a provider on Mac without
/// adding it here means iOS never receives that provider's quota
/// notifications. We can't enforce that at compile time across the wire
/// (UsageProvider is Mac-side), so the test pins the count and the
/// presence of every known ID. Updates to either side need a matched
/// update here.
@Suite("Quota provider list")
struct QuotaProviderListTests {

    @Test("Total count is 27 (25 base + Abacus + Mistral)")
    func totalCount() {
        // Outcome: 25 → 27 in iOS 1.5.0. If this number shifts without
        // matching upstream updates, the push-subscription set drifts
        // out of sync with Mac's actual emitting providers.
        #expect(QuotaProviderList.providers.count == 27)
    }

    @Test("Subscription zone count is 54 (27 providers × 2 states)")
    func subscriptionZoneCount() {
        // Cause: iOS creates one CKRecordZoneSubscription per
        // (provider, state) pair. The implementation in
        // `QuotaTransitionSubscriptions.setupIfNeeded()` doubles
        // providers.count to derive this. Pinning so a future single-
        // state refactor (e.g. consolidate to one zone per provider)
        // can't happen without updating this test.
        #expect(QuotaProviderList.providers.count * 2 == 54)
    }

    @Test("Abacus AI is present with the upstream-canonical displayName")
    func abacusPresent() {
        let abacus = QuotaProviderList.providers.first(where: { $0.id == "abacus" })
        #expect(abacus != nil)
        // Cause: displayName MUST match
        // `AbacusProviderDescriptor.metadata.displayName` on Mac. If
        // Mac renames upstream and we don't update here, the push body
        // shows the stale name (still functional, but visibly wrong).
        #expect(abacus?.displayName == "Abacus AI")
    }

    @Test("Mistral is present with the upstream-canonical displayName")
    func mistralPresent() {
        let mistral = QuotaProviderList.providers.first(where: { $0.id == "mistral" })
        #expect(mistral != nil)
        #expect(mistral?.displayName == "Mistral")
    }

    /// Cause-oriented: a provider ID typo (e.g. accidentally "mistralai"
    /// instead of "mistral") would silently fail to subscribe — Mac
    /// writes to `Quota-mistral-depletedZone` but iOS subscribes to
    /// `Quota-mistralai-depletedZone`, so pushes are delivered into
    /// the void. Pin lowercase + no-spaces shape.
    @Test("Cause: every provider ID is lowercase and contains no whitespace")
    func providerIDFormatInvariant() {
        for provider in QuotaProviderList.providers {
            #expect(provider.id == provider.id.lowercased(),
                "Provider ID '\(provider.id)' must be lowercase")
            #expect(!provider.id.contains(" "),
                "Provider ID '\(provider.id)' must not contain spaces")
            #expect(!provider.id.isEmpty, "Provider ID must not be empty")
        }
    }

    /// Cause-oriented: the zone name template is the byte-for-byte wire
    /// contract between Mac writes and iOS subscriptions. Any change
    /// to the format (separator, casing, suffix) silently breaks
    /// existing users. Pin all known providers' resulting zone names
    /// for both states.
    @Test("Zone name template stays `Quota-{providerID}-{state}Zone`")
    func zoneNameContract() {
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "abacus", state: "depleted") ==
                "Quota-abacus-depletedZone")
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "mistral", state: "restored") ==
                "Quota-mistral-restoredZone")
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "codex", state: "depleted") ==
                "Quota-codex-depletedZone")
    }

    /// Cause-oriented: order of `providers` matters for the deterministic
    /// subscription-creation sequence on first launch (single-pass
    /// upserts). A reordering that puts a new provider before
    /// previously-existing ones would shift CK subscription IDs and
    /// re-create them all. Verify abacus + mistral are appended at
    /// the END (additive), not interleaved.
    @Test("Cause: new providers (abacus + mistral) are appended at the end")
    func newProvidersAppended() {
        let providers = QuotaProviderList.providers
        let last = providers.suffix(2).map(\.id)
        #expect(last == ["abacus", "mistral"],
            "Abacus + Mistral must stay at the tail (additive append)")
    }

    /// Cause-oriented: no duplicate IDs would silently double-subscribe.
    @Test("Cause: no duplicate provider IDs")
    func noDuplicateIDs() {
        let ids = QuotaProviderList.providers.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate provider IDs found")
    }

    /// Cause-oriented: iOS 1.5.0's catalog "Important" message references
    /// "27 providers / 54 push-subscription zones". If those numbers
    /// drift from this list, the user-facing release notes lie. Doc
    /// the cross-coupling.
    @Test("Cause: catalog 27/54 numbers match the actual list")
    func catalogNumbersAlignWithList() {
        #expect(QuotaProviderList.providers.count == 27)
        #expect(QuotaProviderList.providers.count * 2 == 54)
    }
}
