# Mobile UX Performance Bundle

Status: done
Date: 2026-06-11

## Summary

Three user-perceivable optimizations found by auditing the iOS app's hot
paths: data freshness on app foreground, redundant Cost-dashboard
aggregation, and per-frame `DateFormatter` allocation during chart
scrubbing. No behavior is added beyond freshness; all three change *when*
existing work runs, not *what* is computed.

## 1. Foreground auto-refresh (staleness-gated)

**Problem.** The `scenePhase == .active` handler in `CodexBarMobileApp`
only refreshed `RemoteConfigStore`. Synced usage data refreshed at launch
(`startObserving`), on pull-to-refresh, and on silent push — but iOS
drops/defers silent pushes for backgrounded apps, so reopening the app
after minutes away showed stale numbers until a manual pull.

**Change.** `SyncedUsageData` records `lastRefreshCompletedAt` when a full
fetch or incremental delta finishes, and exposes `refreshIfStale()` gated
by the pure static `shouldAutoRefresh(lastRefreshCompletedAt:now:threshold:)`
(threshold 60 s, `SyncedUsageData.foregroundStaleThreshold`). The scene-phase
handler calls it on every `.active` transition.

**Decisions.**

- 60 s threshold: silent pushes already cover the seconds-scale window
  while active; the gate only needs to catch the backgrounded-long-enough
  case without re-fetching on every quick app switch.
- Recorded on *completion*, not start, so a coalesced refresh still counts
  as fresh when it lands.
- Cold start: the `.active` transition races `startObserving()`'s launch
  fetch; both funnel through `coalesceRefresh`, so the second caller awaits
  the in-flight fetch instead of starting a parallel one.
- Clock skew (last refresh in the future) is treated as "not stale" — a
  backwards clock jump must not cause a refresh storm.

## 2. Cost dashboard insights memo

**Problem.** `CostTab.currentInsights` was a computed property evaluated
2–3× per body evaluation (content + toolbar + share sheet), each time
re-running the O(providers × daily × breakdowns) aggregation — and, with
the Cost Window Ledger enabled, a SwiftData fetch + re-aggregation on the
main thread per access (windows up to 365 days).

**Change.** Memoized with the synchronous-resolve-on-miss +
`.onChange(of: key, initial: true)` store pattern already established by
`UtilizationHistoryView.resolvedPoints()`. The key
(`CostTab.insightsCacheKey`) covers: demo mode, `SnapshotIdentityKey`
(provider set + max `lastUpdated`), CWL toggle + window, and today's
wire-format day key (so "Today" totals flip at midnight —
`CostDashboardInsights.todayDayKey()` uses the same pinned formatter as
the aggregation itself).

**History note.** An earlier CostTab cache attempt used async `.task(id:)`
and was reverted because the first render was empty until the task fired
(UI-test failures; see the old note in `ViewCacheIdentityTests`). The
synchronous-resolve pattern keeps the first frame populated.

**Invalidation correctness.** The ledger is written inside
`applyFullFetchResults` in lockstep with snapshot publication, and the
ledger writer's dedup rule skips same-or-older `lastUpdated` rows — so any
ledger change implies a `SnapshotIdentityKey` change. No separate ledger
key component is needed.

## 3. Cached chart-axis formatters

**Problem.** `CostDashboardView.dailyAxisLabel` and
`UtilizationHistoryView.axisLabel` / `fullDateLabel` allocated a fresh
`DateFormatter` per call. Both run per axis label per chart re-render, and
`chartXSelection` scrubbing re-renders every drag frame, putting formatter
construction (locale table loads) on the 60 Hz path.

**Change.** Static cached formatter instances, following the
`CostLedgerService.utcDayKeyFormatter` precedent (read-only after
configuration, main-actor rendering only). The intentionally locale-free
`"M/d"` format and its Build 84/85 history comments are preserved
verbatim. `SyncCostSummary.iso8601DayKey` keeps its per-call factory — it
is documented as reachable off the main actor (thread-safety P0).

## Verification

- `ForegroundRefreshGateTests` — gate decision: nil last-refresh, fresh,
  threshold edge, stale, clock skew, custom threshold.
- `ViewCacheIdentityTests` "Hotspot 5" section — insights memo key
  semantics: stability, snapshot bump, CWL toggle/window, off-window
  irrelevance, day rollover, demo masking, nil/demo/real distinctness.
- Full unit bundle (440 tests / 36 suites) green on iPhone 17 Pro
  simulator; `./Scripts/lint.sh lint` clean including the i18n audit for
  the new release-notes string.
