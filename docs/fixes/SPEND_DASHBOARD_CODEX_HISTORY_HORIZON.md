# Spend Dashboard Codex History Horizon (#160)

Routine/background spend collection must not silently force Codex history
scanning out to 365 days when a much smaller horizon is actually required.

> Correction status: this document was rewritten after an independent review
> of `bb23a60206ded8da220e44a3c95e74eec1641f21` found two remaining
> horizon-demand defects:
>
> 1. the supported 90-day dashboard range did not widen a configured 30-day
>    window (only All/365 was special-cased), and
> 2. a persisted All/90 selection reintroduced wide background scans while the
>    dashboard was closed, because persisted presentation preference was read
>    as active demand (and `startSharedSpendDashboardPublication` eagerly
>    materialized the controller so that the persisted selection participated
>    in the first background capture).
>
> The correction commit on this branch replaces persisted-selection demand
> with ephemeral visible-dashboard demand and generalizes the policy to all
> supported ranges. The original report sections below describe the corrected
> behavior.

## 1. Root cause

Two independent call sites escalated the Codex history horizon to the full
scan window (`SpendDashboardSource.scanDays == 365`) outside any explicit
extended-history demand:

- `UsageStore.startSpendDashboardCodexCostCatchUpIfNeeded` computed
  `historyDays = max(SpendDashboardSource.scanDays, settings.costUsageHistoryDays)`.
  Since `scanDays` is 365, the dashboard catch-up worker **always** scanned
  365 days, regardless of the configured window (default 30). Every routine
  background synchronization (`synchronizeSpendDashboardCodexCostCatchUp`,
  fired on launch via `applySharedSpendDashboardConfiguration` and on
  dashboard hide) therefore scheduled year-long filesystem scanning,
  parsing, aggregation, CPU, and disk I/O.
- `UsageStore.spendDashboardCodexHistoryDays` returned `scanDays` (365) as
  soon as the ambient primary worker converged **or** the account cache was
  independent of the ambient worker (managed/profile selections). That made
  the captured `SpendDashboardConfiguration.codexHistoryDays` (#159) 365 in
  exactly the steady-state routine case, so `makeRequest`/`load` scanned a
  year even though the visible window was 30 days.

The 365-day horizon was an implicit routine default, not a consumer-driven
requirement.

## 2. Routine path that escalated to 365

App launch with spend enabled → `startSharedSpendDashboardPublication` →
`observeSharedSpendDashboardConfiguration` →
`applySharedSpendDashboardConfiguration` →
`synchronizeSpendDashboardCodexCostCatchUp(accounts:)` with the dashboard
never opened. The catch-up worker then scanned 365 days via the
`max(scanDays, …)` floor, and once the primary worker converged, the
configuration horizon flipped to 365 as well, so snapshot loads followed.

## 3. Explicit history consumers

The horizon policy now treats an ACTIVE, visible dashboard range as the
consumer signal, for every supported range — not just All:

- Visible 90 with configured 30 requires 90 days of source coverage (a
  90-day model built on 30 days of history is wrong).
- Visible All (365) requires the full scan window.
- Visible 7 / 30 with configured 30 stays at the configured routine bound.
- Additionally, an explicitly configured 365-day cost window
  (`costUsageHistoryDays == 365`) yields 365 through the policy clamp — that
  is user intent, not escalation.

Persisted `SpendDashboardController.selectedDays` is **presentation
preference only**: it remembers 7/30/90/All across app launches so reopening
the dashboard restores the selection, but it is never by itself proof that a
long-range consumer is currently active. A persisted All selection with the
dashboard closed must not widen background collection.

Deliberately **not** a scan consumer: the token-activity loader still reads
at `activityDays` (365), but `loadCachedCodexTokenActivity` only slices the
already-scanned cache and can never trigger a filesystem scan, so it costs
no I/O.

## 4. Horizon-selection policy

One authority, `SpendDashboardSource.requiredCodexHistoryDays(configuredWindowDays:activeDashboardRequestedDays:)`
(`Sources/CodexBar/SpendDashboardController.swift`):

```swift
routine = clamp(configuredWindowDays, 1...scanDays)
if activeDashboardRequestedDays == nil: required = routine
else: required = max(routine, clamp(activeDashboardRequestedDays, 1...scanDays))
```

Demand representation (ephemeral, not persisted):

- `SpendDashboardController.isHistoryDemandActive` is a stored visibility
  flag, false by default (declared in the class body because Swift stored
  properties cannot live in extensions).
- `SpendDashboardController.activeRequestedHistoryDays: Int?` is a computed
  same-file extension value: `isHistoryDemandActive ? selectedDays : nil`.
- `SpendDashboardPane.onAppear` calls
  `activateHistoryDemandForVisibleDashboard()` (persisted 90 activates 90,
  persisted All activates 365); `onDisappear` calls
  `deactivateHistoryDemand()` before the routine background catch-up
  synchronization; `selectDays` while active automatically follows
  `selectedDays` because demand is derived from it.
- `UsageStore.spendDashboardCodexHistoryDays` reads only
  `sharedSpendDashboardControllerStorage?.activeRequestedHistoryDays`
  (nil when the dashboard was never visible), never `selectedDays`.
- `UsageStore.spendDashboardExtendedCodexHistoryRequired` names the
  `activeRequestedHistoryDays == scanDays` condition for tests and future
  call sites.
- `startSharedSpendDashboardPublication` no longer eagerly materializes the
  controller; background publication never turns a persisted selection into
  active demand. The controller is still materialized lazily on the first
  `applySharedSpendDashboardConfiguration`, but materialization alone is
  inert.

`SpendDashboardSource.configuration(...)` captures the policy value into
`SpendDashboardConfiguration.codexHistoryDays` exactly as #159 established;
`makeRequest` consumes the captured value and never overrides it.
`startSpendDashboardCodexCostCatchUpIfNeeded` scans exactly
`spendDashboardCodexHistoryDays`; the old `max(scanDays, …)` floor stays
removed. The horizon stays inside the worker scope signature, so a horizon
change rotates the scope and stale narrower work cannot satisfy a broader
scope (context-freshness check compares against the same policy value).

## 5. Cached / superset history handling

No new retention machinery: the existing scanner semantics already handle
directionality. `CostUsageScanner.requestedWindowExpandsCache(range:cache:)`
returns false when the requested window is inside the cached window, so
established 365-day cache data satisfies a 30-day request without rescanning
(no destructive truncation of cached history). Conversely, 30-day data never
satisfies a broader request: the horizon is part of the worker scope
signature and of #159 hard source ownership, so narrowing→broadening restarts
work under the broader scope.

Directionality is proven two ways:

- Test 6 (`scanner cache compatibility is directional across horizons`)
  exercises the real scanner seam directly: a narrow or mid request against
  an established 365-day cache and a 90-day cache returns `false` (no
  expansion), while 365-vs-30, 90-vs-30, and 365-vs-90 return `true`.
- Test 4 proves the worker-level close transition: with an established cache,
  closing All re-evaluates at 30 with zero scan passes. Test 5 proves a fresh
  90→30 close schedules `[90, 30]` and never a hidden 365. The
  30-cannot-satisfy-365 direction is covered by the existing #159 liveness
  test that observes loader horizons `[30, 365]`.

## 6. #159 hard-scope preservation

Untouched: `codexHistoryDays` remains in `sameSourceOwnership` and remains
excluded from display-only changes. `SpendDashboardLoadRequest` still
consumes `configuration.codexHistoryDays`. All 16
`SpendDashboardLoadLivenessTests` pass unmodified, including 30→365
invalidation, gated-builder stale-scope death, same-horizon coalescing, and
presentation-only no-work. Transitions such as 30→90 and 90→365 use the same
safe hard-scope rules already proven for 30→365.

## 7. Files changed

- `Sources/CodexBar/SpendDashboardController.swift` — policy semantics
  generalized to `max(routine, active)` for all ranges; added
  `isHistoryDemandActive` plus the same-file extension exposing
  `activeRequestedHistoryDays`, `activateHistoryDemandForVisibleDashboard()`,
  and `deactivateHistoryDemand()`; reworded the stale `codexHistoryDays` doc
  comment; documented why the activity loader keeps the full depth
  (read-only slice, never a scan). The class-body lint budget (800 lines,
  SwiftLint `type_body_length`) is why the demand surface lives in a
  same-file extension.
- `Sources/CodexBar/UsageStore+SpendDashboardCodexCostCatchUp.swift` —
  `spendDashboardCodexHistoryDays` reads active demand through the policy;
  `spendDashboardExtendedCodexHistoryRequired` reads active demand, not
  persisted selection; worker scans the policy horizon; freshness check
  compares against the policy value.
- `Sources/CodexBar/UsageStore+SpendDashboardPublication.swift` — removed
  the eager controller materialization and the comment claiming persisted
  All must control launch-time background scope; lazy materialization in
  `applySharedSpendDashboardConfiguration` is inert.
- `Sources/CodexBar/PreferencesSpendDashboardPane.swift` — `onAppear`
  activates demand before the first visible source request; `onDisappear`
  deactivates demand before routine catch-up; the picker binding simply calls
  `selectDays` (which updates demand automatically while active).
- `Tests/CodexBarTests/SpendDashboardCodexHistoryHorizonTests.swift` —
  rewritten: policy units for all ranges, Test A (routine bounded), Test 1
  (visible 90), Test 2 (persisted All closed does not widen background),
  Test 3 (opening persisted All activates 365), Test 4 (closing All returns
  to 30 without a 365 rescan), Test 5 (visible 90 → close → 30), Test 6
  (real scanner cache-directionality seam).
- `Tests/CodexBarTests/UsageStoreSpendDashboardCodexCostCatchUpTests.swift`
  — unchanged in this correction (worker behavior it covers is still the
  configured-window policy it asserts).
- `Sources/CodexBar/UsageStore.swift` — no net change after the correction
  (an intermediate store-level demand property was removed; the file sits at
  exactly 1500 non-comment lines and must not grow).

#161 was not implemented. No dashboard redesign, no snapshot/model-architecture
refactor, no main-actor changes, no Phase 1 rolling-window changes.

## 8. Targeted tests and results

All commands run in this worktree; no full suite was run.

- Base verification on `bb23a60206ded8da220e44a3c95e74eec1641f21`: a temporary
  probe suite (since deleted) reproduced both defects — the policy returned
  30 for `configured 30 + requested 90`, and a materialized controller holding
  a persisted All selection made both `spendDashboardCodexHistoryDays` and
  `SpendDashboardSource.configuration(...).codexHistoryDays` return 365 while
  the dashboard was closed. The correction tests fail on the reviewed base
  and pass after the fix.
- `swift test --filter SpendDashboardCodexHistoryHorizonTests` — 11 tests
  pass. Observed horizons:
  - routine bounded (Test A): configuration 30, request 30, scanning loader
    `[30]`
  - visible 90 with configured 30 (Test 1): configuration 90, request 90,
    loader `[90]`
  - persisted All, dashboard closed (Test 2): configuration 30, request 30,
    worker advance `[30]`
  - opening persisted All (Test 3): configuration 365, request 365, loader
    `[365]`
  - closing All with established cache (Test 4): policy 30, worker advance
    `[]` (no corpus rescan)
  - visible 90 → closed (Test 5): worker advance `[90, 30]`, no hidden 365
    request
  - scanner cache-directionality seam (Test 6): narrow/mid inside wide or
    mid caches `false`; 365-vs-30, 90-vs-30, 365-vs-90 `true`
- `swift test --filter 'SpendDashboardCodexHistoryHorizonTests|SpendDashboardLoadLivenessTests|UsageStoreSpendDashboardCodexCostCatchUpTests|SpendDashboardControllerTests'`
  — 69 tests across 6 suites pass (the filter also matched
  `SpendDashboardRequestTimeTests` and `SpendDashboardControllerRevisionTests`).
  This includes all 16 #159 liveness tests and the 18 catch-up tests.
- `swift build` — complete.
- `swiftlint lint --strict` on the 5 changed Swift files plus the untouched
  `UsageStore.swift` (verified here because it sits exactly at the
  `file_length` limit): `Found 0 violations, 0 serious in 6 files.`
- `swiftformat --lint` on the same files: only the 7 pre-existing
  `wrapIfStatementBodies` notes in `SpendDashboardController.swift` (2) and
  `PreferencesSpendDashboardPane.swift` (5); verified identical on the base
  SHA with the same tool (homebrew formatter version drift, not introduced
  here). Full `./Scripts/lint.sh lint` was intentionally not run (pinned-tool
  installer + full-repo passes are disproportionate for this scope; per-file
  checks above cover the diff).

Broader suites (`make test`, `./Scripts/test.sh`, full Xcode plan) were
intentionally omitted: the change is scoped to the dashboard horizon, and
all directly affected suites pass.

## 9. Self-review Loop 1 — demand lifecycle trace

| Scenario | Persisted `selectedDays` | Active demand | Configuration `codexHistoryDays` | Worker requested horizon | Corpus scan required |
| --- | --- | --- | --- | --- | --- |
| Launch, dashboard never opened | 30 default | nil | 30 | 30 | bounded 30 (or cache-compat) |
| Launch, persisted 90, closed | 90 | nil | 30 | 30 | bounded |
| Launch, persisted All, closed | 365 | nil | 30 | 30 | bounded |
| Open with persisted 90 | 90 | 90 | 90 | 90 | 30→90 if cache is 30 |
| Open with persisted All | 365 | 365 | 365 | 365 | 30→365 if cache is 30 |
| Pick 30→90 while visible | 90 | 90 | 90 | 90 | expansion only if cache narrower |
| Pick 90→All while visible | 365 | 365 | 365 | 365 | expansion only if cache narrower |
| Close from All | 365 | nil | 30 | 30 | none if 365 cache established |
| Reopen (persisted All) | 365 | 365 | 365 | 365 | none if 365 cache established |

No discrepancies found. Additional review findings:

- Q: Can routine background activity still request 365 accidentally? A: No.
  Every Codex scan producer (`spendDashboardCodexHistoryDays`, catch-up
  worker, `makeRequest`, `load`) flows from the single policy, and the only
  widened input is `activeRequestedHistoryDays`, which is nil unless the pane
  is/was visible.
- Q: Is every 365 request tied to explicit need? A: Yes — visible All,
  configured-365, or read-only cache slicing.
- Q: Is every 90 request provisioned? A: Yes — visible 90 yields 90 through
  `max(routine, active)`; Test 1 scans `[90]`.
- Q: 365→30 reuse without rescan? A: Yes via
  `requestedWindowExpandsCache` directionality (Test 6) plus worker-level
  Test 4 and the existing #159 365→30 behavior. A horizon narrowing still
  rotates the worker scope signature and re-evaluates catch-up statuses —
  cheap manifest reads, not a rescan.
- Q: 30 falsely satisfying 90/365? A: No — scope signature + #159 ownership;
  Test 5 + Test 6 + the existing 30→365 liveness test.
- Q: #159 intact? A: Yes — ownership/liveness code untouched; 16/16 pass.
- Q: Power/thermal/cancellation/checkpoint preserved? A: Yes — untouched.
- Q: New polling/retries/scans? A: No. Demand transitions ride the existing
  `@Observable`/`withObservationTracking` configuration observation and the
  existing pane lifecycle; no new tasks, timers, or observation loops.
- Correction review fix during development: an intermediate store-level
  `spendDashboardActiveRequestedHistoryDays` property pushed
  `UsageStore.swift` past SwiftLint's `file_length` warning (1500) and the
  two demand methods pushed `SpendDashboardController` past
  `type_body_length` (800). The final mechanism stores one boolean in the
  class and derives the rest in a same-file extension, keeping both files
  lint-clean without suppressions.

## 10. Self-review Loop 2 — CPU regression review

Searched all #160-related paths for `365`, `scanDays`, `selectedDays`,
`spendDashboardCodexHistoryDays`, active demand/visibility, and catch-up
synchronization:

- No routine background path interprets a persisted range as active demand:
  `selectedDays` appears only in the controller (persistence, model build,
  demand derivation) and in the pane's picker display.
- No supported visible range is under-provisioned: 7/30 stay bounded, 90
  provisions 90, All provisions 365 (`max(routine, active)` for all ranges).
- No independent/managed/profile worker bypasses the policy: both the
  primary-shared and independent account paths call
  `startSpendDashboardCodexCostCatchUpIfNeeded`, which reads
  `spendDashboardCodexHistoryDays`; `synchronizeSpendDashboardCodexCostCatchUp`
  passes only configured history to the primary worker and the policy value to
  the dashboard worker.
- No visibility polling was added; activation/deactivation is driven by the
  existing SwiftUI `onAppear`/`onDisappear`.
- No parallel scanning was added; the worker machinery is unchanged.
- Low-power/thermal/cancellation/checkpoint behavior untouched.

Diff-scope review: `git diff bb23a60206ded8da220e44a3c95e74eec1641f21..HEAD`
contains only the #160 active-demand/lifecycle policy, the narrow pane
lifecycle integration, the horizon tests, and this report. No #161 code, no
Phase 1 files, no unrelated #159 modifications, no broad formatting.

## 11. #161 confirmation

#161 was not implemented in this phase. No code or tests reference it.

## 13. Final independent-review correction (shared primary + close re-scope + generic arbitration)

Independent review of `46639580d1601741870cdc901f1061a1d13bc86d` found two
remaining #160 gaps; this section corrects the record (in particular the
§9–§10 statements claiming every scan producer already flowed from the
single policy — the shared-primary worker did not).

1. **Shared-primary worker ignored active demand.** Both dashboard entry
   points (`synchronizeSpendDashboardCodexCostCatchUp` and
   `startSpendDashboardCodexCostCatchUpIfNeeded`) routed the
   `codexCostCatchUpUsesPrimaryCache == true` path to
   `startCodexCostCatchUpIfNeeded(requestedHistoryDays:
   settings.costUsageHistoryDays)`. Configured 30 + visible 90 therefore
   scanned the primary cache at 30 while the dashboard request was 90;
   visible All scanned primary at 30 while the request was 365. Both now
   pass `spendDashboardCodexHistoryDays` (`max(routine, active)`) when the
   dashboard shares the primary cache, so closed → routine, visible 90 →
   90, visible All → 365.
2. **Existing tests missed the primary-cache path.** The #160 suite used
   synthetic `.profileHome` accounts, which exercise the independent worker
   only. New Tests A/B use a live-system account with an ambient
   `tokenCostScope` (so `codexCostCatchUpUsesPrimaryCache == true`),
   intercept the primary `advanceCodexScanCatchUp` history argument, and
   assert 90 / 365 respectively with zero independent advances for the same
   cache.
3. **Close did not synchronously re-scope an in-flight controller load.**
   `SpendDashboardPane.onDisappear` deactivated demand and synchronized
   catch-up but never fed the new routine configuration into the
   controller, leaving a gated 365 load with no synchronous cancellation.
   Close now runs deactivate → capture routine configuration (30) →
   `controller.update(configuration:)` (letting #159 hard-scope
   cancel/reject the wide work) → synchronize routine catch-up. `stop()`
   also clears `isHistoryDemandActive` as a fail-safe (persisted
   `selectedDays` untouched); it lives in the same-file extension for the
   800-line `type_body_length` budget.
4. **Final primary-worker demand semantics.** The earlier report's claim that
   callers were fully traced and that nil/generic callers could not affect a
   wider dashboard worker was incomplete. Normal refreshes, stale-token
   hydration, and mode-only entry points can all re-enter the primary authority
   without an explicit horizon; once narrowing was enabled, their old
   settings-only calculation could withdraw a still-visible shared 90/365
   demand. The final resolver accounts for the active shared dashboard at the
   primary authority, while the probe re-entry no longer carries a captured
   horizon. No generalized demand registry was added. The invariant is
   `primary = max(routine, explicit, active-if-shared)`: shared + visible 90 →
   90, shared + visible All → 365, closed (or independent-only) → routine.
   When the dashboard stops sharing a previously shared cache, the primary
   is reconciled to the routine window only if a primary task/probe exists,
   so dashboard syncs never spawn routine work. No second scanner, no
   parallel scans, serialized `CostUsageScanExecutor` preserved.
5. **Primary shrink is checkpoint-safe.** `startCodexCostCatchUpIfNeeded` was
   monotonic (widen-only). Narrowing now mirrors widening: while a bounded
   pass runs, the narrower horizon is recorded and `restartRequested` is set
   so the current pass commits its checkpoint before restarting at 30; when
   idle, the worker cancels and restarts immediately. The paused-probe path
   clears stale wider pauses instead of re-probing at
   `max(desired, stale)`. Power/thermal, cancellation, no-progress, and
   scope-signature behavior are untouched.
6. **Final close ordering.** Deactivate demand → routine
   `SpendDashboardSource.configuration` (30) → `controller.update` → catch-up
   synchronize. Builder-gated 365 never reaches the loader; loader-gated 365
   completions are ownership-discarded; only the 30-day result publishes.
7. **Coverage and exact sequences.**
   - Test A (shared 90): primary advances `[90]`, independent `[]`,
     `codexCostCatchUpHistoryDays == 90`, no independent task.
   - Test B (shared All): primary `[365]`, independent `[]`.
   - Test C (close All → routine): primary `[365, 30]`, final horizon 30.
   - Test D (close with 365 loader in flight): loader horizons `[365, 30]`,
     stale 365 discarded (model stays empty/refreshing), 30 publishes cost 9
     with final configuration 30.
   - Test E (close with 365 builder gated): loader horizons `[30]` only.
   - Stop fail-safe: active → `stop()` clears demand, keeps `selectedDays`.
   - Control: existing independent 90→30 test still yields `[90, 30]`;
     `UsageStoreSpendDashboardCodexCostCatchUpTests` (19) and
     `SpendDashboardLoadLivenessTests` (15) pass unmodified, so #159
     hard-scope semantics are intact.

## 12. Remaining limitations / deferred work

- **Aggregate background-work budget (GitHub #160 broader acceptance item) is
  explicitly deferred** to a broader performance/integration phase. This
  phase implements and verifies the confirmed history-horizon defect only:
  there is still no single observable budget covering scanner + dashboard +
  projection work. Do not read this report as completing every sentence of
  the broader #160 acceptance list.
- Narrowing the horizon (365→30) rotates the catch-up scope signature and
  restarts the worker to re-evaluate statuses. With nothing pending this
  performs only manifest/status reads, but a fully converge-aware worker
  could skip even the restart. Intentionally deferred: the current behavior
  is correct and cheap, and avoiding a second retention mechanism was an
  explicit goal.
- `spendDashboardExtendedCodexHistoryRequired` currently names the visible-All
  condition. If a future feature (e.g. annual export, reconciliation) needs
  extended history, it should set demand through this predicate/policy rather
  than adding a new escalation site.

## 14. Final review — current-demand arbitration

The prior correction correctly widened the shared primary worker for visible
90/All and added checkpoint-safe narrowing. Enabling narrowing exposed one
remaining arbitration gap: a generic primary start computed only
`max(settings.costUsageHistoryDays, requestedHistoryDays ?? 0)`. A generic
refresh after visible shared All therefore looked like a withdrawal from 365
to 30 even though the dashboard was still visible. This section supersedes
the earlier nil/generic-caller conclusion in §13.4.

The primary authority now resolves exactly:

```text
effectivePrimaryHistory = max(
    configuredRoutineHistory,
    explicitRequestedHistory,
    spendDashboardCodexCostCatchUpUsesPrimaryWorker
        ? spendDashboardCodexHistoryDays
        : 0
)
```

`spendDashboardCodexHistoryDays` is already `max(routine,
activeDashboardRequestedDays)`, with closed demand reading as routine. The
shared-primary boolean is set before the dashboard-to-primary call and is
cleared before independent-profile reconciliation. Thus generic calls observe
current shared demand without every caller manually forwarding it, while an
independent visible All worker cannot widen the ambient primary worker.

### Complete primary-worker production caller inventory

| Location | Classification | Current-demand proof |
| --- | --- | --- |
| `UsageStore.swift:1555` → `afterRefreshing` | Routine refresh bridge | For Codex, forwards with no explicit horizon; the authority re-reads current shared demand. |
| `UsageStore+TokenCost.swift:300` | Routine stale-cache hydration | No-argument start; cannot withdraw a current shared 90/365 demand. |
| `UsageStore+CodexCostCatchUp.swift:50` | `afterRefreshing` forwarding wrapper | Passes nil horizon and automatic mode. |
| `UsageStore+CodexCostCatchUp.swift:96` | Immediate internal widening restart | Carries the just-computed current target after cancellation; no suspension occurs before re-entry. |
| `UsageStore+CodexCostCatchUp.swift:116` | Immediate internal narrowing restart | Carries the just-computed current target after withdrawal; checkpoint-safe narrowing is unchanged. |
| `UsageStore+CodexCostCatchUp.swift:174` | Post-pass checkpoint restart | Uses the latest target recorded by the running-worker arbitration; a withdrawal records routine before this defer path. |
| `UsageStore+CodexCostCatchUp.swift:206` | Accelerated mode-only entry point | No explicit horizon; resolver preserves active shared demand. |
| `UsageStore+CodexCostCatchUp.swift:210` | Background mode-only entry point | No explicit horizon; resolver preserves active shared demand. |
| `UsageStore+CodexCostCatchUp.swift:923` | Internal paused-progress probe | Re-enters without its captured old horizon so removed demand cannot be resurrected. |
| `UsageStore+SpendDashboardCodexCostCatchUp.swift:92` | Shared dashboard demand | Sets shared-primary state first, then passes the policy horizon. |
| `UsageStore+SpendDashboardCodexCostCatchUp.swift:120` | Shared-cache withdrawal/reconciliation | Clears shared-primary state first, then requests configured routine history. |
| `UsageStore+SpendDashboardCodexCostCatchUp.swift:150` | Shared dashboard start/resume | Sets shared-primary state first, then passes the policy horizon. |

The branch-wide search also found the direct test invocations in
`SpendDashboardCodexHistoryHorizonTests`, `UsageStoreCodexCostCatchUpTests`,
and `UsageStoreSpendDashboardCodexCostCatchUpTests`; they exercise routine,
explicit, mode-only, withdrawal, probe, shared-dashboard, and independent
paths. No additional production caller was found.

### Exact arbitration regression sequences

- Visible shared All + `afterRefreshing: .codex`: primary advances
  `[365, 365]`; no 30-day restart, no independent dashboard advance.
- Visible shared 90 + no-argument stale-cache-equivalent start: primary
  advances `[90, 90]`; no 30-day restart.
- Visible shared All + accelerated then background mode change: primary
  advances `[365, 365, 365]`; mode changes accelerated → automatic without
  collapsing the horizon.
- Closing visible shared All: retained withdrawal coverage advances
  `[365, 30]` and ends at routine 30.
- Switching visible All to an independent/profile cache: independent worker
  advances `[365]`; the ambient primary re-arbitrates `[365, 30]` and remains
  routine after the switch.

Targeted results in this final correction:

- Each of the four new arbitration regressions passed individually.
- `swift test --filter SpendDashboardCodexHistoryHorizonTests` — 20/20 pass.
- `swift test --filter UsageStoreCodexCostCatchUpArbitrationTests` — 1/1
  pass (independent/profile transition).
- `swift test --filter UsageStoreCodexCostCatchUpTests` — 18/18 pass.
- `swift test --filter SpendDashboardLoadLivenessTests` — 15/15 pass; #159
  hard-scope/liveness behavior remains green.
- `swiftformat --lint` passed for the three changed Swift files. SwiftLint
  passed on each changed Swift file.

#161 remains untouched. The aggregate background-work budget remains an
explicitly deferred broader acceptance item; this correction only fixes
current primary history-demand arbitration.
