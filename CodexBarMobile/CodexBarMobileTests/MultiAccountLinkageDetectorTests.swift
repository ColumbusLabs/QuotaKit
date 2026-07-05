import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Pins the rules in `MultiAccountLinkageDetector` that decide WHEN iOS
/// should offer the user a "Same account?" prompt for cross-version Macs.
///
/// The detector is the gate between the union-find merge result and the
/// inline §7 UI: it surfaces candidates only when the (named, legacy)
/// pairing is unambiguous, and stays silent when guessing would risk
/// wrongly merging two real accounts.
@Suite("Multi-account linkage detector")
struct MultiAccountLinkageDetectorTests {
    @Test
    func `One named + one legacy → 1 candidate`() {
        let named = Self.makeProvider(
            id: "codex", email: "user@x.com",
            identifiers: ["codex:email:user@x.com"])
        let legacy = Self.makeProvider(id: "codex", email: nil, identifiers: nil)
        let candidates = MultiAccountLinkageDetector.candidates(
            among: [named, legacy])
        #expect(candidates.count == 1)
        #expect(candidates.first?.named.cardIdentityKey == named.cardIdentityKey)
        #expect(candidates.first?.legacy.cardIdentityKey == legacy.cardIdentityKey)
    }

    @Test
    func `One named + two legacy → 2 candidates (each legacy paired with the named)`() {
        let named = Self.makeProvider(
            id: "codex", email: "user@x.com",
            identifiers: ["codex:email:user@x.com"])
        // Two legacy snapshots from two old Macs both fell to legacy bucket.
        // BOTH should be offered to merge into `named`.
        // Note: the detector receives POST-merge cards. Two legacy cards
        // from two Macs would actually merge first (both in
        // legacy-no-identity bucket) — so in practice this test exercises
        // a synthetic ambiguity. Pinning the rule for completeness.
        let legacy1 = Self.makeProvider(id: "codex", email: nil, identifiers: nil)
        let legacy2 = Self.makeProvider(
            id: "codex", email: " ", identifiers: nil) // empty-after-trim email
        let candidates = MultiAccountLinkageDetector.candidates(
            among: [named, legacy1, legacy2])
        #expect(candidates.count == 2)
        let legacyKeys = Set(candidates.map(\.legacy.cardIdentityKey))
        #expect(legacyKeys.contains(legacy1.cardIdentityKey))
        #expect(legacyKeys.contains(legacy2.cardIdentityKey))
    }

    @Test
    func `Two named + one legacy → 0 candidates (ambiguous; user must pick)`() {
        let alice = Self.makeProvider(
            id: "codex", email: "alice@x.com",
            identifiers: ["codex:email:alice@x.com"])
        let bob = Self.makeProvider(
            id: "codex", email: "bob@x.com",
            identifiers: ["codex:email:bob@x.com"])
        let legacy = Self.makeProvider(id: "codex", email: nil, identifiers: nil)
        let candidates = MultiAccountLinkageDetector.candidates(
            among: [alice, bob, legacy])
        #expect(
            candidates.isEmpty,
            "Two real Codex accounts (alice + bob) + 1 nameless = iOS can't pick; skip auto-prompt.")
    }

    @Test
    func `Zero named + many legacy → 0 candidates (no auto-merge offered)`() {
        let legacy1 = Self.makeProvider(id: "codex", email: nil, identifiers: nil)
        let legacy2 = Self.makeProvider(id: "codex", email: nil, identifiers: nil)
        let candidates = MultiAccountLinkageDetector.candidates(
            among: [legacy1, legacy2])
        // These already merge via shared legacy-no-identity bucket — no
        // candidate needed since the union-find handles them.
        #expect(candidates.isEmpty)
    }

    @Test
    func `Single card → 0 candidates (nothing to merge)`() {
        let only = Self.makeProvider(
            id: "codex", email: "user@x.com",
            identifiers: ["codex:email:user@x.com"])
        let candidates = MultiAccountLinkageDetector.candidates(among: [only])
        #expect(candidates.isEmpty)
    }

    @Test
    func `Cross-provider isolation: claude legacy doesn't get merged into codex named`() {
        let codexNamed = Self.makeProvider(
            id: "codex", email: "user@x.com",
            identifiers: ["codex:email:user@x.com"])
        let claudeLegacy = Self.makeProvider(id: "claude", email: nil, identifiers: nil)
        let candidates = MultiAccountLinkageDetector.candidates(
            among: [codexNamed, claudeLegacy])
        #expect(
            candidates.isEmpty,
            "Different providerID never pairs into a candidate.")
    }

    @Test
    func `appVersionForProvider supplies legacyMacVersion for §9 inline hint`() {
        let named = Self.makeProvider(
            id: "codex", email: "user@x.com",
            identifiers: ["codex:email:user@x.com"])
        let legacy = Self.makeProvider(id: "codex", email: nil, identifiers: nil)
        let candidates = MultiAccountLinkageDetector.candidates(
            among: [named, legacy],
            appVersionForProvider: { provider in
                provider.cardIdentityKey == legacy.cardIdentityKey ? "0.23.6" : "0.25.1"
            })
        #expect(
            candidates.first?.legacyMacVersion == "0.23.6",
            "Detector forwards the legacy snapshot's Mac version for the inline hint.")
    }

    @Test
    func `MultiAccountLinkageCandidate.linkedIdentifiers carries anchor IDs from both sides`() {
        let named = Self.makeProvider(
            id: "codex", email: "user@x.com",
            identifiers: ["codex:account:org-123", "codex:email:user@x.com"])
        let legacy = Self.makeProvider(id: "codex", email: nil, identifiers: nil)
        let candidate = MultiAccountLinkageCandidate(
            named: named, legacy: legacy, legacyMacVersion: nil)
        let linked = candidate.linkedIdentifiers
        #expect(
            linked.contains("codex:account:org-123"),
            "Named-side anchor (first explicit identifier) included.")
        #expect(
            linked.contains("codex:legacy-no-identity"),
            "Legacy-side bucket key included so union-find can find both sides.")
    }

    @Test
    func `Candidate emission order is deterministic (sorted by hashKey)`() {
        let named = Self.makeProvider(
            id: "codex", email: "user@x.com",
            identifiers: ["codex:email:user@x.com"])
        let l1 = Self.makeProvider(
            id: "codex", email: " ", identifiers: nil)
        let l2 = Self.makeProvider(id: "codex", email: nil, identifiers: nil)

        let runA = MultiAccountLinkageDetector.candidates(among: [named, l1, l2])
        let runB = MultiAccountLinkageDetector.candidates(among: [l2, l1, named])
        let keysA = runA.map(\.hashKey)
        let keysB = runB.map(\.hashKey)
        #expect(
            keysA == keysB,
            "Different input orderings produce the same candidate list — UI doesn't flicker between renders.")
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
}
