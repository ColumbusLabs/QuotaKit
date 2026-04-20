# 011 · Incremental sync v2 — in-memory cache, not SwiftData-backed (redo of P6 + P7)

**Status:** Design
**Supersedes:** Build 59's P6 + P7 (reverted in Build 60, commit `3644b4c4`)
**Date:** 2026-04-19
**Branch:** refactor-1.3.0

## What broke in v1

Build 59's P6/P7 tied the incremental-sync path to SwiftData. `refreshIncremental` applied the change-token delta to SwiftData and then read SwiftData back as "the per-provider-zone source of truth" for the priority merge.

The bug: SwiftData is not a clean mirror of any one zone. It accumulates rows from BOTH `SwiftDataBridge.upsert(deviceSnapshots:)` (called after every full fetch — seeds rows from both the new zone AND the legacy zone) and `SwiftDataBridge.applyPerProviderDelta` (called after every incremental push — only seeds rows from the new zone).

Asymmetric multi-Mac case:
- Mac A upgraded to P4 → writes to both zones.
- Mac B still on legacy → writes ONLY to legacy zone.
- Full fetch on iOS: SwiftData gets Mac A rows (via per-provider query → reconstructed) AND Mac B rows (via legacy query → reconstructed).
- Silent push from Mac A → incremental path runs.
- Incremental reads SwiftData → sees both Mac A and Mac B rows.
- `prioritiseByDevice` treats both as "per-provider" sources, so Mac B's stale row (last refreshed at full-fetch time) wins against the *fresh* legacy CKQuery for Mac B.
- User sees Mac B stale/flickering every time Mac A sends a silent push.

## v2 design principle

**Every zone gets its own cache slot, and the incremental path never consults a store that could contain rows from a different zone.**

Implementation: the cache lives in memory on the `SyncedUsageData` instance. SwiftData is kept for the P3 cold-start hydrate only — it is a read-through cache, not a zone mirror.

```
+------------------+  full fetch    +--------------------------+
|  CloudSyncManager| -------------> |  SnapshotCache           |
|  (iOS side API)  |  CKQuery both  |  .perProviderByDevice    |
|                  |  zones fresh   |  .legacyByDevice         |
|                  |                |  .deviceMetadata         |
|                  |  change-token  |                          |
|                  |  delta         |  mutates ONLY            |
|                  | -------------> |  .perProviderByDevice    |
+------------------+                +--------------------------+
                                              |
                                              | priority merge in-memory
                                              v
                                       SyncedUsageData.snapshot
                                              |
                                              v
                                          SwiftUI views
                                              |
                                              | P3 cold-start only
                                              v
                                       SwiftDataBridge.upsert
                                       (read by init next launch)
```

## SnapshotCache shape

```swift
@MainActor
struct SnapshotCache {
    // Per-provider zone data, keyed deviceID → composite(providerID, accountEmail)
    // → the provider snapshot from the envelope.
    var perProviderByDevice: [String: [String: ProviderUsageSnapshot]] = [:]

    // Legacy zone data, keyed by deviceID → the full monolithic snapshot.
    // Separate from perProviderByDevice so a silent push never touches it.
    var legacyByDevice: [String: SyncedUsageSnapshot] = [:]

    // Device-level metadata, keyed deviceID. Sourced from whichever zone's
    // update most recently arrived — updated independently from providers so
    // a legacy-only Mac still gets a metadata entry.
    struct Metadata {
        var deviceName: String
        var appVersion: String?
        var mobileVersion: String?
        var syncTimestamp: Date
        var notificationPushEnabled: Bool?
    }
    var deviceMetadata: [String: Metadata] = [:]
}
```

## Priority merge (pure over cache)

```swift
func buildMergedSnapshots(from cache: SnapshotCache) -> [SyncedUsageSnapshot] {
    var result: [SyncedUsageSnapshot] = []
    let allDeviceIDs = Set(cache.perProviderByDevice.keys)
        .union(cache.legacyByDevice.keys)

    for deviceID in allDeviceIDs {
        if let providers = cache.perProviderByDevice[deviceID], !providers.isEmpty {
            // Per-provider zone wins. Reconstruct SyncedUsageSnapshot from
            // cached per-provider entries + deviceMetadata.
            result.append(reconstruct(
                deviceID: deviceID,
                providers: Array(providers.values),
                meta: cache.deviceMetadata[deviceID]))
        } else if let legacy = cache.legacyByDevice[deviceID] {
            // Fall through to legacy.
            result.append(legacy)
        }
    }
    return result
}
```

Key invariant: `perProviderByDevice[deviceID]` is populated **only** by:
1. A full CKQuery against `DeviceProvidersZone`, or
2. An incremental delta from `DeviceProvidersZone`.

It is NEVER populated from legacy-zone data. So if Mac B has never written to the new zone, it simply won't have an entry — `legacyByDevice[macB]` wins by exclusion.

## Full-fetch flow (unchanged in spirit, explicit now)

`SyncedUsageData.fetchFromCloudKit`:
1. `CloudSyncManager.fetchPerProviderDeviceSnapshots()` — CKQuery on new zone, returns `[SyncedUsageSnapshot]` (one per device that wrote to new zone, reconstructed from envelopes).
2. `CloudSyncManager.fetchLegacyDeviceSnapshots()` — CKQuery on custom + default legacy zones, returns monolithic snapshots.
3. Reset `cache.perProviderByDevice` and `cache.legacyByDevice` to empty, then populate:
   - For each per-provider snapshot: `cache.perProviderByDevice[s.deviceID] = {composite: provider for each provider}`
   - For each legacy snapshot: `cache.legacyByDevice[s.deviceID] = s`
   - Metadata written for both (legacy populates metadata if per-provider didn't already).
4. Build merged snapshots from cache → update `self.snapshot` / `self.deviceSnapshots`.
5. Call `SwiftDataBridge.upsert(deviceSnapshots: merged)` so next cold start can hydrate (P3).

## Incremental-push flow (new)

`SyncedUsageData.refreshIncremental` (invoked by silent-push observer):
1. Load `CKServerChangeToken` for new zone from SwiftData (`SyncStateRecord`).
2. `CloudSyncManager.fetchPerProviderZoneChanges(since: token)` → `(upserted: [ProviderUsageEnvelope], deletedRecordNames: [String], newToken: ..., tokenExpired: Bool, zoneMissing: Bool)`
3. If `tokenExpired`: clear stored token, retry once with `nil` (full replay). Cache is fully rebuilt for new-zone side from this replay's envelopes.
4. For each envelope in `upserted`:
   - `cache.perProviderByDevice[envelope.deviceID][composite(envelope.provider)] = envelope.provider`
   - `cache.deviceMetadata[envelope.deviceID] = Metadata(from: envelope)`
5. For each recordName in `deletedRecordNames`:
   - Parse composite from recordName. Remove from `cache.perProviderByDevice[deviceID]`.
   - If device's dict becomes empty, remove the device entry. Metadata stays (legacy may still have a snapshot for it).
6. Persist new token to SwiftData.
7. `cache.legacyByDevice` is NOT touched. Devices that only exist in legacy keep their last-known legacy snapshot until the next full fetch.
8. Build merged snapshots from cache → update `self.snapshot`.

## Cold-start flow (P3, unchanged)

`SyncedUsageData.init`:
1. Try `SwiftDataBridge.readAllDeviceSnapshots(from: context)` (returns the last-persisted merged state — from last full fetch).
2. Seed `cache.legacyByDevice` with these rows (treat cold-start data as "legacy" bucket — conservative; real fresh data will override on next full fetch).
3. If SwiftData is empty, try KVS. If that's empty too, start blank.
4. Builds merged snapshots from cache → `self.snapshot` visible instantly.
5. `startObserving` fires `fetchFromCloudKit` in background → fresh data replaces the seed.

Seeding cold-start into the `legacyByDevice` bucket (not `perProviderByDevice`) is deliberate: we don't have authoritative zone-of-origin info for SwiftData rows, and treating them as legacy means the next fresh per-provider fetch will correctly overwrite them for any device that writes to the new zone. Conservative for old Macs.

## Multi-device trace

### Scenario 1: Mac A upgraded (P4), Mac B still on legacy, one iPhone (new)

**Full fetch:**
- New-zone CKQuery → returns envelopes for Mac A's providers → `cache.perProviderByDevice[macA] = {...}`.
- Legacy CKQuery → returns monolithic snapshots for both Mac A and Mac B → `cache.legacyByDevice[macA] = ..., cache.legacyByDevice[macB] = ...`.
- Merged: Mac A from per-provider (priority), Mac B from legacy. ✓

**Mac A pushes a change (silent push to iPhone):**
- Change-token delta returns Mac A's modified providers.
- `cache.perProviderByDevice[macA]` updated.
- `cache.legacyByDevice` untouched — Mac A's legacy entry stays, Mac B's legacy entry stays.
- Rebuild: Mac A from per-provider (fresh), Mac B from legacy (as of last full fetch — not fresher because iPhone doesn't subscribe to legacy zone pushes). ✓ Correct.

**Mac B pushes a change (via legacy zone, NO silent push to iPhone):**
- iPhone doesn't wake.
- Mac B's data stays stale on iPhone until next full fetch (app open or pull-to-refresh). ✓ Acceptable — this is the same as pre-v1 behavior, legacy zone has never had silent push.

### Scenario 2: Both Mac A and Mac B on P4

**Full fetch:**
- New-zone CKQuery → returns envelopes for both Macs → `cache.perProviderByDevice[macA] = {...}, [macB] = {...}`.
- Legacy CKQuery → both Macs write to legacy too (P4 is dual-write) → `cache.legacyByDevice[macA] = ..., [macB] = ...`.
- Merged: both Macs from per-provider (priority). ✓

**Mac A pushes a change:**
- Delta = Mac A's modified providers. 
- `cache.perProviderByDevice[macA]` updated.
- `[macB]` untouched — but since Mac B also writes to new zone, it'll send its own silent push when it changes. Each Mac's changes independently refresh that Mac's entry. ✓

### Scenario 3: Both Macs on legacy (pre-P4)

- `cache.perProviderByDevice` stays empty (zone doesn't exist, or queries return nothing).
- Both Macs in `cache.legacyByDevice`.
- Silent push never fires (subscription is on new zone, no writes there).
- Behavior identical to the app before P4 shipped. ✓

### Scenario 4: iPhone on v1.2.0 (58), Mac A on P4

- Old iPhone has no per-provider reader. Reads only legacy zone.
- Mac A writes to both; old iPhone sees Mac A's legacy copy.
- Any iPhone in this state ignores the new zone entirely. ✓

### Scenario 5: iPhone on v1.3.0 new (this build), Mac A still on 0.20.0 (no P4)

- Mac A writes only to legacy.
- iPhone's full fetch: per-provider query returns `.empty` or `.zoneNotFound`; legacy query returns Mac A's monolithic record.
- `cache.perProviderByDevice` stays empty; Mac A in `cache.legacyByDevice`.
- Merged = Mac A from legacy. ✓ No regression.

### Scenario 6: 2 Macs × 2 iPhones

Each device (Mac or iPhone) has its own `SyncedUsageData` cache. CloudKit is the shared source of truth. Mac writes → both iPhones receive silent push → each iPhone independently runs `refreshIncremental` against its own cache.

Two iPhones on same iCloud account:
- Both subscribed to `DeviceProvidersZone`.
- Mac A writes → Apple fans out the silent push to all subscribed devices.
- Each iPhone processes independently. No cross-iPhone coordination needed.
- ✓ Correct by construction.

## Edge cases

### Process restart

1. App killed → `SyncedUsageData` instance gone, cache lost.
2. App relaunch → `SyncedUsageData.init` hydrates from SwiftData into `cache.legacyByDevice` (conservative).
3. `startObserving` triggers a full fetch → cache rebuilt properly with both zones.
4. First silent push after relaunch → incremental path finds its stored change token in SwiftData, uses it.

### Change-token expiry

- Mac has been offline for 30+ days. Server may have GC'd the token.
- `fetchPerProviderZoneChanges(since: storedToken)` returns `tokenExpired: true`.
- Handler clears stored token, retries with `nil` → full replay of new-zone records.
- After replay, `cache.perProviderByDevice` is FULLY REBUILT from the replay (token-expired replay is equivalent to a full fetch for that zone).
- Caller should clear `cache.perProviderByDevice` before applying a nil-token replay to avoid retaining stale entries.

### Zone doesn't exist

- Happens for a brand-new iPhone where no Mac has yet written to the new zone.
- `fetchPerProviderZoneChanges` returns `zoneMissing: true`, `upserted: []`.
- Nothing applied to cache. Priority merge falls through to legacy. ✓

### Concurrent full-fetch and silent push

- `SyncedUsageData` is `@MainActor` — all method calls serialize on the main actor.
- `fetchFromCloudKit` and `refreshIncremental` both suspend (await CloudKit I/O). During suspension other main-actor code can run.
- Potential race: full-fetch reads both zones, is about to overwrite `cache.perProviderByDevice` with results. Meanwhile a silent push fires another `refreshIncremental` that also wants to mutate the same cache slot.
- Mitigation: wrap each refresh's cache-mutation step in a synchronous (non-suspending) block so both mutations happen as indivisible @MainActor actions. As long as we don't `await` between "here's the new data" and "apply to cache", the two refreshes can't interleave their mutations.
- Implementation: compute the new cache contents as a local value outside of mutation, then write to `self.cache` in a single synchronous statement.

### Silent push before first full fetch

- iPhone launches, receives a silent push BEFORE `startObserving`'s full fetch completes.
- `cache.perProviderByDevice` is empty (or seeded from SwiftData into legacy bucket only).
- Incremental delta arrives → applies to `cache.perProviderByDevice` → Mac A's devices appear.
- Mac B still absent (no legacy fetch yet either). Brief transient where user sees only Mac A.
- Full fetch completes → legacy fetched → Mac B appears.
- Transient window: milliseconds to seconds. Acceptable.

## Testing plan

- `SnapshotCacheTests`:
  - `apply delta populates perProviderByDevice, leaves legacyByDevice alone`
  - `delete recordName removes the right composite`
  - `priority merge: device in both → per-provider wins`
  - `priority merge: device only in legacy → legacy used`
  - `priority merge: device in neither → not returned`
  - `Mac A new + Mac B legacy — explicit scenario test`
  - `build from empty cache returns []`
- `CloudSyncManager.fetchPerProviderZoneChanges` continues to be integration-tested in future real-device smoke, not unit-tested (CloudKit is hard to mock).
- Full iOS xcodebuild test suite on simulator must stay green.

## Rollback plan

If Build 61 ships and a new multi-device issue surfaces: `git revert` the v2 commits. Build 60 state is the known-good baseline (P3 + P4 + P5 full-fetch-only).

## Out of scope

- Refreshing Mac B's legacy data in response to a Mac A silent push. Today Mac B only refreshes at full fetch (app open / pull-to-refresh). A future enhancement could periodically re-query legacy zone on a timer, but it's not in v2 scope.
- Sub-provider-level delta (each silent push still downloads the entire record for any changed provider). Not a scale issue at current payload sizes.
