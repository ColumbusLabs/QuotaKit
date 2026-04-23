# Research 015 · Mac-side Symmetry Audit (Upstream PR Material)

**Status**: Documented for upstream. No iOS-side code change.
**Date**: 2026-04-23
**Trigger**: Post-Build-80 "perfect-pass" audit; Agent A's parallel Mac-symmetry investigation, findings verified against source.

## Context

Between Build 77 and Build 83 the iOS client closed 8 bugs in a five-round systematic audit (cross-view semantic · multi-device merge · test distributions · boundary conditions · Codable resilience). Several of the bug classes are symmetric — they could just as plausibly exist on the Mac side since Mac owns the data production path (`SyncCoordinator`, UI layers) and iOS is a downstream consumer.

Agent A ran a mirrored 8-category check against the Mac codebase (`Sources/CodexBar/**`, `Sources/CodexBarCore/**`). This document records the findings. Because `Sources/` and `Tests/` belong to upstream (steipete/CodexBar), the fix path is **upstream PR, not local patch**. iOS-side defensive mitigations are called out where applicable.

## Findings

### 1. Non-deterministic `accounts.first` / `providers.first` selection

Two call sites pick "the first element" from a collection whose iteration order is not guaranteed. Visible symptom: multi-account / multi-provider users see the wrong selection after refresh.

**a. Codex account switcher** — `Sources/CodexBar/StatusItemController+SwitcherViews.swift:922`

```swift
self.selectedAccountID = selectedAccountID ?? accounts.first?.id ?? ""
```

If `accounts` comes from a Set or an unordered dict iteration, `accounts.first?.id` is non-deterministic. A user with two Codex accounts may see the menu-bar switcher jump between them across refreshes.

**b. Widget provider selection** — `Sources/CodexBarWidget/CodexBarWidgetProvider.swift:199, 218`

```swift
provider: providers.first ?? .codex  // line 199
let selected = providers.first { $0 == stored } ?? providers.first ?? .codex  // line 218
```

Same pattern. For a user with Codex + Claude both widget-eligible, the home-screen widget could display data for whichever provider CloudKit happened to iterate first on that fetch.

**Fix (upstream)**: sort `accounts` / `providers` by a stable key (id, displayName, lastUpdated) before taking `.first`. Or, for the widget, explicitly persist the user's chosen provider in `UserDefaults` and only fall back to a deterministic default.

**iOS-side mitigation**: N/A (iOS does not consume these Mac-local UI states).

### 2. `OpenAIDashboardModels.swift` dayKey TimeZone handling

`Sources/CodexBarCore/OpenAIDashboardModels.swift:93`:

```swift
formatter.timeZone = TimeZone.current
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.dateFormat = "yyyy-MM-dd"
```

Mac uses `TimeZone.current` to generate the daily cost `dayKey`. iOS (`SyncCostSummary+Today.swift` after Build 81) now also explicitly uses `TimeZone.current`. Both are in lockstep **as long as the user's Mac and iPhone are in the same timezone**, which is the common case.

**The latent edge case**: user in China running Mac in their office and iPhone while traveling in the US. The two devices emit different dayKeys for the same moment. iOS's "Today" card would miss today's Mac-written point and fall back to sessionCostUSD. Not crash, just silent drop-into-fallback.

**Status**: documented contract. Build 81 pinned iOS's side explicitly. Upstream-side change would be to always use UTC (which breaks "Today" semantics for users who expect their local day) or to encode the timezone into the dayKey. Both are user-facing decisions, not obvious wins.

**iOS-side mitigation**: none needed — today's behavior is "prefer daily[today], fallback to sessionCostUSD". If the user is cross-timezone, they still see the session number, just not the committed daily.

### 3. `SyncCoordinator` ghost records from nil-email placeholder

`Sources/CodexBar/Sync/SyncCoordinator.swift:300-301`:

```swift
private static func perProviderHashKey(providerID: String, accountEmail: String?) -> String {
    "\(providerID)|\(accountEmail ?? "_")"
}
```

When a provider first initializes, `accountEmail` may be nil (OAuth / cookies still loading). Mac pushes a per-provider envelope keyed by `"codex|_"`. Seconds later, after login completes, Mac pushes again with key `"codex|user@..."`. These go to **distinct CKRecords**; the `_` record is never overwritten.

Mac has `isGhostProvider` logic (`SyncCoordinator.swift` ~line 290) that skips the first push when the provider payload is "empty-shaped". iOS (`SnapshotCache.isGhost` — Build 66) has the same guard on the read side. Both guards work **today**. But the root architecture — keying by `accountEmail ?? "_"` — makes the ghost class possible.

**Fix (upstream)**: two options:
1. Don't push until `accountEmail` is known (delay the first emission).
2. Use providerID alone as the key and carry `accountEmail` as a separate CKRecord field; multi-account support then requires a different record structure.

**iOS-side mitigation**: already in place (`SnapshotCache.isGhost` filter). Build 68 hardened this.

### 4. Perplexity multi-account not split by `accountEmail`

`Sources/CodexBar/Sync/SyncCoordinator.swift:156-171`. The Perplexity envelope construction reads `snapshot?.perplexityUsage` directly — a single snapshot, no per-account partitioning. If a user has two Perplexity accounts on Mac, the one reported to CloudKit is whichever the Mac-side "active account" logic surfaced last.

By contrast, Codex has `providerID|accountEmail` composite keys exactly because the Codex side supports multi-account. Perplexity's Mac-side scrape was built for single-account first and hasn't grown this support yet.

**Fix (upstream)**: extend `PerplexityProvider` on Mac to enumerate all logged-in accounts and emit one envelope per `accountEmail`, matching the Codex pattern.

**iOS-side mitigation**: iOS's `mergeSnapshots` already keys by `providerID|accountEmail`, so the moment Mac starts emitting per-account Perplexity envelopes, iOS handles them correctly without change.

### 5. Upstream `UtilizationPaceStore` aggregates

Agent A did not find a Mac-side analogue of iOS's `UtilizationAggregateView` raw-avg-vs-peak bug — Mac's menu-bar UI displays the current session percentage directly (`snapshot.primary.usedPercent`), not a 30-day aggregation. The cross-view semantic mismatch class is iOS-specific because iOS is the one doing 30-day aggregation on the consumer side. ✅ no action.

### 6. Cross-version Codable

Mac writes with `CloudSyncConstants.makeJSONEncoder()` (iso8601 + sortedKeys per `SyncCoordinator.swift:41-45`). No bare `JSONEncoder()` found in Mac sync paths. ✅ no action.

### 7. Test distribution

Upstream Tests are orthogonal to our iOS test extensions (Build 80 + 83). We don't patch them.

## Action items for upstream PR (if we decide to send one)

Priority:

1. **P1 — Account switcher + Widget `providers.first`** (user-visible flicker in multi-account / multi-provider setups). Sort before selecting.
2. **P2 — Ghost record architecture** (`"_"` placeholder). Defer or re-architect the nil-email key. iOS's defensive filter means this is not user-breaking today, but the `_` records accumulate over the user's iCloud quota indefinitely.
3. **P2 — Perplexity multi-account emit per `accountEmail`**. Symmetric with Codex behavior.
4. **P3 — dayKey timezone contract**. Encode tz intent into the wire format or document the "same-timezone assumption". Today's behavior is acceptable for 99% of users.

## Why we're not patching Mac locally

Per project policy (CLAUDE.md):
- `Sources/` and `Tests/` are **read-only** for our iOS fork.
- Mac upstream is `steipete/CodexBar`. Our fork is `o1xhack/CodexBar`, iOS-only.
- Merging upstream changes back is part of our release cadence; we don't fork Mac divergence.

These findings wait until we either:
- Open upstream PRs against `steipete/CodexBar` (preferred if the fix is clean).
- Or decide the fix requires iOS-side defensive handling (already covered for ghost records).
