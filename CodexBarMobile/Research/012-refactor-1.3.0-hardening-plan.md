# 012 · refactor-1.3.0 hardening plan (post-Release pass)

**Status:** Plan
**Date:** 2026-04-21
**Branch:** refactor-1.3.0
**Scope:** Everything in Release column post-Build 67

## Premise

All P1–P7, Mac 0.20.2 ghost filter, Build 66 + 67 fixes, and the Codex review subtask are now in Todoist Release. This plan does NOT add new features. It is a quality bar pass:

1. **Read** every line of new / modified Swift to surface bugs that slipped past the previous Codex review and through real-device verification.
2. **Audit extensibility**: walk through future scenarios (more providers, more devices, more accounts, schema evolution, scale) and confirm the current code degrades gracefully.
3. **Add scenario tests** — designed around USER-FACING POSSIBILITIES, not as mirrors of code paths. The test bar is "if a user does X under condition Y, does the app behave correctly," not "is this branch covered."

Per user directive: tests must explore *possibilities*, not just *what the code already does*. Coverage of behavior, not of lines.

## Files in scope

### Production code (Swift)

**Shared layer (CodexBarSync target — Mac + iOS):**
- `Shared/Models/ProviderUsageEnvelope.swift`
- `Shared/iCloud/CloudConstants.swift`
- `Shared/iCloud/CloudSyncManager.swift`
- `Shared/iCloud/PayloadCompression.swift`

**iOS app:**
- `CodexBarMobile/CodexBarMobile/Models/SnapshotCache.swift`
- `CodexBarMobile/CodexBarMobile/Models/SyncedUsageData.swift`
- `CodexBarMobile/CodexBarMobile/Storage/SwiftDataBridge.swift`
- `CodexBarMobile/CodexBarMobile/Storage/SwiftDataSchema.swift`
- `CodexBarMobile/CodexBarMobile/Storage/ModelContainerFactory.swift`
- `CodexBarMobile/CodexBarMobile/iCloud/CloudSyncReader.swift`
- `CodexBarMobile/CodexBarMobile/Notifications/DeviceProviderZoneSubscription.swift`
- `CodexBarMobile/CodexBarMobile/CodexBarMobileApp.swift`
- `CodexBarMobile/CodexBarMobile/ContentView.swift` (Cost / Usage tab edits)
- `CodexBarMobile/CodexBarMobile/Views/UtilizationAggregateView.swift` (P1 cache work)
- `CodexBarMobile/CodexBarMobile/Views/UtilizationHistoryView.swift` (same)
- `CodexBarMobile/CodexBarMobile/Views/CostShareCardView.swift`
- `CodexBarMobile/CodexBarMobile/Views/ProviderDetailView.swift`
- `CodexBarMobile/CodexBarMobile/Views/ProviderUsageView.swift`

**Mac app:**
- `Sources/CodexBar/Sync/SyncCoordinator.swift`

### Test code

- `CodexBarMobile/CodexBarMobileTests/SnapshotCacheTests.swift`
- `CodexBarMobile/CodexBarMobileTests/DualZoneReaderTests.swift`
- `CodexBarMobile/CodexBarMobileTests/Storage/SwiftDataBridgeTests.swift`
- `CodexBarMobile/CodexBarMobileTests/Storage/SnapshotIdentityKeyTests.swift`
- `CodexBarMobile/CodexBarMobileTests/Storage/ModelContainerFactoryTests.swift`
- `CodexBarMobile/CodexBarMobileTests/ViewCacheIdentityTests.swift`
- `Tests/CodexBarTests/SyncCoordinatorTests.swift`
- `Tests/CodexBarTests/PayloadCompressionAndEnvelopeTests.swift`

## Phase 1 · Code review pass

For each file above:

- Read every line.
- Check date encoding/decoding consistency (the Build 66 root cause). If any other JSON encoder is constructed without explicit `.iso8601`, flag.
- Check `try?` vs `try!`. Silent error swallowing on critical paths is the Build 65 root cause shape.
- Check optional unwrapping in error branches.
- Check @MainActor / nonisolated boundaries; especially anywhere `Task { ... }` or `Task.detached { ... }` is used.
- Check observer cleanup: `NotificationCenter.addObserver` without matching removeObserver.
- Check encoder/decoder dateEncodingStrategy for ALL `JSONEncoder()` and `JSONDecoder()` instances (the Build 66 lesson — there are likely more).
- Check `cache.replaceFromFullFetch` and similar for race conditions if any new caller is added later.

Output: a short list of findings under "Phase 1 findings" below as the work proceeds.

## Phase 2 · Extensibility audit

Walk through each scenario and confirm the code degrades gracefully (no crash, no data loss, no silent ghost):

### S1 · 10+ providers per device
- `pushPerProviderRecords` chunks at 200 records/batch — well above 10.
- `mergeSnapshots` is O(providers²) due to nested loops? Verify.
- `SnapshotCache.perProviderByDevice[deviceID]` → dictionary, O(1) lookup. Fine.
- No hardcoded provider count anywhere in shared code.

### S2 · Multi-account same provider per device
- `compositeKey = {providerID}|{accountEmail}` — unique per account.
- Per-provider zone records keyed by this composite. Multiple records per provider OK.
- iOS `mergeSnapshots` groups by `(providerID, accountEmail)` — keeps separate accounts.
- View layer: `ProviderListView` shows each provider entry separately. Codex multi-account becomes 2 cards (already handled in 1.2.0).

### S3 · 3+ devices (3+ Macs, 3+ iPhones)
- Each device has stable UUID via `stableDeviceID()`.
- CloudKit zone holds N devices' worth of records concurrently — fine.
- iPhone's `SnapshotCache.perProviderByDevice` keyed by deviceID, scales.
- iPhone subscribes once to zone — silent push fans out from all Macs.

### S4 · Schema evolution (encodingVersion bump)
- `decodeEnvelope` has `if version > providerPayloadVersion { return nil }`.
- Mac writes always use current version. Old iOS reads new version — drops record (preferable to mis-decode).
- Need: a path to bump version + back-fill. Document.

### S5 · CloudKit account switch
- `CKAccountChanged` notification triggers re-setup of subscriptions in AppDelegate.
- SwiftData store does NOT auto-clear on account change → may show old account's data briefly.
- KVS observes `accountChanged` event and switches snapshots.

### S6 · CKRecord 1MB limit (per-provider record approaches limit)
- Per-provider record holds ONE provider's data — much smaller than the legacy monolithic record.
- 730 utilization entries × ~50 bytes ≈ 36KB → well under.
- zlib reduces ~10× → <5KB typical.
- Need: monitor + warning if any single provider's record approaches limit.

### S7 · Token expired in middle of session
- `fetchPerProviderZoneChanges` handles `changeTokenExpired` → returns flag → caller clears + retries with nil.
- Edge case: what if BOTH expired AND second call also expires immediately? Currently retries once, doesn't loop.

### S8 · Concurrent silent pushes (Mac A push followed by Mac B push within 100ms)
- iPhone receives 2 `didReceiveRemoteNotification` → posts 2 `.codexBarProviderZoneDidChange`.
- 2 `Task` instances spawned, each calls `refreshIncremental`.
- Both await CloudKit fetch in parallel → race on cache mutation.
- Mitigation: `@MainActor` serializes mutations between awaits. But cache state could read stale between two interleaved updates.
- Need: serialize refreshIncremental via single in-flight task.

### S9 · iCloud quota exceeded
- `CloudSyncError(from: CKError)` maps to `.quotaExceeded`.
- iOS reads display this as error string, but doesn't UI-prompt user.
- Mac writes silently fail with quota — bandwidth wasted on retries.
- Need: surface quota errors more visibly?

### S10 · App backgrounded, silent push arrives, app foregrounded later
- `didReceiveRemoteNotification` fires regardless of app state (with fetch background mode).
- Refresh runs in background. View not visible.
- App foregrounded → already-up-to-date data shown.
- Should work. Verify via instrumentation later.

## Phase 3 · Test coverage gap analysis

Current test files + count:
- `SnapshotCacheTests.swift` — 18 cases
- `DualZoneReaderTests.swift` — 8 cases
- `SwiftDataBridgeTests.swift` — N (legacy + my additions)
- `SyncCoordinatorTests.swift` — 13 cases
- `PayloadCompressionAndEnvelopeTests.swift` — 5 cases

### Scenario gaps to cover

These describe USER-OBSERVABLE behaviors we want to assert, not internal code paths.

1. **Multi-account same provider** (Codex with 2 accounts on Mac A): SnapshotCache should keep BOTH as separate entries; merge layer should NOT collapse them.
2. **Account email transitions** (provider was nil-email then user logged in → email present): per-provider zone has 2 records for same providerID. Cache should prefer the one with non-nil email if both present (currently undefined — need to specify).
3. **Empty Mac (just installed)**: pushes nothing → iPhone should show "No Mac data found" not crash.
4. **iPhone with cached SwiftData but no internet**: should show cached state with error banner.
5. **iPhone with cached SwiftData but stale (>30 days old)**: should still display, fetch tries to refresh, surfaces age.
6. **CKRecord with future encodingVersion**: iPhone should not crash, silently ignore record.
7. **CKRecord with payload that fails to decompress** (corrupted bytes): iPhone should ignore that envelope, keep others.
8. **Per-provider record exists for device that's no longer in legacy zone**: priority merge should still work (per-provider wins, legacy just absent).
9. **Legacy record exists with deviceID matching a per-provider record**: per-provider wins (already tested).
10. **Ghost envelope arriving via incremental delta** (not just full fetch): should be filtered. (Currently tested.)
11. **Concurrent `refreshIncremental` calls** (silent push storm): only one should mutate cache at a time. Likely need a serial-task mechanism.
12. **Date encoding round-trip**: encode every type with Date fields, decode, assert equal. Prevent another Build 65-class regression.
13. **Token-expired retry that ALSO returns expired**: should not infinite-loop. Bail after one retry with error status.
14. **CloudKit account changed during a fetch**: should abort cleanly, not corrupt cache.
15. **prioritiseByDevice with one device that has a "_" composite key (legacy from v1 P6) and another with new format**: should both still surface.

### Tests to ADD (new files / cases)

- `SnapshotCacheTests` +cases for multi-account, account-email transitions, mixed-format keys, ghost via delta, concurrent apply.
- `SwiftDataBridgeTests` +cases for date round-trip on each model, encoding-version handling, prune-after-account-change.
- New file `CloudSyncManagerErrorPathsTests.swift` — uses fakes / mocks to trigger every CloudKit error code we map and verify the right `CloudSyncError` comes out.
- New file `SyncedUsageDataConcurrencyTests.swift` — exercises rapid back-to-back full + incremental fetches.

## Execution order

1. Phase 1: read all files, log findings inline below
2. Phase 2: walk scenarios, identify any code change needed
3. Phase 3: implement scenario tests, plus any code fix from Phase 2
4. Build + simulator test + device install + commit + push

Bump iOS to Build 68; no Mac change unless Phase 1/2 surfaces one.

## Findings log (filled in during execution)

### Phase 1 findings

(filled inline as code is read)

### Phase 2 findings

(filled inline as scenarios are walked)

### Phase 3 changes

(list of new tests + any code modifications)
