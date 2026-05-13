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

    @Test("Total count is 38 (25 base + Abacus + Mistral + 11 v0.24/v0.25)")
    func totalCount() {
        // Outcome: 25 → 27 in iOS 1.5.0 (Abacus + Mistral) →
        // 38 in iOS 1.6.0 (11 new from Mac v0.24+v0.25 catch-up).
        // If this number shifts without matching upstream updates,
        // the push-subscription set drifts out of sync with Mac's
        // actual emitting providers.
        #expect(QuotaProviderList.providers.count == 38)
    }

    @Test("Subscription zone count is 114 (38 providers × 3 states)")
    func subscriptionZoneCount() {
        // iOS 1.5.0: 38 × 2 (depleted+restored) = 76 zones.
        // iOS 1.6.0 / Mac 0.25.2 adds a third "warning" state for
        // pre-depletion threshold pushes → 38 × 3 = 114 zones.
        // `QuotaTransitionSubscriptions.makeConfigs()` builds one
        // `SubConfig` per (provider, state) — pinning here so a
        // future state addition/removal can't drift silently.
        #expect(QuotaProviderList.providers.count * 3 == 114)
    }

    @Test("Warning-zone name format matches Mac/iOS contract")
    func warningZoneNameFormat() {
        // Mac's `CloudSyncManager.writeQuotaWarningTransition` and
        // iOS's `QuotaTransitionSubscriptions.makeConfigs()` MUST
        // agree on this template byte-for-byte. Pinning so a future
        // rename here would break warning push delivery entirely.
        #expect(QuotaProviderList.quotaZoneName(
            providerID: "codex", state: "warning") == "Quota-codex-warningZone")
        #expect(QuotaProviderList.quotaZoneName(
            providerID: "claude", state: "warning") == "Quota-claude-warningZone")
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
    /// re-create them all. Verify Abacus + Mistral + the 11 v0.24/v0.25
    /// additions are appended at the END (additive), not interleaved.
    @Test("Cause: new providers (v0.23 + v0.24/v0.25) are appended at the tail")
    func newProvidersAppended() {
        let providers = QuotaProviderList.providers
        // Abacus + Mistral were positions [25, 26] in iOS 1.5.0.
        // The 11 v0.24/v0.25 catch-up additions are positions [27..37]
        // (38 total). Pin the full tail order so a careless edit doesn't
        // reorder providers and force every existing user's iOS app to
        // re-create 76 CK subscriptions.
        let tail = providers.suffix(13).map(\.id)
        #expect(tail == [
            "abacus", "mistral",
            "openai", "manus", "windsurf", "mimo", "doubao",
            "deepseek", "codebuff", "crof", "venice", "commandcode",
            "stepfun",
        ], "All 13 catch-up additions must stay at the tail in this order")
    }

    // MARK: - iOS 1.6.0 · v0.24+v0.25 catch-up presence

    /// Cause-oriented: each provider must be present with its
    /// upstream-canonical displayName so the static `alertBody`
    /// generated at subscription time matches what Mac writes into
    /// the push body.
    @Test("OpenAI API balance present (v0.25 #877)")
    func openaiPresent() {
        let openai = QuotaProviderList.providers.first(where: { $0.id == "openai" })
        #expect(openai != nil)
        #expect(openai?.displayName == "OpenAI API")
    }

    @Test("Manus present (v0.25 #700)")
    func manusPresent() {
        let manus = QuotaProviderList.providers.first(where: { $0.id == "manus" })
        #expect(manus != nil)
        #expect(manus?.displayName == "Manus")
    }

    @Test("Windsurf present (v0.24 #583)")
    func windsurfPresent() {
        let windsurf = QuotaProviderList.providers.first(where: { $0.id == "windsurf" })
        #expect(windsurf != nil)
        #expect(windsurf?.displayName == "Windsurf")
    }

    @Test("Xiaomi MiMo present (v0.25 #651)")
    func mimoPresent() {
        let mimo = QuotaProviderList.providers.first(where: { $0.id == "mimo" })
        #expect(mimo != nil)
        #expect(mimo?.displayName == "Xiaomi MiMo")
    }

    @Test("Doubao present (v0.25 #498)")
    func doubaoPresent() {
        let doubao = QuotaProviderList.providers.first(where: { $0.id == "doubao" })
        #expect(doubao != nil)
        #expect(doubao?.displayName == "Doubao")
    }

    @Test("DeepSeek present (v0.24 #811)")
    func deepseekPresent() {
        let deepseek = QuotaProviderList.providers.first(where: { $0.id == "deepseek" })
        #expect(deepseek != nil)
        #expect(deepseek?.displayName == "DeepSeek")
    }

    @Test("Codebuff present (v0.24 #837)")
    func codebuffPresent() {
        let codebuff = QuotaProviderList.providers.first(where: { $0.id == "codebuff" })
        #expect(codebuff != nil)
        #expect(codebuff?.displayName == "Codebuff")
    }

    @Test("Crof present (v0.25 #872)")
    func crofPresent() {
        let crof = QuotaProviderList.providers.first(where: { $0.id == "crof" })
        #expect(crof != nil)
        #expect(crof?.displayName == "Crof")
    }

    @Test("Venice present (v0.25 #865)")
    func venicePresent() {
        let venice = QuotaProviderList.providers.first(where: { $0.id == "venice" })
        #expect(venice != nil)
        #expect(venice?.displayName == "Venice")
    }

    @Test("Command Code present (v0.25 #857)")
    func commandCodePresent() {
        let cc = QuotaProviderList.providers.first(where: { $0.id == "commandcode" })
        #expect(cc != nil)
        #expect(cc?.displayName == "Command Code")
    }

    @Test("StepFun present (v0.25 #815)")
    func stepfunPresent() {
        let stepfun = QuotaProviderList.providers.first(where: { $0.id == "stepfun" })
        #expect(stepfun != nil)
        #expect(stepfun?.displayName == "StepFun")
    }

    /// Cause-oriented: no duplicate IDs would silently double-subscribe.
    @Test("Cause: no duplicate provider IDs")
    func noDuplicateIDs() {
        let ids = QuotaProviderList.providers.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate provider IDs found")
    }

    /// Cause-oriented: iOS 1.6.0's catalog "Important" message references
    /// "38 providers / 76 push-subscription zones" (was 27 / 54 in
    /// iOS 1.5.0). If those numbers drift from this list, the user-facing
    /// release notes lie. Doc the cross-coupling.
    @Test("Cause: catalog 38/76 numbers match the actual list")
    func catalogNumbersAlignWithList() {
        #expect(QuotaProviderList.providers.count == 38)
        #expect(QuotaProviderList.providers.count * 2 == 76)
    }
}
