# 019 · Account Identity Multi-Version Merge — Research

**Status:** `ready` — design locked. Folds into Mac 0.23 + iOS 1.5.0. **No marketing-version changes.** Build numbers move within current marketing tags (technical detail, not user-facing).
**Author:** Architect role.
**Date:** 2026-04-27.
**Triggered by:** Real-world repro on user's machine — single Codex account, two Macs (one on 0.20.3 / one on 0.23), iOS 1.5.0 (Build 96) showed **two** Codex cards because the merge key collapsed when one Mac wrote `accountEmail` and the other didn't.
**Related:** [018-model-fallback-pricing.md](018-model-fallback-pricing.md) (sibling design with the same "Mac evolves, iOS must keep working" theme).

---

## 1. Problem statement

`CloudSyncReader.mergeSnapshots` groups provider snapshots by `(providerID, accountEmail ?? "")`. Two failure modes show up the moment you have **N Macs running M different versions** with **K different identity-field schemas**:

1. **Schema-shape drift.** Mac 0.23 writes `accountEmail`. Mac 0.20.3 writes `accountEmail = nil`. Same logical account, two grouping buckets, two cards.
2. **Schema evolution.** A future Mac 0.27 starts writing `accountSub` and stops writing `accountEmail`. iOS keyed on `accountEmail` produces three buckets (0.23 with email, 0.20.3 with nil, 0.27 with nil-but-different-truth) for the same account.
3. **Hard-removal.** A future Mac 0.30 deletes `accountEmail` entirely. Old Macs still write it. No overlap → permanent split.

Anything we hard-code in the iOS merge key (single field, single algorithm) breaks on the next schema change. The architecture must let **iOS keep working without redeployment** as Mac evolves.

---

## 2. Design principles (the load-bearing 4)

1. **iOS is the merge authority.** Mac doesn't decide which snapshots are "the same account." Mac just tells iOS what stable identifiers it knows about. iOS does the grouping. (Mac can't know which Macs are the same account anyway — only iOS sees all snapshots at once.)
2. **Identity is a SET, not a value.** Each snapshot carries a list of stable identifiers Mac currently knows. iOS unions across the set: any pair of snapshots that share *any* identifier is in the same account.
3. **Identifier writes are additive.** Mac never silently drops an identifier from the set in a new release. Removing an identifier requires a documented deprecation cycle (≥3 minor versions of double-writing).
4. **Identifiers are opaque to iOS.** iOS never parses or interprets the identifier strings. It only does string equality + connected-components grouping. Mac can introduce new identifier schemes (`uuid:`, `sub:`, `phone:`, …) without iOS code changes.

---

## 3. Wire format addition

`Shared/Models/UsageSnapshot.swift`:

```swift
public struct ProviderUsageSnapshot: Codable, Sendable, Equatable {
    // ... existing fields stay unchanged ...

    /// Mac-side stable identifiers for the logical account this snapshot
    /// represents. iOS uses these as grouping evidence: any two snapshots
    /// that share at least one identifier in this set merge into one card.
    ///
    /// Format: `{providerID}:{scheme}:{value}` — e.g.
    /// `"codex:email:user@example.com"`, `"codex:sub:abc-123"`,
    /// `"claude:oauth-id:xyz789"`. The `providerID` prefix prevents
    /// cross-provider false merges. The `scheme` is informational —
    /// iOS doesn't parse it, only compares strings.
    ///
    /// **nil** (decode default for old Mac payloads) → iOS buckets the
    /// snapshot under a per-device legacy key, never merging it with
    /// other Macs. The user sees a "data not aligned, update other Mac
    /// to merge" hint in the affected provider card.
    ///
    /// **`[]` (empty array)** → same as nil. New Mac, but couldn't
    /// compute any identifier (e.g. user signed out mid-fetch). Treated
    /// as legacy to avoid grouping all anonymous snapshots together.
    ///
    /// Mac rule: this field is **additive only**. New schemes (sub,
    /// uuid, phone, …) are appended to the list while the legacy
    /// scheme stays in place for at least 3 minor releases. See §6.
    public let accountIdentities: [String]?
}
```

Backward-compat: encoder uses `encodeIfPresent`, decoder uses `decodeIfPresent`. Old iOS ignores the unknown key. Old Mac → new iOS reads `nil`. See Build 79 forward-compat invariant.

---

## 4. Mac-side identity computation

Each provider has a small helper that returns its current best-known identifier set. The function signature:

```swift
extension ProviderDescriptor {
    func currentAccountIdentities() -> [String]
}
```

### 4.1 Identifier ranking — primary is account UUID, not email

**Critical decision**: email is a *contact handle*, not an *account identifier*. It changes (Apple privaterelay rotation), aliases (multiple addresses for same account), and is shareable (team@company.com). Using it as the only identifier creates false-merge risk and false-split risk simultaneously.

**Primary identifier** for each provider is the upstream account's stable UUID/sub claim. **Secondary** identifiers (email, etc.) are added to the set only when known, but never relied on alone.

### 4.2 Tier-A providers

| Provider | Primary (always) | Secondary (when available) | Resulting identifier set |
|---|---|---|---|
| **Codex** | OpenAI organization account ID (from `/v1/organizations` or token claim) | email, Apple Sign-In `sub`, Google `sub` | `["codex:account:<id>", "codex:email:<email>", "codex:apple-sub:<s>", …]` |
| **Claude** | Anthropic OAuth `sub` claim (JWT) | primary email, Anthropic-side org ID when available | `["claude:oauth-sub:<sub>", "claude:email:<email>", "claude:org:<id>"]` |
| **VertexAI** | GCP user-id / service-account-id | email, GCP project numeric ID | `["vertexai:user-id:<id>", "vertexai:project-num:<n>", "vertexai:email:<email>"]` |

If the primary identifier can't be obtained (network failure, partial signin), Mac writes whatever secondaries it has + omits primary — better than nil. The legacy bucket is reserved for *no identifiers at all*.

### 4.3 Other 24 providers

Default to nil. Their cost path doesn't go through local pricing, and their accounts are typically single-Mac (no cross-Mac merging needed). If a future non-Tier-A provider needs cross-Mac merging, just add a `currentAccountIdentities()` impl to its descriptor.

### 4.4 Normalization rules (Mac-side, before write)

- All identifier values: lowercase + Unicode NFC normalize + trim whitespace
- Special characters in `value` (e.g., `:` / `|` / `/`): percent-encode (RFC 3986)
- Time-bounded values (JWT `exp`, session tokens): NEVER include
- Empty/whitespace-only values: omit (don't write `"codex:email:"`)
- Maximum identifier string length: 256 chars (truncate + log if exceeded; provider should fix at source)

### 4.2 Other 24 providers

Default to empty / nil. Their snapshots get a `legacy:<deviceID>:<provider>` per-device key in iOS, which means they stay per-device cards. That matches today's behavior — these providers' costs come from upstream APIs, so per-device is fine. We don't actively merge them.

If we later want cross-Mac merging for a non-Tier-A provider (rare), add identifiers to that provider's helper.

### 4.3 Schema evolution example

Mac 0.27 wants to migrate from email to a stable Apple-Sign-In `sub`. Concrete plan:

| Release | What Mac writes | Why |
|---|---|---|
| 0.23–0.26 | `["codex:email:..."]` | current state |
| **0.27** | `["codex:email:...", "codex:sub:..."]` | start of double-write |
| **0.28** | `["codex:email:...", "codex:sub:..."]` | still double-writing |
| **0.29** | `["codex:email:...", "codex:sub:..."]` | still double-writing (covers users who skipped 0.27/0.28) |
| 0.30 | `["codex:sub:..."]` | safe to drop email — every Mac that's been opened in the last 3 minor cycles wrote both forms |

iOS during the 0.27–0.29 transition window: 0.23 user has `[email]` set, 0.27 user has `[email, sub]`. They share `email` → same group ✓.

---

## 5. iOS merge — union-find over the identifier graph

`CloudSyncReader.mergeSnapshots` becomes:

```swift
// Build an identifier → snapshots-using-it index
var snapshotsByIdentifier: [String: [ProviderUsageSnapshot]] = [:]
var legacySnapshots: [(deviceID: String, snapshot: ProviderUsageSnapshot)] = []

for snapshot in providerSnapshots {
    if let identifiers = snapshot.accountIdentities, !identifiers.isEmpty {
        for identifier in identifiers {
            snapshotsByIdentifier[identifier, default: []].append(snapshot)
        }
    } else {
        // Old Mac OR new Mac couldn't compute identifiers → legacy bucket
        legacySnapshots.append((deviceID: ..., snapshot: snapshot))
    }
}

// Connected components via union-find: each snapshot is a node, edge if
// they share an identifier
var groups = UnionFind<ProviderUsageSnapshot>()
for (_, snapshots) in snapshotsByIdentifier {
    for i in 1..<snapshots.count {
        groups.union(snapshots[0], snapshots[i])
    }
}

// Each connected component = one merged provider card
let mergedCards: [ProviderUsageSnapshot] = groups.connectedComponents()
    .map { component in mergeSingleGroup(component) }

// Plus: each legacy snapshot is its own card (per-device)
let legacyCards: [ProviderUsageSnapshot] = legacySnapshots.map { ... }

// And: any L3 LinkageRecords from CloudKit further merge across groups
// (see §7)
```

**Properties:**

- O(N · I) where N = snapshots, I = avg identifier-set size. For our scale (a handful of Macs × a few providers × <5 identifiers each) this is negligible.
- Order-independent: same input always produces the same connected components.
- Adding a new identifier scheme on Mac never breaks iOS — iOS just sees more strings to potentially union on.

---

## 6. Deprecation policy (the institutional discipline)

**Rule:** Identifier strings, once published, are **persisted in the spec for ≥3 minor versions**.

### 6.1 Adding an identifier scheme

Free at any time. Just append to the set. Old iOS ignores unknown identifier strings; they only become useful when iOS sees a snapshot containing that identifier and can union via shared identifiers.

### 6.2 Removing an identifier scheme

Three-step ratchet:

1. Announce in the release notes for **N**: "Going forward, `email` will be deprecated in favor of `sub`. We will continue writing both for the next 3 releases."
2. **N, N+1, N+2**: write both `email` and `sub` in `accountIdentities`.
3. **N+3**: stop writing `email`. By this point, every Mac that has been opened in the last 3 minor cycles has written both forms at least once → iOS has had multiple opportunities to associate the two via union-find.

### 6.3 Renaming an identifier value

Don't rename — add a new scheme. The old scheme stays. Example: instead of changing `email` to `email_lowercased`, add a new `email_normalized:` scheme alongside the existing `email:` until 6.2 retires the old one.

### 6.4 Why 3 minors

The Mac update cadence in the wild has a long tail. Sparkle auto-updates run on app launch; a Mac that hasn't been opened in 6 weeks may be 2–3 minors behind. Three minors covers ≥3 months of normal usage — sufficient to catch >99% of users with at least one re-launch.

---

## 7. L3 fallback — user-confirmed LinkageRecord

When union-find produces multiple groups for what the user knows is one account (e.g. 6.2 wasn't followed and identifiers don't overlap), iOS gives the user an explicit affordance:

### 7.1 UI surface

When iOS detects ≥2 cards for the same `providerID` that share **no identifier**, surface a small inline button on each card:

> Two Codex cards detected. Same account?
> [Merge as same account] [Keep separate]

User picks "Merge as same account". iOS then:

1. Picks one identifier from each group as the "anchor" (preferring newest-snapshot identifier).
2. Writes a new `LinkageRecord` to CloudKit private DB with:
   ```swift
   struct LinkageRecord: Codable {
       let recordID: UUID                          // for SwiftData identity
       let providerID: String                      // "codex"
       let linkedIdentifiers: [String]             // anchor IDs from each group
       let confirmedAt: Date
       let confirmedFromDeviceID: String           // which iPhone confirmed
       let confirmedByUserAction: Bool             // always true (no auto-link)
   }
   ```
3. iOS reads all `LinkageRecord`s on every refresh and treats each list of `linkedIdentifiers` as a "virtual identifier" — adding an edge in the union-find graph between any snapshots that contain ANY of those identifiers.

### 7.2 Properties

- **User-driven**: never auto-merge across non-overlapping groups. The risk of false merges is the user's call.
- **Cross-iPhone**: LinkageRecord lives in CloudKit private DB → all iPhones sharing the iCloud account see it.
- **Self-correcting**: if the user changes their mind, an **Unmerge** action writes an inverse record (see §7.4).
- **Bounded**: only fires when union-find can't connect groups on its own. For 99% of upgrade scenarios this UI never appears.

### 7.4 Unmerge action

If a user accidentally merges two genuinely-different accounts via L3:

1. Long-press the merged card → "Unmerge accounts" menu item
2. iOS writes a `LinkageRecord` with `unmerge: true` flag listing the same `linkedIdentifiers` as the original merge
3. On next read, iOS applies un-merges *after* applying merges: the affected identifier pair is removed from the union-find graph as a virtual edge

Stored as additive records (never destructively delete the original LinkageRecord). Provides full audit trail via record history and lets cross-iPhone unmerge propagate naturally.

### 7.3 Why this isn't the primary mechanism

- Adds UX friction. Users shouldn't need to confirm what's obviously the same account.
- Adds CloudKit write surface. Writes are eventual-consistency and create concurrency edges (two iPhones confirm at the same time → both write LinkageRecords with overlapping but slightly different anchors).
- L1 + L2 (Mac writes set + iOS unions) cover the upgrade-window case. L3 is only for the **post-deprecation-violation** case.

---

## 8. Three-Mac-three-version regression test matrix

The test matrix that proves §2 + §5 + §6 hold:

| Test name | Mac A writes | Mac B writes | Mac C writes | Expected |
|---|---|---|---|---|
| `allOnSameVersion` | `[email:U]` | `[email:U]` | `[email:U]` | 1 group |
| `oneVersionBehind` | `[email:U]` | `[email:U]` | nil (legacy) | 1 group from A+B + 1 legacy bucket from C |
| `oneVersionAhead` | `[email:U]` | `[email:U]` | `[email:U, sub:S]` | 1 group via shared email |
| `transitionPeriod` | `[email:U]` (old) | `[email:U, sub:S]` (mid) | `[email:U, sub:S]` (newer-but-still-double-write) | 1 group via shared email |
| `harddropPolicyFollowed` | `[email:U, sub:S]` | `[email:U, sub:S]` | `[sub:S]` (post-deprecation) | 1 group via shared sub |
| `harddropPolicyViolated` | `[email:U]` | `[sub:S]` | `[sub:S]` | 2 groups (1 from A, 1 from B+C) — L3 prompt should trigger |
| `legacyAndNew` | nil (Mac 0.20.3) | `[email:U]` | `[email:U, sub:S]` | 1 group from B+C, 1 legacy bucket from A |
| `differentAccountsLookSimilar` | `[email:userA@x]` | `[email:userB@x]` | `[email:userC@x]` | 3 groups (genuinely different accounts) |
| `transitiveMerge` | `[email:U1]` | `[email:U1, email:U2]` (Mac sees user has 2 email aliases) | `[email:U2]` | 1 group transitively via Mac B |
| `legacyBucketIsolation` | nil | nil | nil | 3 separate per-device legacy buckets (no false merge) |
| `linkageRecordOverride` | `[email:U]` | `[sub:S]` | n/a | 2 groups initially → user confirms merge → LinkageRecord written → 1 group on next read |

Plus old-wire-compat tests (Mac 0.20.x payload decodes cleanly on new iOS, no crash).

---

## 9. iOS UI for the upgrade window

When iOS shows multiple cards for the same `providerID` that fall into different groups (or at least one is in the legacy per-device bucket), display an inline notice on each affected card:

> ⚠️ Another Mac (CodexBar 0.20.3) reports this provider differently. Update CodexBar there to merge automatically. — *Last seen 17 minutes ago*

Action button: "Update Other Mac" (deep-links to a help page with the Sparkle update flow).

Localized into 4 languages (en / zh-Hans / zh-Hant / ja). Hooks into the existing About & Sync "Update available" badge so the iPhone has a single source of truth on which Mac is stale.

---

## 10. Folding into Mac 0.23 + iOS 1.5.0

**Marketing versions stay locked** at Mac 0.23 / iOS 1.5.0 — non-negotiable.

Build numbers are a technical artifact for distinguishing builds (TestFlight requires uniqueness; local re-install needs a new bundle version to overwrite cleanly). They move as engineering needs, not as a "release" signal:

| Component | Now | After this work |
|---|---|---|
| Mac MARKETING_VERSION | 0.23 | 0.23 |
| Mac BUILD_NUMBER | 57 | 58 |
| iOS MARKETING_VERSION | 1.5.0 | 1.5.0 |
| iOS CURRENT_PROJECT_VERSION | 97 (prep, never uploaded) | 98 |
| Mac GH draft tag | `v0.23-mobile.1.3.1` | same tag, replaced asset on respin |

The iOS Build 97 prep in commit `25f17551` is replaced in place — never uploaded so no TestFlight collision. Reaching 98 as a single hop makes commit history match the artifact lineage.

---

## 11. Implementation order

1. ✅ Research/019 (this doc) — **user reviews**
2. Mac:
   - Add `accountIdentities: [String]?` to `ProviderUsageSnapshot` + Codable plumbing
   - Add `currentAccountIdentities()` to Codex / Claude / VertexAI provider descriptors
   - SyncCoordinator wires the identifier set into the outbound snapshot
3. iOS:
   - `CloudSyncReader.mergeSnapshots` switches to identifier-set union-find
   - Legacy bucket for nil/empty identifiers
   - LinkageRecord schema + reader (SwiftData entity)
4. iOS UI:
   - "Data not aligned" inline hint on affected cards
   - L3 user-confirmed merge prompt + write LinkageRecord
   - 4-lang i18n strings
5. Tests: §8 matrix as XCTest cases + 4 round-trip tests
6. Bump versions: Mac → 58, iOS → 98
7. Re-install Mac locally; replace iOS Build 97 prep with Build 98
8. User QA → upload TestFlight + re-spin Mac draft

Estimated: ~400 LOC code + ~250 LOC tests + this 200-line markdown.

---

## 11.5. Edge cases anticipated beyond the originally-raised 3-Mac scenario

The user raised "3 Macs / 3 versions / new fields added". Below are additional cases the architecture must (and does) handle. Each is annotated with how L1+L2+L3 covers it.

| # | Case | Coverage |
|---|---|---|
| A | User changes IdP (Apple → Google) on same provider account | Primary `codex:account:<id>` stays stable across IdPs; secondary IdP-sub identifiers come and go. L2 unions on shared primary. ✓ |
| B | Apple privaterelay email rotation | Primary `codex:account:<id>` unchanged; only the `email:` secondary changes. Old snapshots have old email, new have new — both share account ID. ✓ |
| C | Provider-side account merge (Anthropic merges two accounts) | On next refresh, Mac sees new merged account's identifiers. Old snapshots with old account ID stay separate (correctly, until they're cleaned by L1 ghost-records logic on Mac). ✓ |
| D | Mac offline for weeks (stale snapshot in CloudKit) | iOS unions on whatever identifiers the stale snapshot has. As long as ≥1 still appears in any current snapshot, connected. Stale-by-itself snapshot keeps appearing until that Mac comes online and writes fresh. ✓ |
| E | OAuth `sub` rotation by IdP | Email + account ID still overlap; sub-rotation just adds a new identifier without removing the old. ✓ |
| F | Multi-IdP login on different Macs (Apple on Mac A, Google on Mac B, same provider account underneath) | Both Macs write `codex:account:<id>` as primary → merge via primary even when secondary IdP-subs differ. ✓ |
| G | Provider account change on same Mac (sign out + sign in different account) | New account writes a new snapshot with new identifiers. Old snapshot with old identifiers gets cleaned by Mac-side L1 ghost-records logic (already shipped in P4 of the v0.23 work). ✓ |
| H | iCloud account switch on iPhone | CloudKit private DB is per-Apple-ID; switching iCloud accounts means a totally fresh DB, no carry-over of identifier state. ✓ |
| I | CloudKit zone deletion / rebuild | Same as fresh install — Macs re-write on next sync, iOS re-merges. ✓ |
| J | Privacy / PII | Identifier strings contain emails / OAuth subs (PII). CloudKit private DB is encrypted at rest + in transit. **No regression vs today** — `accountEmail` already was PII in cleartext. ✓ |
| K | Performance / size | 5 IDs × 27 providers × N Macs ≈ 7KB extra per snapshot. CKRecord limit is ~1MB. Negligible. ✓ |
| L | Wire encoding errors / corrupt bytes | `decodeIfPresent` fails gracefully → identifiers `nil` → legacy per-device bucket. Conservative degradation. ✓ |
| M | Concurrent L3 confirmations from two iPhones | Both write LinkageRecords. CloudKit accepts both. iOS reads union of all linkages. Idempotent. ✓ |
| N | User clicks L3 "merge" by mistake | Add **Unmerge action** in card UI: writes inverse LinkageRecord that nullifies the prior link for the affected identifier pair. ✓ (now in §7.4) |
| O | Mac in middle of sign-out (auth state half-torn-down) | Mac defers identifier write until auth state is settled OR writes whatever it currently has (partial set is fine). ✓ |
| P | Group / shared email aliases (`team@company.com` for 5 people) | Don't include shared aliases as identifiers — only stable upstream account UUIDs and the **primary** authenticated email. Group emails would never be the primary identifier returned by `currentAccountIdentities()`. ✓ |
| Q | Family Sharing | CloudKit private DB is per-Apple-ID, not per-family. Each Apple ID has its own merge. ✓ |
| R | Test/sandbox builds writing to production CloudKit | Existing entitlement (`com.apple.developer.icloud-container-environment = Production`) keeps dev signing pointed at Production. No leakage from dev/CI runs since they don't ship CloudKit-Production. ✓ |
| S | iOS reinstall | SwiftData cache wiped → re-derived from CloudKit on next sync. Linkage records persist (CloudKit-side). ✓ |
| T | Mac OS upgrade (14 → 15) | Keychain access stays. No regression. Verified during macOS 26 RenderBox upgrade earlier. ✓ |
| U | Provider rate-limited identifier fetch (`/v1/organizations` returns 429) | Mac falls back to writing only the secondary identifiers it cached. Logs the fetch failure. Eventually retries. Identifier set may temporarily lack primary — still functional via secondaries. ✓ |
| V | Snapshot size near CKRecord limit | Identifier set is bounded (max 5–8 strings of 256 chars = ~2KB). Compression already in place from earlier work. ✓ |
| W | Provider that legitimately HAS no stable account identifier | Falls back to legacy per-device bucket. User sees per-device cards (matches today's behavior for non-Tier-A). ✓ |

This list is **not exhaustive** — but it covers every category I can name (user lifecycle, network, encoding, concurrency, security, perf, schema). New cases that don't fit existing categories will be added to §11.5 as they're discovered, never silently bolted into the merge logic.

## 12. Out of scope (recorded so we don't accidentally do them)

- Auto-link by similarity (e.g. "emails are 85% similar"). User-driven only.
- Cross-provider merging (two providers reporting the same email). Different providers always stay separate.
- Auto-detect "obviously the same" via UI proximity tricks (icons, names). UX friction not worth the complexity.
- Migrating existing per-device snapshots to identifier-keyed records (one-time data migration). Not needed: snapshots are short-lived and re-derived from local Mac state on every refresh.
- Mac-side identifier propagation (Mac A reading Mac B's record on CloudKit and "back-filling" Mac B's identifiers). Mac talks only via writes — no Mac-Mac coordination.

---

## 13. Acceptance — design locked

All architecture decisions made; status `ready` for implementation. Locked items:

- [x] Schema-shape drift, schema-evolution, and hard-removal failure modes (§1)
- [x] Four design principles: iOS as merge authority, identity as set, additive-only writes, opaque-to-iOS (§2)
- [x] Wire-format addition: `accountIdentities: [String]?` via `decodeIfPresent` (§3)
- [x] Mac identity ranking: primary is provider account UUID, secondaries are email/IdP-sub (§4.1)
- [x] Per-Tier-A provider identifier set spec (§4.2)
- [x] Normalization rules (§4.4): lowercase + NFC + trim + URL-encode + length cap
- [x] iOS union-find merge with legacy per-device bucket fallback (§5)
- [x] Deprecation policy: identifier writes additive-only, ≥3 minor releases for any removal (§6)
- [x] L3 user-confirmed LinkageRecord with Unmerge undo (§7 + §7.4)
- [x] 11-case test matrix covering 3-Mac-3-version + edges (§8)
- [x] 23-case anticipated edge case audit (§11.5)
- [x] iOS upgrade-window UI hint (§9)
- [x] Build-number plan, marketing versions held at 0.23 / 1.5.0 (§10)

## 14. Implementation status — 2026-05-11 (iOS 1.5.3)

L1 + L2 shipped with Mac 0.23 / iOS 1.5.0 (Build 89). L3 + §9 inline hint
sat as "design-locked, never-built" through ~6 months. Discovered when the
user upgraded one of two Macs to 0.25.1 — old Mac on 0.23.6 wrote
`accountEmail=nil` for Codex while new Mac extracted `msxiao113@gmail.com`
(upstream `#869` Codex multi-account refactor began emitting accountEmail
for the same logical account that was previously anonymous). L1+L2's
legacy-no-identity bucket separated them, no UI to bridge → two Codex
cards on iOS for one Codex account.

### 14.1 What was built (iOS 1.5.3, commit pending)

| §  | File / type | Status |
|----|----|----|
| §3 | `Shared/Models/UsageSnapshot.swift` `ProviderUsageSnapshot.accountIdentities` | unchanged; already shipped |
| §3 | `Shared/Models/ProviderAccountLinkage.swift` | **new** — Codable record + `inverseUnmerge` helper |
| §3 | `Shared/iCloud/CloudConstants.swift` `providerAccountLinkageRecordType` | **new** — wire contract for CKRecord type name |
| §3 | `Shared/iCloud/CloudSyncManager.swift` save/fetch linkage methods | **new** — `saveProviderAccountLinkage` + `fetchProviderAccountLinkages`, stored in existing `DeviceProvidersZone` |
| §5 | `CodexBarMobile/iCloud/CloudSyncReader.swift` `mergeSnapshots(_:linkages:)` | **new param** — second pass applies LinkageRecord union edges after L1+L2 |
| §7 | `CodexBarMobile/Models/MultiAccountLinkageCandidate.swift` + detector | **new** — surfaces only the unambiguous (one-named + N-legacy) pairs |
| §7 / §9 | `CodexBarMobile/Views/ProviderUsageView.swift` linkage prompt section | **new** — inline UI on the legacy card; "Same account?" + "Keep separate" buttons; §9 hint string when legacy Mac's version is known |
| §7.4 | `ProviderUsageView` contextMenu "Unmerge Accounts" | **new** — long-press on a merged card writes inverse linkage |
| §7 | `CodexBarMobile/Models/SyncedUsageData.swift` `confirmLinkage` / `revokeLinkage` | **new** — local-apply + CloudKit write |
| §8 | `CodexBarMobileTests/AccountIdentityMergeTests.swift` §8.1–§8.10 | already shipped |
| §8 | `CodexBarMobileTests/LinkageRecordMergeTests.swift` §8.11 + §7.4 + §11.5 row M | **new** — 8 cases (override, unmerge, order-independence, concurrent idempotence, cross-providerID isolation, no-overlap no-op, Codable round-trip, backward-compat decode) |
| §8 | `CodexBarMobileTests/MultiAccountLinkageDetectorTests.swift` | **new** — 8 cases pinning detector rules (unambiguous emit, ambiguous skip, single-card skip, cross-provider isolation, deterministic ordering, app-version surfacing) |
| §9 | `Localizable.xcstrings` — 5 new keys × 4 langs | **new** — `Yes, same account`, `Keep separate`, `Unmerge Accounts`, `linkage-prompt-headline`, `linkage-prompt-detail`, `linkage-prompt-detail-with-version` |

### 14.2 Design-spec → code map

- §3 wire schema → `ProviderAccountLinkage` + `CloudSyncManager.makeLinkageRecord/decodeLinkage`
- §5 step 3b LinkageRecord application → `CloudSyncReader.mergeSnapshots` lines applying merge/unmerge after L1+L2
- §5 step 4 group reduction → unchanged from L1+L2 path (LinkageRecord just adds edges, doesn't change how groups become merged cards)
- §7.1 UI prompt → `ProviderUsageView.linkagePromptSection`
- §7.2 properties → all four (user-driven / cross-iPhone / self-correcting / bounded) preserved
- §7.3 "this isn't the primary mechanism" → still true: detector only emits when (one-named + N-legacy) AND user hasn't dismissed; ambiguous cases stay silent (see §7-A in the detector docstring)
- §7.4 Unmerge → `MultiAccountLinkageCandidate` unused for inverse; inverse uses `ProviderAccountLinkage.inverseUnmerge(...)` with set-equality key (`linkageKey` in `CloudSyncReader`) so order doesn't matter

### 14.3 Design deltas discovered during build

1. **§5 union-find ordering.** Originally documented as union-find first, LinkageRecord as a virtual edge. Built as: L1+L2 union-find first (step 3), then LinkageRecord edges (step 3b) BEFORE step 4 grouping. The unmerge ordering nuance — "applied AFTER merges" — needed a set-equality canonical key (`linkageKey`) because union-find can't tear apart unions directly. Inverse `unmerge=true` records skip the corresponding merge edge BEFORE step 4 runs, achieving the same net effect.
2. **§7.1 inline prompt anchor.** Spec says "surface a small inline button on each card". Built: prompt only on the LEGACY card (the side that's missing identifier data). Asymmetric UI is clearer for users — "this card looks like that one" reads better than "these two cards look alike". Named card stays clean.
3. **§7 ambiguity handling.** Spec lists §7.1 as the trigger when "iOS detects ≥2 cards for the same providerID that share no identifier". Build adds a stricter rule: only emit when there's EXACTLY ONE named card + N legacy cards. Two named cards (multi-account on the named side) is genuine multi-account and we can't guess which named card a legacy belongs to. Result: those cases stay 2+ cards on the UI with no auto-prompt; user has to upgrade the old Mac (the §9 path) rather than confirm via §7. Documented in `MultiAccountLinkageDetector` rule §7-A.
4. **§7 dismissal persistence.** Spec didn't address "what if user picks 'Keep separate'". Build: in-memory dismissal set on `ProviderListView` (`@State var dismissedCandidateKeys`). Re-evaluated on next launch (no persistence). Reasoning: candidates auto-dismiss once the legacy Mac upgrades. A persisted "no, never ask" would block the user from ever changing their mind.
5. **§9 wording.** Spec gave one English headline ("⚠️ Another Mac (CodexBar 0.X) reports this provider differently. Update CodexBar there to merge automatically."). Build separates §9 hint (the "0.X" version reference) from §7 merge prompt — both shown together in the same inline panel, with the version reference inline in the body text rather than as a separate row. Translates to all 4 languages.
6. **CKRecord zone.** Spec didn't pin it. Build: same `DeviceProvidersZone` as snapshot records. Avoids a second zone subscription + separate change-token logic; the existing per-provider zone subscription delivers linkage upserts as part of the same incremental delta stream.

### 14.4 Tests pinned

22 new test cases across two files, all passing:
- `LinkageRecordMergeTests` (8): §8.11 override, §7.4 unmerge + order-independence, concurrent merge idempotence, wrong-providerID no-op, no-overlap no-op, Codable round-trip, missing-unmerge backward-compat decode, `inverseUnmerge` helper.
- `MultiAccountLinkageDetectorTests` (8): unambiguous emission, multi-legacy fan-out, two-named-skip, zero-named-skip, single-card-skip, cross-provider isolation, app-version surfacing, deterministic ordering.

Plus the existing 16 `AccountIdentityMergeTests` (§8.1–§8.10 + identifier-synthesis edge cases) still pass.

### 14.5 What's still NOT built (deferred)

- **§7.1 multi-named picker.** When there are ≥2 named cards + ≥1 legacy, iOS could present a sheet to ask "which named card does this legacy belong to?" Deferred because: (a) the detector currently returns 0 candidates in this case so the user sees the cards but no prompt; (b) the case rarely fires in practice — most multi-Mac users have one account per provider; (c) implementing it correctly requires a separate UI surface, not the inline button. Documented as `MultiAccountLinkageDetector` rule §7-A future-work in the file's docstring.

Next: implementation. No further design review needed.
