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
    @Test
    func `Total count is 56 including DeepInfra`() {
        // Outcome: 25 → 27 in iOS 1.5.0 (Abacus + Mistral) →
        // 38 in iOS 1.6.0 (11 new from Mac v0.24+v0.25 catch-up) →
        // 40 in iOS 1.7.0 (2 new from Mac v0.26.0: moonshot + bedrock) →
        // 45 in iOS 1.8.0 (5 new from Mac v0.27.0: grok, groq,
        // elevenlabs, deepgram, llmproxy) →
        // 48 in iOS 1.9.0 (3 new from Mac v0.28+v0.29: azureopenai,
        // alibabatokenplan, t3chat) →
        // 49 in iOS 1.10.0 (Sakana AI from upstream v0.36.x) →
        // 50 after Qoder, 51 after Sub2API, 52 after ZenMux, 54 after
        // ClinePass and LongCat, 55 after Neuralwatt, and 56 after DeepInfra.
        // ai& is spend-only and has no quota transitions, so it intentionally
        // does not consume three CloudKit quota-zone subscriptions.
        // If this number shifts without matching upstream updates,
        // the push-subscription set drifts out of sync with Mac's
        // actual emitting providers.
        #expect(QuotaProviderList.providers.count == 56)
    }

    @Test
    func `Subscription zone count is 168 (56 providers × 3 states)`() {
        // iOS 1.5.0: 27 × 2 = 54 zones.
        // iOS 1.6.0 / Mac 0.25.2: 38 × 3 (depleted/restored/warning) = 114.
        // iOS 1.7.0 / Mac 0.26.2: 40 × 3 = 120 zones (+moonshot, +bedrock).
        // iOS 1.8.0 / Mac 0.27.0: 45 × 3 = 135 zones (+grok, +groq,
        // +elevenlabs, +deepgram, +llmproxy).
        // iOS 1.9.0 / Mac 0.29.0: 48 × 3 = 144 zones (+azureopenai,
        // +alibabatokenplan, +t3chat).
        // iOS 1.10.0 / Mac 0.36.x: 49 × 3 = 147 zones (+sakana).
        // Qoder/Sub2API/ZenMux catch-up: 52 × 3 = 156 zones.
        // ClinePass/LongCat catch-up: 54 × 3 = 162 zones.
        // Neuralwatt catch-up: 55 × 3 = 165 zones.
        // DeepInfra catch-up: 56 × 3 = 168 zones.
        // `QuotaTransitionSubscriptions.makeConfigs()` builds one
        // `SubConfig` per (provider, state) — pinning here so a
        // future state addition/removal can't drift silently.
        #expect(QuotaProviderList.providers.count * 3 == 168)
    }

    @Test
    func `Warning-zone name format matches Mac/iOS contract`() {
        // Mac's `CloudSyncManager.writeQuotaWarningTransition` and
        // iOS's `QuotaTransitionSubscriptions.makeConfigs()` MUST
        // agree on this template byte-for-byte. Pinning so a future
        // rename here would break warning push delivery entirely.
        #expect(QuotaProviderList.quotaZoneName(
            providerID: "codex", state: "warning") == "Quota-codex-warningZone")
        #expect(QuotaProviderList.quotaZoneName(
            providerID: "claude", state: "warning") == "Quota-claude-warningZone")
    }

    @Test
    func `Abacus AI is present with the upstream-canonical displayName`() {
        let abacus = QuotaProviderList.providers.first(where: { $0.id == "abacus" })
        #expect(abacus != nil)
        // Cause: displayName MUST match
        // `AbacusProviderDescriptor.metadata.displayName` on Mac. If
        // Mac renames upstream and we don't update here, the push body
        // shows the stale name (still functional, but visibly wrong).
        #expect(abacus?.displayName == "Abacus AI")
    }

    @Test
    func `Mistral is present with the upstream-canonical displayName`() {
        let mistral = QuotaProviderList.providers.first(where: { $0.id == "mistral" })
        #expect(mistral != nil)
        #expect(mistral?.displayName == "Mistral")
    }

    /// Cause-oriented: a provider ID typo (e.g. accidentally "mistralai"
    /// instead of "mistral") would silently fail to subscribe — Mac
    /// writes to `Quota-mistral-depletedZone` but iOS subscribes to
    /// `Quota-mistralai-depletedZone`, so pushes are delivered into
    /// the void. Pin lowercase + no-spaces shape.
    @Test
    func `Cause: every provider ID is lowercase and contains no whitespace`() {
        for provider in QuotaProviderList.providers {
            #expect(
                provider.id == provider.id.lowercased(),
                "Provider ID '\(provider.id)' must be lowercase")
            #expect(
                !provider.id.contains(" "),
                "Provider ID '\(provider.id)' must not contain spaces")
            #expect(!provider.id.isEmpty, "Provider ID must not be empty")
        }
    }

    /// Cause-oriented: the zone name template is the byte-for-byte wire
    /// contract between Mac writes and iOS subscriptions. Any change
    /// to the format (separator, casing, suffix) silently breaks
    /// existing users. Pin all known providers' resulting zone names
    /// for both states.
    @Test
    func `Zone name template stays Quota-{providerID}-{state}Zone`() {
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
    @Test
    func `Cause: new providers through DeepInfra are appended at the tail`() {
        let providers = QuotaProviderList.providers
        // Providers are append-only so per-(provider,state) CK subscription
        // IDs stay stable across upgrades. Pin the recent tail so a careless
        // edit can't reorder providers and force every existing user's iOS
        // app to re-create subscriptions.
        //  - iOS 1.8.0 appended 5 v0.27.0 providers (positions [40..44]).
        //  - iOS 1.9.0 appended 3 v0.28+v0.29 providers (positions [45..47]).
        //  - iOS 1.10.0 appended Sakana AI (position [48]).
        //  - Qoder catch-up appended Qoder (position [49]).
        //  - Sub2API catch-up appended Sub2API (position [50]).
        //  - ZenMux, ClinePass, and LongCat occupy positions [51...53].
        //  - DeepInfra occupies position [55].
        let tail = providers.suffix(16).map(\.id)
        #expect(tail == [
            "grok", "groq", "elevenlabs", "deepgram", "llmproxy",
            "azureopenai", "alibabatokenplan", "t3chat", "sakana", "qoder", "sub2api", "zenmux",
            "clinepass", "longcat", "neuralwatt", "deepinfra",
        ], "provider catch-up additions through DeepInfra must stay at the tail in this order")
    }

    // MARK: - iOS 1.6.0 · v0.24+v0.25 catch-up presence

    /// Cause-oriented: each provider must be present with its
    /// upstream-canonical displayName so the static `alertBody`
    /// generated at subscription time matches what Mac writes into
    /// the push body.
    @Test
    func `OpenAI API balance present (v0.25 #877)`() {
        let openai = QuotaProviderList.providers.first(where: { $0.id == "openai" })
        #expect(openai != nil)
        #expect(openai?.displayName == "OpenAI API")
    }

    @Test
    func `Manus present (v0.25 #700)`() {
        let manus = QuotaProviderList.providers.first(where: { $0.id == "manus" })
        #expect(manus != nil)
        #expect(manus?.displayName == "Manus")
    }

    @Test
    func `Windsurf present (v0.24 #583)`() {
        let windsurf = QuotaProviderList.providers.first(where: { $0.id == "windsurf" })
        #expect(windsurf != nil)
        #expect(windsurf?.displayName == "Windsurf")
    }

    @Test
    func `Xiaomi MiMo present (v0.25 #651)`() {
        let mimo = QuotaProviderList.providers.first(where: { $0.id == "mimo" })
        #expect(mimo != nil)
        #expect(mimo?.displayName == "Xiaomi MiMo")
    }

    @Test
    func `Doubao present (v0.25 #498)`() {
        let doubao = QuotaProviderList.providers.first(where: { $0.id == "doubao" })
        #expect(doubao != nil)
        #expect(doubao?.displayName == "Doubao")
    }

    @Test
    func `DeepSeek present (v0.24 #811)`() {
        let deepseek = QuotaProviderList.providers.first(where: { $0.id == "deepseek" })
        #expect(deepseek != nil)
        #expect(deepseek?.displayName == "DeepSeek")
    }

    @Test
    func `Codebuff present (v0.24 #837)`() {
        let codebuff = QuotaProviderList.providers.first(where: { $0.id == "codebuff" })
        #expect(codebuff != nil)
        #expect(codebuff?.displayName == "Codebuff")
    }

    @Test
    func `Crof present (v0.25 #872)`() {
        let crof = QuotaProviderList.providers.first(where: { $0.id == "crof" })
        #expect(crof != nil)
        #expect(crof?.displayName == "Crof")
    }

    @Test
    func `Venice present (v0.25 #865)`() {
        let venice = QuotaProviderList.providers.first(where: { $0.id == "venice" })
        #expect(venice != nil)
        #expect(venice?.displayName == "Venice")
    }

    @Test
    func `Command Code present (v0.25 #857)`() {
        let cc = QuotaProviderList.providers.first(where: { $0.id == "commandcode" })
        #expect(cc != nil)
        #expect(cc?.displayName == "Command Code")
    }

    @Test
    func `StepFun present (v0.25 #815)`() {
        let stepfun = QuotaProviderList.providers.first(where: { $0.id == "stepfun" })
        #expect(stepfun != nil)
        #expect(stepfun?.displayName == "StepFun")
    }

    /// Cause-oriented: no duplicate IDs would silently double-subscribe.
    @Test
    func `Cause: no duplicate provider IDs`() {
        let ids = QuotaProviderList.providers.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate provider IDs found")
    }

    /// Cause-oriented: the catalog/release-notes copy references the
    /// provider count and zone count. If those numbers drift from this
    /// list, the user-facing release notes lie. Doc the cross-coupling.
    /// (Zone count is providers × 3 states since iOS 1.6.0 added the
    /// `warning` state alongside `depleted`/`restored`.)
    @Test
    func `Cause: catalog 56/168 numbers match the actual list`() {
        #expect(QuotaProviderList.providers.count == 56)
        #expect(QuotaProviderList.providers.count * 3 == 168)
    }

    @Test
    func `Sakana AI present (v0.36.x #1774)`() {
        let sakana = QuotaProviderList.providers.first(where: { $0.id == "sakana" })
        #expect(sakana != nil)
        #expect(sakana?.displayName == "Sakana AI")
    }

    @Test
    func `Qoder present (v0.36.x #1833)`() {
        let qoder = QuotaProviderList.providers.first(where: { $0.id == "qoder" })
        #expect(qoder != nil)
        #expect(qoder?.displayName == "Qoder")
    }

    @Test
    func `ZenMux present with canonical display name`() {
        let zenMux = QuotaProviderList.providers.first(where: { $0.id == "zenmux" })
        #expect(zenMux?.displayName == "ZenMux")

        let clinePass = QuotaProviderList.providers.first(where: { $0.id == "clinepass" })
        let longCat = QuotaProviderList.providers.first(where: { $0.id == "longcat" })
        let neuralwatt = QuotaProviderList.providers.first(where: { $0.id == "neuralwatt" })
        #expect(clinePass?.displayName == "ClinePass")
        #expect(longCat?.displayName == "LongCat")
        #expect(neuralwatt?.displayName == "Neuralwatt")
    }

    @Test
    func `DeepInfra is present and spend-only ai& has no quota subscription`() {
        let deepInfra = QuotaProviderList.providers.first(where: { $0.id == "deepinfra" })
        let aiAnd = QuotaProviderList.providers.first(where: { $0.id == "aiand" })
        #expect(deepInfra?.displayName == "DeepInfra")
        #expect(aiAnd == nil)
    }

    /// Cause-oriented: iOS 1.7.0 specifically adds Moonshot + Bedrock.
    /// Pin them by id + displayName so a rename on either side doesn't
    /// silently break push delivery for the new providers.
    @Test
    func `Moonshot / Kimi API present (v0.26.0 #911)`() {
        let m = QuotaProviderList.providers.first(where: { $0.id == "moonshot" })
        #expect(m != nil)
        #expect(m?.displayName == "Moonshot / Kimi API")
    }

    @Test
    func `AWS Bedrock present (v0.26.0 #897)`() {
        let b = QuotaProviderList.providers.first(where: { $0.id == "bedrock" })
        #expect(b != nil)
        #expect(b?.displayName == "AWS Bedrock")
    }
}
