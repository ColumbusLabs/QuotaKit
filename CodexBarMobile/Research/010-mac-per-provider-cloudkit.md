# 010 · Mac Per-Provider CloudKit Record + zlib + Dual-Write (P4)

**Status:** Design
**Owner:** P4
**Branch:** refactor-1.3.0
**Date:** 2026-04-19

---

## Problem

Mac serialises every device's full usage state into a **single** `DeviceSnapshot` CKRecord in `DeviceSnapshotsZone`, plain-JSON inside the `payload` field.

- CloudKit hard-limits one record to **1 MB**. Measured at ~2 MB for 10 providers × 30 days of hourly utilization. Long-running Mac users already risk hitting it.
- Every push re-encodes and re-uploads the **entire** blob even when only one provider changed.
- iOS downloads the full blob on every sync and push delta, so its transfer cost scales with total state, not with what actually changed.

P4 solves all three by splitting into per-provider records in a new zone and compressing each record's payload with zlib. iOS will keep reading the legacy zone (P4 is Mac-only; the iOS side switches in P5).

## Invariants (what MUST keep working)

| Combination | Mac writes | iOS reads | Outcome |
|---|---|---|---|
| Old Mac × Old iOS | legacy zone only | legacy zone only | unchanged |
| Old Mac × New iOS | legacy zone only | both zones (P5) | new zone empty → uses legacy; same as today |
| **New Mac × Old iOS** | **both zones** | **legacy zone only** | **old iOS ignores new zone, still sees up-to-date legacy — no regression** |
| New Mac × New iOS | both zones | both zones, prefers new | per-provider incremental sync working end-to-end |

The third row is the compatibility contract for P4: **legacy zone must still be authoritative as long as any old iOS reader exists**. This is enforced by dual-write with legacy as primary.

## Schema

### New CloudKit zone

```
zoneName: "DeviceProvidersZone"
ownerName: (default — private database)
```

### New record type

```
recordType: "DeviceProviderSnapshot"
recordName: "{deviceID}|{providerID}|{accountEmail ?? "_"}"
```

The composite recordName matches iOS `ProviderSnapshotModel.compositeKey` exactly — one provider per Codex account per Mac collapses into one stable recordID, so repeated pushes are idempotent `save`s that overwrite in place.

### Fields (CKRecord)

| Field | CKRecordValue type | Queryable? | Purpose |
|---|---|---|---|
| `deviceID` | String | ✓ | CKQuery filter by device |
| `deviceName` | String | — | display (no server-side filter needed) |
| `providerID` | String | ✓ | CKQuery filter by provider |
| `providerName` | String | — | display |
| `accountEmail` | String (empty "" for nil) | ✓ | Codex multi-account disambiguation |
| `lastUpdated` | Date | ✓ Sortable | for "most recent per provider" queries |
| `encodingVersion` | Int64 | — | =1 (zlib JSON). Guards future format bumps |
| `payload` | Bytes | — | zlib-compressed `ProviderUsageEnvelope` JSON |

**Schema deploy:** CloudKit Production does not auto-promote record types from saves. Before new-zone writes can land in Production, the schema above MUST be deployed via CloudKit Dashboard → Schema → Deployments. Steps:
1. In Development env: Mac saves one sample record, Apple auto-creates schema
2. Dashboard → Deployments → **Promote to Production**
3. Only then will new-zone writes from Production Mac builds succeed

This is a **one-time, out-of-band step** before the user's Mac app upgrades to a build with P4 enabled. Until then the new-zone write will fail with `.invalidArguments`, **the legacy write still succeeds** (graceful degradation), and the user sees no regression.

## Payload shape

```swift
public struct ProviderUsageEnvelope: Codable, Sendable, Equatable {
    public let deviceID: String
    public let deviceName: String
    public let appVersion: String?
    public let mobileVersion: String?
    public let syncTimestamp: Date          // device-level sync time
    public let notificationPushEnabled: Bool?
    public let provider: ProviderUsageSnapshot  // the actual data
}
```

iOS (P5) reconstructs device-level `SyncedUsageSnapshot` by grouping envelopes by `deviceID`.

### Compression

`Compression.framework` → `COMPRESSION_ZLIB`. Measured ~10× reduction on realistic provider payloads (raw ~80KB → ~8KB).

```swift
public enum PayloadCompression {
    public static func compress(_ data: Data) throws -> Data
    public static func decompress(_ data: Data) throws -> Data
}
```

Format: 4-byte little-endian original size prefix + zlib-deflated bytes. The size prefix is required by `compression_decode_buffer` to pre-size the destination buffer.

## Write path

### Entry point stays the same

`SyncCoordinator.pushCurrentSnapshot()` keeps its current behavior for the legacy zone — encode the full `SyncedUsageSnapshot` and call `pushSnapshot(…)` exactly as before. Then, as an **additive** step, build envelopes and call the new per-provider writer.

```swift
// existing, unchanged
let result = await self.syncManager.pushSnapshot(synced)

// NEW: per-provider dual-write
let envelopes = providerSnapshots.map { ProviderUsageEnvelope(…, provider: $0) }
let changed = filterChanged(envelopes)
if !changed.isEmpty {
    let perProviderResult = await self.syncManager.pushPerProviderRecords(changed)
    // log failures but DO NOT clobber `result` — legacy write is authoritative
}
```

### Per-provider diff

The coordinator keeps an in-memory `[String: Int]` hash cache keyed by composite (`providerID|accountEmail`). Each push:
1. Encode `provider` (NOT the envelope — envelope's `syncTimestamp` changes every push and would defeat the diff) with a deterministic JSON encoder (sorted keys).
2. Hash → if cache miss or cache-value differs → include in `changed`.
3. On successful push, update cache.

On cold start the cache is empty → first push re-writes everything. That's exactly what we want (the Mac's process was just restarted, cache correctness cannot be assumed).

### CloudSyncManager new method

```swift
public func pushPerProviderRecords(
    _ envelopes: [ProviderUsageEnvelope]
) async -> SyncPushResult
```

- `ensurePerProviderZoneExists()` — same fetch-first pattern as `ensureCustomZoneExists()`.
- For each envelope:
  - Encode envelope → compress → set `payload`
  - Create or fetch CKRecord at composite recordID
  - Populate queryable fields (`deviceID`, `providerID`, `accountEmail`, `lastUpdated`, etc.)
- Batch via **`CKModifyRecordsOperation`** with `savePolicy = .changedKeys`, atomic per chunk of ≤200 records (CloudKit operation limit). Typical batch is ≤30 (real users rarely have that many providers).
- Conflict handling: `.serverRecordChanged` → re-fetch server record, overwrite fields, resave (same pattern as legacy writer).

### SyncPushing protocol

Extend with a default no-op so existing `MockSyncPusher` (and any other test doubles) don't break:

```swift
public protocol SyncPushing: Sendable {
    func pushSnapshot(_ snapshot: SyncedUsageSnapshot) async -> SyncPushResult
    func pushPerProviderRecords(
        _ envelopes: [ProviderUsageEnvelope]
    ) async -> SyncPushResult
}

extension SyncPushing {
    public func pushPerProviderRecords(
        _ envelopes: [ProviderUsageEnvelope]
    ) async -> SyncPushResult {
        .success // no-op default for test doubles / legacy impls
    }
}
```

New dedicated `SyncCoordinatorTests` test covers the real per-provider code path via `MockSyncPusher` that overrides the default.

## Rollout order

1. Ship Mac 0.20.1 with dual-write **disabled** (feature flag in `SettingsStore`, default off) → internal beta sanity check
2. Deploy CloudKit schema via Dashboard (one-off op)
3. Ship Mac 0.20.2 with dual-write **enabled** → new zone starts populating
4. P5 ships iOS dual-zone reader → iOS actually consumes new zone

For P4 this doc, we implement steps 1 + 3 together as one change (feature flag present but default ON once build green locally). User can gate before release.

## Tests

| Layer | Test |
|---|---|
| `PayloadCompression` | round-trip known input; decompress rejects malformed; empty Data edge case |
| `ProviderUsageEnvelope` | JSON round-trip; Codable back-compat (decode ignores unknown fields) |
| `SyncCoordinator` | `pushCurrentSnapshot` calls both `pushSnapshot` AND `pushPerProviderRecords`; second push with unchanged data calls `pushPerProviderRecords` with `[]`; one-provider change calls with exactly that one envelope |
| Mac build | `xcodebuild build -scheme CodexBar` clean |
| Mac smoke | run Mac app, check OSLog `cloudkit-sync` subsystem for both writes; check CloudKit Dashboard that both zones populate |

Real-device iOS test is NOT part of P4 — iOS code is untouched. iOS still reads legacy zone.

## Rollback

If P4 misbehaves after shipping:
1. Ship Mac 0.20.3 with dual-write kill-switch (`SettingsStore.perProviderZoneWriteEnabled = false`) — stops new-zone writes. Legacy zone unaffected.
2. Last resort: delete `DeviceProvidersZone` from CloudKit Dashboard. Apple recreates it on next write attempt if kill-switch re-enabled.

No iOS impact in either case (P5 not shipped yet).

## Out of scope (P5 / P6 / P7)

- iOS reading the new zone (P5)
- Change tokens / `CKFetchRecordZoneChangesOperation` (P6)
- Push-driven delta upsert (P7)

P4 is deliberately just "Mac writes per-provider records, compressed, dual-write-safe". Nothing else.
