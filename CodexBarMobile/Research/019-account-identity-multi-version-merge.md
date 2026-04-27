# 019 · Account Identity Multi-Version Merge — Research

**Status:** Phase 0 design for Mac 0.23 + iOS 1.5.0 (folded into the same release; no new marketing versions).
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

### 4.1 Tier-A (the three providers we already keep tight loops on)

| Provider | Identifier sources today | Identifier set today |
|---|---|---|
| **Codex** | OpenAI account email (from CLI token + dashboard fetch) | `["codex:email:<email>"]` |
| **Claude** | OAuth `sub` claim (when OAuth) **+** primary email when available | `["claude:oauth-sub:<sub>", "claude:email:<email>"]` (both when both known; just one if only one) |
| **VertexAI** | GCP project ID + account email (from `gcloud auth list`) | `["vertexai:gcp-project:<project>", "vertexai:email:<email>"]` |

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
- **Self-correcting**: if the user changes their mind, a future "Unmerge" action writes an inverse record. (Out of scope for first implementation; can be added later.)
- **Bounded**: only fires when union-find can't connect groups on its own. For 99% of upgrade scenarios this UI never appears.

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

Per user direction: **no new marketing versions**. Build numbers bump within current marketing tags:

| Component | Pre-this-work | After this work |
|---|---|---|
| Mac MARKETING_VERSION | 0.23 | 0.23 (unchanged) |
| Mac BUILD_NUMBER | 57 (locally installed) | **58** (new local install) |
| iOS MARKETING_VERSION | 1.5.0 | 1.5.0 (unchanged) |
| iOS CURRENT_PROJECT_VERSION | 97 (prep, not uploaded) | **98** (replaces 97 prep before upload) |
| Sparkle CFBundleVersion | 57.1.5.0 | **58.1.5.0** |
| Mac GH draft URL | `v0.23-mobile.1.3.1` | same tag, replaced asset |

iOS Build 97 was version-bumped in commit `25f17551` but never uploaded to TestFlight. We can either keep 97 (and push the identity-merge code on top) or jump to 98 to mark this as a distinct iteration. **Decision: jump to 98** so the in-flight changes are visually distinct from the original Build 97 prep.

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

## 12. Out of scope (recorded so we don't accidentally do them)

- Auto-link by similarity (e.g. "emails are 85% similar"). User-driven only.
- Cross-provider merging (two providers reporting the same email). Different providers always stay separate.
- Auto-detect "obviously the same" via UI proximity tricks (icons, names). UX friction not worth the complexity.
- Migrating existing per-device snapshots to identifier-keyed records (one-time data migration). Not needed: snapshots are short-lived and re-derived from local Mac state on every refresh.
- Mac-side identifier propagation (Mac A reading Mac B's record on CloudKit and "back-filling" Mac B's identifiers). Mac talks only via writes — no Mac-Mac coordination.

---

## 13. Acceptance for Phase 0

- [x] Schema-shape drift, schema-evolution, and hard-removal failure modes mapped (§1)
- [x] Wire-format addition is purely additive + decodeIfPresent (§3)
- [x] Mac-side identity computation per Tier-A provider documented (§4)
- [x] iOS merge as opaque-string union-find (§5)
- [x] Deprecation policy with 3-minor-version overlap rule (§6)
- [x] L3 user-confirmed LinkageRecord as fallback (§7)
- [x] Test matrix covering 3-Mac-3-version + edge cases (§8)
- [x] iOS upgrade-window UI hint specified (§9)
- [x] Version-bump plan within Mac 0.23 / iOS 1.5.0 (§10)
- [ ] User review (you).
