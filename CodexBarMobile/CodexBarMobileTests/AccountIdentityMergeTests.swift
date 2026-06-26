import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Pins the union-find merge behavior introduced for multi-device,
/// multi-version Mac scenarios. Covers the 11-case test matrix in
/// `Research/019-account-identity-multi-version-merge.md` §8 and the
/// effective-identifier synthesis rules in `CloudSyncReader`.
@Suite("Account identity multi-version merge")
struct AccountIdentityMergeTests {
    private let pinnedDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - effectiveIdentifiers synthesis

    @Test("Modern snapshot with explicit identifiers passes them through")
    func explicitIdentifiers() {
        let p = Self.makeProvider(
            id: "codex",
            email: "user@example.com",
            identifiers: ["codex:account:org-x", "codex:email:user@example.com"])
        let ids = CloudSyncReader.effectiveIdentifiers(for: p)
        #expect(ids == ["codex:account:org-x", "codex:email:user@example.com"])
    }

    @Test("Legacy snapshot with email synthesizes `provider:email:<lowered>` identifier")
    func legacyEmailSynthesis() {
        let p = Self.makeProvider(
            id: "codex",
            email: "User@Example.COM",
            identifiers: nil)
        let ids = CloudSyncReader.effectiveIdentifiers(for: p)
        #expect(ids == ["codex:email:user@example.com"])
    }

    @Test("Legacy snapshot with nil email falls back to legacy-no-identity bucket")
    func legacyNoEmailBucket() {
        let p = Self.makeProvider(id: "codex", email: nil, identifiers: nil)
        let ids = CloudSyncReader.effectiveIdentifiers(for: p)
        #expect(ids == ["codex:legacy-no-identity"])
    }

    @Test("Empty identifier array is treated as legacy (NOT explicit)")
    func emptyArrayTreatedAsLegacy() {
        let p = Self.makeProvider(
            id: "codex",
            email: "user@example.com",
            identifiers: [])
        let ids = CloudSyncReader.effectiveIdentifiers(for: p)
        // Empty array → no explicit, fall through to email synthesis.
        #expect(ids == ["codex:email:user@example.com"])
    }

    // MARK: - mergeSnapshots — the 11-case matrix from Research/019 §8

    @Test("§8.1 — All Macs on same version: 1 group")
    func allOnSameVersion() throws {
        let s1 = Self.makeMac(deviceID: "mac-A", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u@x.com",
                identifiers: ["codex:email:u@x.com"]),
        ])
        let s2 = Self.makeMac(deviceID: "mac-B", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u@x.com",
                identifiers: ["codex:email:u@x.com"]),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([s1, s2]))
        #expect(merged.providers.count == 1, "Same email → 1 card.")
    }

    @Test("§8.2 — One version behind (legacy alongside modern, different keys)")
    func oneVersionBehind() throws {
        // Modern Mac writes account+email; legacy Mac writes nil identifiers
        // and nil email. They DON'T share an identifier → 2 cards (correct;
        // user can L3 confirm or upgrade old Mac to break ambiguity).
        let modern = Self.makeMac(deviceID: "mac-A", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u@x.com",
                identifiers: ["codex:account:org-x", "codex:email:u@x.com"]),
        ])
        let legacy = Self.makeMac(deviceID: "mac-B", providers: [
            Self.makeProvider(id: "codex", email: nil, identifiers: nil),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([modern, legacy]))
        #expect(merged.providers.count == 2, "Different identifier sets → 2 cards.")
    }

    @Test("§8.3 — One version ahead (newer Mac added a field): 1 group via shared email")
    func oneVersionAhead() throws {
        let baseline = Self.makeMac(deviceID: "mac-A", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u@x.com",
                identifiers: ["codex:email:u@x.com"]),
        ])
        let ahead = Self.makeMac(deviceID: "mac-B", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u@x.com",
                identifiers: ["codex:email:u@x.com", "codex:account:org-x"]),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([baseline, ahead]))
        #expect(merged.providers.count == 1, "Shared email bridges old + new → 1 card.")
    }

    @Test("§8.4 — Transition period (3-Mac, 3 versions, all double-write email)")
    func transitionPeriod() throws {
        let m1 = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u@x.com",
                identifiers: ["codex:email:u@x.com"]),
        ])
        let m2 = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u@x.com",
                identifiers: ["codex:email:u@x.com", "codex:account:org-x"]),
        ])
        let m3 = Self.makeMac(deviceID: "C", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u@x.com",
                identifiers: ["codex:email:u@x.com", "codex:account:org-x", "codex:phone:+1-555"]),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([m1, m2, m3]))
        #expect(merged.providers.count == 1, "Shared email or shared org bridges all 3 → 1 card.")
    }

    @Test("§8.5 — Hard-drop policy followed: post-deprecation override via shared sub")
    func hardDropPolicyFollowed() throws {
        // After 3 minor releases of double-writing email + sub, 0.30 stops
        // writing email. Mac-A still writes both (running 0.27); Mac-B writes
        // sub-only (running 0.30+). Shared sub → merge.
        let mA = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u@x.com",
                identifiers: ["codex:email:u@x.com", "codex:sub:s1"]),
        ])
        let mB = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(
                id: "codex",
                email: nil,
                identifiers: ["codex:sub:s1"]),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([mA, mB]))
        #expect(merged.providers.count == 1, "Shared sub merges across old + post-deprecation Macs.")
    }

    @Test("§8.6 — Hard-drop policy violated: 2 groups (L3 needed)")
    func hardDropPolicyViolated() throws {
        // Mac 0.27 hard-removed email without overlap with sub. Mac-A writes
        // only email; Mac-B and Mac-C write only sub. No overlap → 2 groups.
        let mA = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(
                id: "codex",
                email: nil,
                identifiers: ["codex:email:u@x.com"]),
        ])
        let mB = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(
                id: "codex",
                email: nil,
                identifiers: ["codex:sub:s1"]),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([mA, mB]))
        #expect(
            merged.providers.count == 2,
            "No shared identifier → 2 separate cards. L3 user-merge would be the cure.")
    }

    @Test("§8.7 — Legacy + new Mac with same accountEmail: 1 group via synthesized email")
    func legacyAndNewSameEmail() throws {
        // The user's actual reported issue: 0.20.3 Mac (no `accountIdentities`)
        // sharing an email with a 0.23 Mac (writes both `accountIdentities`
        // and accountEmail). The legacy Mac's email is synthesized into
        // `codex:email:<email>` which matches the new Mac's explicit
        // `codex:email:<email>` identifier → merged.
        let legacy = Self.makeMac(deviceID: "mbp", providers: [
            Self.makeProvider(id: "codex", email: "u@x.com", identifiers: nil),
        ])
        let modern = Self.makeMac(deviceID: "studio", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u@x.com",
                identifiers: ["codex:account:org-x", "codex:email:u@x.com"]),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([legacy, modern]))
        #expect(
            merged.providers.count == 1,
            "Synthesized legacy `codex:email:u@x.com` bridges to new explicit identifier.")
    }

    @Test("Over-limit legacy emails with the same prefix stay separate")
    func overLimitLegacyEmailsDoNotPrefixCollide() throws {
        let sharedPrefix = String(repeating: "a", count: AccountIdentityNormalize.maxAccountIdentifierLength + 20)
        let firstEmail = sharedPrefix + "1@example.com"
        let secondEmail = sharedPrefix + "2@example.com"

        let mA = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(id: "codex", email: firstEmail, identifiers: nil),
        ])
        let mB = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(id: "codex", email: secondEmail, identifiers: nil),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([mA, mB]))
        #expect(
            merged.providers.count == 2,
            "Distinct over-limit emails must hash to distinct synthesized identifiers.")
    }

    @Test("Modern explicit hashed email matches legacy synthesis")
    func modernExplicitHashedEmailMatchesLegacySynthesis() throws {
        let longEmail = String(repeating: "a", count: AccountIdentityNormalize.maxAccountIdentifierLength + 100)
            + "@example.com"
        let normalized = try #require(AccountIdentityNormalize.normalize(longEmail))

        let legacy = Self.makeMac(deviceID: "legacy", providers: [
            Self.makeProvider(id: "codex", email: longEmail, identifiers: nil),
        ])
        let modern = Self.makeMac(deviceID: "modern", providers: [
            Self.makeProvider(
                id: "codex",
                email: longEmail,
                identifiers: ["codex:email:\(normalized)"]),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([legacy, modern]))
        #expect(
            merged.providers.count == 1,
            "Legacy synthesis must still bridge to the modern explicit hashed identifier.")
    }

    @Test("§8.8 — Different accounts on same provider: keep separate")
    func differentAccountsLookSimilar() throws {
        let mA = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(
                id: "codex",
                email: "userA@x.com",
                identifiers: ["codex:email:usera@x.com"]),
        ])
        let mB = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(
                id: "codex",
                email: "userB@x.com",
                identifiers: ["codex:email:userb@x.com"]),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([mA, mB]))
        #expect(merged.providers.count == 2, "Genuinely different emails → 2 cards.")
    }

    @Test("§8.9 — Transitive merge (Mac B asserts both emails are same account)")
    func transitiveMerge() throws {
        let mA = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u1@x.com",
                identifiers: ["codex:email:u1@x.com"]),
        ])
        let mB = Self.makeMac(deviceID: "B", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u1@x.com",
                identifiers: ["codex:email:u1@x.com", "codex:email:u2@x.com"]),
        ])
        let mC = Self.makeMac(deviceID: "C", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u2@x.com",
                identifiers: ["codex:email:u2@x.com"]),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([mA, mB, mC]))
        #expect(
            merged.providers.count == 1,
            "A↔B share u1; B↔C share u2; transitive closure → 1 card.")
    }

    @Test("§8.10 — All legacy with nil email: single shared bucket (current behavior preserved)")
    func legacyBucketIsolation() throws {
        // 3 legacy Macs, all with nil identifiers + nil email.
        // Pre-019 behavior grouped them together (via `(providerID, "")`)
        // into one card. We must preserve that — the legacy-no-identity
        // synthesis bucket does exactly that.
        let macs = (0..<3).map { i in
            Self.makeMac(deviceID: "mac-\(i)", providers: [
                Self.makeProvider(id: "codex", email: nil, identifiers: nil),
            ])
        }
        let merged = try #require(CloudSyncReader.mergeSnapshots(macs))
        #expect(
            merged.providers.count == 1,
            "All legacy with nil email → single bucket (pre-019 behavior preserved).")
    }

    @Test("§8.11 — Two-provider isolation: codex and claude never cross-merge")
    func crossProviderIsolation() throws {
        // Even if two providers happened to use the same email, their
        // identifiers carry different `providerID:` prefixes so the strings
        // never match.
        let snapshot = Self.makeMac(deviceID: "A", providers: [
            Self.makeProvider(
                id: "codex",
                email: "u@x.com",
                identifiers: ["codex:email:u@x.com"]),
            Self.makeProvider(
                id: "claude",
                email: "u@x.com",
                identifiers: ["claude:email:u@x.com"]),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([snapshot]))
        #expect(merged.providers.count == 2, "Different providers never merge.")
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
