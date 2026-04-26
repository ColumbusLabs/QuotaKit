# Ghost Records · Defense-in-Depth Analysis (post Build 94)

Status: Complete · 2026-04-26
Owner: CTO

---

## Context

User reported on iOS 1.3.0 (Build 93) right after both Macs upgraded to 0.20.3:
- Duplicate Codex cards (one "Hidden", one "Codex 2" fallback ordinal)
- Stale Perplexity card despite user disabling on Mac
- Cost Provider Share summing to 104%

Build 94 hotfix shipped same day with `SnapshotCache.dropOrphansAndStale(_:)`. User confirmed fix works on their devices.

User then asked for three rounds of expanded validation:
1. Comprehensive test coverage — full architectural matrix, not just immediate bug
2. Deep root cause analysis — go beyond the symptom, find related issues
3. CTO-level sweep — categorize the bug class architecturally

Plus code review. This document records all findings and follow-up actions.

---

## Round 1 · Test Matrix Expansion

`SnapshotCacheTests` grew from 24 cases pre-Build-94 → 29 (Build 94) → **50** (post-Round-1).

### New coverage

| Category | Tests added | Covers |
|---|---|---|
| Rule 1 edges | 4 | empty-string email, three-way alice+bob+nil, per-device boundary, real-email never touched even when stale |
| Rule 2 edges | 4 | exact 30-min boundary, real-email exempt, lone nil-email on offline device, multiple nil-email mixed freshness |
| Rule combination + legacy fallback | 2 | rules-stack interactions, all-filtered → legacy fallback path |
| Multi-device | 1 | independent per-device filtering (one dirty + one clean) |
| Integration paths | 3 | replaceFromFullFetch / replacePerProviderFromReplay / applyDelta — each verified to filter at read time |
| Edge cases | 4 | empty cache, future-dated lastUpdated (clock skew), only-real-email entries, Build 66 isGhost stacking, same-timestamp Rule 1 behavior |
| Defense-in-depth | 2 | legacy bucket filter applied; clean legacy passthrough |

All 50 tests pass on iPhone 17 Pro Simulator.

---

## Round 2 · Deep Root Cause Hunt

Two parallel investigation agents covered:
- **Agent A**: scan fork-owned codebase for the same write-only-no-delete pattern across the project
- **Agent B**: trace data flow from CloudKit/SwiftData → display, find paths that bypass the Build 94 filter

### Agent A findings — write-only-no-delete pattern is systemic

The codebase has **zero explicit record or zone deletion semantics**. Pattern recurs at 5+ critical sites:

| Site | Write path | Delete path? | Orphan risk | Severity |
|---|---|---|---|---|
| `Shared/iCloud/CloudSyncManager.swift` `pushSnapshot()` | Upsert by deviceID into legacy zone | NONE | Mac UUID reset → old deviceID record persists forever | HIGH |
| `Sources/CodexBar/Sync/SyncCoordinator.swift` `pushPerProviderRecords()` | Upsert by composite key into per-provider zone | NONE | Provider disable → record persists; identity drift → orphan | **CRITICAL — already user-reported** |
| `CodexBarMobile/Notifications/QuotaTransitionSubscriptions.swift` `setupIfNeeded()` | Per-(provider, state) `CKRecordZoneSubscription` | PARTIAL — only legacy IDs from Builds 42-53 | Provider deprecated upstream → subscription orphaned | MODERATE |
| `CodexBarMobile/Storage/SwiftDataBridge.swift` `upsert()` | Composite-key upsert with row-prune | CONDITIONAL — prunes only when row absent from incoming list | Identity drift → old row keyed by old composite never matches → never pruned | MODERATE-HIGH |
| Custom CloudKit zones (legacy + per-provider + 50 quota zones) | `modifyRecordZones(saving: ..., deleting: [])` | NONE | Provider removed upstream → `Quota-{providerID}-*Zone` persists | HIGH (server-side, silent) |
| `Localizable.xcstrings` (variant pattern) | New keys auto-added by Xcode | NONE | 162 of 261 keys are dead (no live code reference) | MINOR |

**Architectural observation**: every write site has a corresponding "lifecycle" event (provider disable / version upgrade / account switch / device wipe) that should trigger cleanup, but no site has it.

### Agent B findings — Build 94 filter coverage assessment

| Path | Bypasses filter? | Failure scenario | Severity |
|---|---|---|---|
| **1.** SwiftData cold-start hydrate → `legacyByDevice` | **YES (gap)** | First launch on 1.3.1 after upgrading from 1.3.0 with stale SwiftData rows shows orphans for 1-2 sec until network fetch overrides | **HIGH for upgrade users** |
| **2.** Mac legacy zone snapshot construction | NO | Mac only writes `enabledProviders()` — legacy is clean by construction | None |
| **3.** Cost view (`CostDashboardInsights`) data path | NO | Cost reads merged snapshot → already filtered | None |
| **4.** `mergeProviderEntries` cross-device sentinel (`""` vs `"_"`) | DOCUMENTED | Documented as in-function-only; doesn't escape to wire layer | LOW |
| **5.** `accountEmail` not merged via `latestNonNil<T>` | PARTIAL | Cross-version Mac drift (Mac 0.20.3 nil + Mac 0.23 email): merged identity flickers based on which Mac refreshed last | MEDIUM |
| **6.** `applyDelta(deletedRecordNames:)` is dead code | DEAD | Mac never calls `CKDatabase.deleteRecord` → inbound delete deltas can never be exercised; reliance on TTL only | MEDIUM |

**The most important finding**: Path 1 means a small subset of users (those upgrading 1.3.0 → 1.3.1 with stale local SwiftData) see orphans transiently. Build 94 alone doesn't cover them.

---

## Round 3 · CTO-Level Architectural Categorization

### Bug class

**"Eventually consistent distributed cache without lifecycle management."**

Three layers of mutable state:
1. **Mac local** (UserDefaults, OAuth tokens, in-memory provider state)
2. **CloudKit zones** (DeviceSnapshotsZone, DeviceProvidersZone, ~50 quota zones)
3. **iOS in-memory cache + SwiftData**

Writes flow in one direction (Mac → CloudKit → iOS). Each layer trusts the previous. Cleanup is everyone's responsibility, so it's no one's responsibility.

### Why this surfaced now

CodexBar started with a single zone and a single device. Single-zone × single-device + always-on providers = no lifecycle events that produce orphans. The architecture was correct for that workload.

Two recent changes broke the assumption:
1. **Build 59** introduced per-provider records (composite key by `accountEmail`) — added an identity dimension that depends on Mac's internal account-derivation logic
2. **Upstream v0.20** refactored Codex's account identity (`CodexAccountReconciliation` / `CodexIdentity` end-to-end) — changing how the composite key is derived between Mac versions

Together, these flipped the assumption "accountEmail is stable for a given Mac across upgrades" from a true invariant to a load-bearing assumption that nothing enforces.

### Layered defense

| Layer | What | Role |
|---|---|---|
| L1 — Mac authoritative cleanup | `SyncCoordinator.deleteRecord(for:)` on disable + `CodexAccountReconciliation` migration cleanup | Root cure. Eliminates orphans at source. **Planned in Research/016 v0.23 Phase 1.** |
| L2 — iOS read-time filtering | `SnapshotCache.dropOrphansAndStale(_:)` (Build 94) | Symptom fix. Hides orphans regardless of source. **Shipped.** |
| L3 — Defense-in-depth on legacy bucket | `SnapshotCache.filterSnapshotProviders(_:)` (Build 95) | Catches the upgrade-cold-start-hydrate gap. **Shipping.** |
| L4 — Wire-format forward compat | `decodeIfPresent` on every optional + Build 79 future-Mac field test | Prevents schema drift from breaking older clients. **Already in place.** |
| L5 — Observability | Settings → Developer Tools "Provider records vs displayed" diff panel | Future. Not yet built. Would catch new orphan classes early. |

Build 94 + 95 are L2 + L3. They don't fix the root cause (L1) but they make the user-visible problem invisible. L1 is correctly deferred to v0.23 because it requires Mac code changes and we don't want a Mac-only release for cleanup that L2/L3 already handles user-visibly.

### Other places this bug class lurks (not user-reported, future-proof)

Per Agent A findings, file as future tasks:

1. **iOS push subscription cleanup** — when upstream removes a provider in v0.24+, iOS keeps zombie subscriptions. Need to extend `setupIfNeeded()` to delete subscriptions whose provider IDs are no longer in `QuotaProviderList.providers`. (Bonus: surfaces a 50-zone CloudKit query on every cold start, so it's also a perf win.)
2. **Custom zone destruction** — when upstream removes a provider, `Quota-{providerID}-*Zone` should be torn down. Mac-side responsibility.
3. **Dead `Localizable.xcstrings` keys** — 162 dead keys today. Build 93 added a `state=new` audit; consider extending to "key referenced in code" audit too. Dev-tooling priority.
4. **`accountEmail` field merge** — CloudSyncReader.mergeProviderEntries should use `latestNonNil<T>` for accountEmail like Build 76 did for other optionals. Prevents identity flicker on cross-version multi-Mac. Small change, low risk.
5. **`applyDelta(deletedRecordNames:)`** — dead code path. Either keep as defense (Mac might emit deletes in future v0.23+ Phase 1) or remove. Keep is fine; it's documented.

---

## Code Review · `SnapshotCache.dropOrphansAndStale(_:)` + `buildDeviceSnapshots`

### Function signature & contract

```swift
static func dropOrphansAndStale(
    _ byComposite: [String: ProviderUsageSnapshot]
) -> [String: ProviderUsageSnapshot]
```

**Pure function**, takes dictionary, returns dictionary. No side effects, no reads from outer state. Easy to test in isolation. ✓

### Correctness review

**Rule 1 implementation** (lines ~290-310 of SnapshotCache.swift):
```swift
var byProviderID: [String: [String]] = [:]
for (key, provider) in byComposite {
    byProviderID[provider.providerID, default: []].append(key)
}
var keptKeys = Set<String>()
for (_, keys) in byProviderID {
    let hasRealEmail = keys.contains { key in
        guard let email = byComposite[key]?.accountEmail else { return false }
        return !email.isEmpty
    }
    for key in keys {
        guard let provider = byComposite[key] else { continue }
        let hasEmail = !(provider.accountEmail ?? "").isEmpty
        if !hasRealEmail || hasEmail {
            keptKeys.insert(key)
        }
    }
}
```

- ✓ Correctly groups by providerID
- ✓ Empty-string email handled equivalently to nil (both `hasRealEmail` check and `hasEmail` check use `!isEmpty` semantics)
- ✓ Single-entry providerID never trips the rule (`hasRealEmail` based only on the lone entry; if real-email present then it's the kept entry, if nil-email then we keep the lone entry)
- ✓ Three-way (alice + bob + nil): hasRealEmail=true, alice/bob have emails (kept), nil dropped. Verified by `rule1_threeWayDropsNilKeepsRealEmails` test.
- ⚠️ **Minor redundancy**: looks up `byComposite[key]?.accountEmail` twice per key. Could be refactored to one pass. Performance is O(n) anyway and n is small (< 30 typically). Not a real concern.

**Rule 2 implementation** (lines ~313-325):
```swift
guard let deviceFreshest = afterOrphanDrop.values
    .map({ $0.lastUpdated }).max()
else { return afterOrphanDrop }
let staleCutoff = deviceFreshest.addingTimeInterval(-30 * 60)
return afterOrphanDrop.filter { _, provider in
    let hasEmail = !(provider.accountEmail ?? "").isEmpty
    return hasEmail || provider.lastUpdated >= staleCutoff
}
```

- ✓ `deviceFreshest` from afterOrphanDrop (post Rule 1) — uses already-trimmed set as basis
- ✓ Real-email entries unconditionally pass (immune from TTL)
- ✓ Single-entry case: deviceFreshest = that entry → cutoff = entry - 30min → entry > cutoff → kept (verified by `rule2_loneNilEmailOnOfflineDevice`)
- ✓ Threshold rationale documented inline (30 min is wider than slowest known cadence)
- ⚠️ **Hardcoded 30 min** — could be a `static let staleThreshold` constant for visibility / configurability. Acceptable as inline.

**Two-step sequencing** — Rule 1 then Rule 2 — is correct because:
- Rule 1's output is the input to Rule 2
- Rule 1 reduces the set, so Rule 2 deals with cleaner data
- If we ran Rule 2 first, we'd compute `deviceFreshest` over data that includes orphans — could mis-pick freshest as a stale-orphan if it happened to be the freshest stale record. Rare but possible.
- Order matters; current order is correct.

### Design review

**Read-time vs write-time filtering** — design choice to filter at read (in `buildDeviceSnapshots`) rather than write (in `replaceFromFullFetch` / `applyDelta`). Pros:
- ✓ Cache holds raw zone state; debugging shows what's actually on the wire
- ✓ Incremental delta updates can never trim freshly-arrived peer records that briefly look "stale"
- ✓ Filter logic centralized (one site to change)
- ✓ When Mac resumes refreshing a previously-stale provider, deviceFreshest slides forward and the record returns automatically

Trade-off: filter runs on every `buildDeviceSnapshots` call. Cost is O(devices × providers-per-device). With max ~3 Macs × ~25 providers, that's 75 entries — sub-microsecond. Negligible.

### Defense-in-depth (Build 95)

`buildDeviceSnapshots` now applies the same filter to legacy-bucket fallback paths via `filterSnapshotProviders`. Catches:
- Cold-start hydrate from pre-Build-94 SwiftData (transient orphan flicker on first 1.3.1 launch)
- Any future scenario where Mac legacy zone has orphans (currently impossible by construction, but cheap to defend against)

Implementation has clean-path optimization: returns the original snapshot reference when no filtering happened, avoiding unnecessary allocation/reordering for the common case.

### Tests review

50 tests cover:
- ✓ Rule 1 happy + edge (4)
- ✓ Rule 2 happy + edge (4)
- ✓ Combined behavior (3)
- ✓ Multi-device (2)
- ✓ Integration with all 3 cache write paths (3)
- ✓ Edge cases (5)
- ✓ Defense-in-depth (2)
- ✓ Existing tests retained (~27)

Coverage gaps that could be added but are lower-priority:
- Property-based test for "every (n, k) input produces stable output across runs" — Swift Testing supports parameterized tests, could exercise random fixtures.
- Cross-device merge interaction (after `buildDeviceSnapshots` returns, `CloudSyncReader.mergeSnapshots` runs). Should test that filter output integrates cleanly with multi-device merge. Lower priority: already test-covered indirectly by existing CloudKitMergeTests.

### Code style nits

- ⚠️ Comment in `filterSnapshotProviders` says "returns the original snapshot reference" but Swift value types don't have references; clarification could be: "returns a snapshot equivalent to the input (no reordering / allocation churn)". Minor.
- ✓ Inline comments explain *why*, not *what*. Consistent with project style.
- ✓ All lengthy comments anchor to user-reported scenarios (Builds 66/76/77/93/94 referenced) for archeological context.

### Verdict

**Code quality: production-ready.** Comprehensive test coverage, well-documented design rationale, conservative defaults (real-email exempt from TTL, stricter rule order), clean separation of concerns (read-time filter, immutable input). 

Two pending follow-ups for v0.23 / iOS 1.5.0:
- L1 (Mac-side cleanup) — Research/016 Phase 1 follow-up tasks
- accountEmail latestNonNil — small cross-version fix

---

## Action Items (filed)

- [x] Build 94 ghost-records filter (shipped 2026-04-26)
- [x] Round 1 test matrix expansion (24 → 50 tests, this build)
- [x] Defense-in-depth: legacy bucket filter (Build 95, this build)
- [ ] **v0.23 migration**: Mac SyncCoordinator delete-on-disable + identity-drift cleanup (already in Research/016)
- [ ] **iOS 1.5.0**: extend QuotaTransitionSubscriptions cleanup to remove orphan subscriptions (Round 2 Agent A finding #3)
- [ ] **iOS 1.5.0** (low priority): `accountEmail` cross-version merge via `latestNonNil<T>` (Round 2 Agent B finding #5)
- [ ] **Future / dev-tooling**: extend i18n audit to also flag dead `Localizable.xcstrings` keys (Round 2 Agent A finding #6)
- [ ] **Future / observability**: Developer Tools panel showing "provider records in CloudKit vs displayed on iOS"
