# Spend Dashboard Codex History Horizon (#160)

Routine/background spend collection must not silently force Codex history
scanning out to 365 days when a much smaller horizon is actually required.

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
never opened (no All selection). The catch-up worker then scanned 365 days
via the `max(scanDays, …)` floor, and once the primary worker converged, the
configuration horizon flipped to 365 as well, so snapshot loads followed.

## 3. Legitimate 365 consumers

Exactly one user-visible consumer genuinely requires full-year history: the
spend dashboard **All range**
(`SpendDashboardController.selectedDays == SpendDashboardSource.scanDays`,
persisted under `settingsSpendDashboardDays`). Selecting All needs 365 days
of daily/project/session breakdowns plus the 365-day token-activity strip.

Additionally, an explicitly configured 365-day cost window
(`costUsageHistoryDays == 365`) yields 365 through the policy clamp — that is
user intent, not escalation.

Deliberately **not** a scan consumer: the token-activity loader still reads
at `activityDays` (365), but `loadCachedCodexTokenActivity` only slices the
already-scanned cache and can never trigger a filesystem scan, so it costs
no I/O. No production consumer other than All requires a 365-day *scan*.

## 4. Horizon-selection policy

One authority, `SpendDashboardSource.requiredCodexHistoryDays(configuredWindowDays:dashboardRequestedDays:)`
(`Sources/CodexBar/SpendDashboardController.swift`):

- Routine/background work uses the configured window
  (`settings.costUsageHistoryDays`, default 30), clamped to `1...scanDays`.
- The full window is selected only when the dashboard explicitly requests
  `>= scanDays` (the All range) — or when the configured window itself is
  365.
- `SpendDashboardSource.configuration(...)` captures that value into
  `SpendDashboardConfiguration.codexHistoryDays` exactly as #159 established;
  `makeRequest` consumes the captured value and never overrides it.
- `UsageStore.spendDashboardCodexHistoryDays` is now the pure policy value.
  The old convergence/independent-cache escalation branches are removed.
- `startSpendDashboardCodexCostCatchUpIfNeeded` scans exactly
  `spendDashboardCodexHistoryDays`; the `max(scanDays, …)` floor is removed.
  The horizon stays inside the worker scope signature, so a horizon change
  still rotates the scope and stale narrower work cannot satisfy a broader
  scope (context-freshness check compares against the same policy value).
- `startSharedSpendDashboardPublication` creates the shared controller
  before the first observation so a persisted All selection is visible to
  the policy on the very first configuration capture (no new observation,
  polling, or lifecycle: the controller was already created on that same
  call stack via `applySharedSpendDashboardConfiguration`).
- New predicate `spendDashboardExtendedCodexHistoryRequired` names the
  explicit-demand condition for tests and future call sites.

## 5. Cached / superset history handling

No new retention machinery: the existing scanner semantics already handle
directionality. `requestedWindowExpandsCache` returns false when the
requested window is inside the cached window, so established 365-day cache
data satisfies a 30-day request without rescanning (no destructive
truncation of cached history). Conversely, 30-day data never satisfies an
explicit 365-day request: the horizon is part of the worker scope signature
and of #159 hard source ownership, so narrowing→broadening restarts work
under the broader scope. New Test C / Test D prove both directions at the
worker level.

## 6. #159 hard-scope preservation

Untouched: `codexHistoryDays` remains in `sameSourceOwnership` and remains
excluded from display-only changes. `SpendDashboardLoadRequest` still
consumes `configuration.codexHistoryDays`. All 16
`SpendDashboardLoadLivenessTests` pass unmodified, including 30→365
invalidation, gated-builder stale-scope death, same-horizon coalescing, and
presentation-only no-work.

## 7. Files changed

- `Sources/CodexBar/SpendDashboardController.swift` — added
  `requiredCodexHistoryDays` policy; reworded the stale
  `codexHistoryDays` doc comment; documented why the activity loader keeps
  the full depth (read-only slice, never a scan).
- `Sources/CodexBar/UsageStore+SpendDashboardCodexCostCatchUp.swift` —
  `spendDashboardCodexHistoryDays` is now the pure policy value (removed
  convergence/independent-cache escalation); worker scans the policy
  horizon; freshness check compares against the policy value; added
  `spendDashboardExtendedCodexHistoryRequired`.
- `Sources/CodexBar/UsageStore+SpendDashboardPublication.swift` — create the
  shared controller before the first observation; comment now describes the
  bounded horizon.
- `Tests/CodexBarTests/UsageStoreSpendDashboardCodexCostCatchUpTests.swift` —
  updated four tests to the bounded policy (configured window is honored;
  expansion restarts scope).
- `Tests/CodexBarTests/SpendDashboardCodexHistoryHorizonTests.swift` — new;
  Tests A–E plus policy units.

#161 was not implemented. No dashboard redesign, no snapshot/model-architecture
refactor, no main-actor changes, no Phase 1 rolling-window changes.

## 8. Targeted tests and results

- `SpendDashboardCodexHistoryHorizonTests` (8 tests): policy units, Test A
  routine load captures/scans `[30]` with no hidden 365 escalation, Test B
  All range captures/scans `[365]` attributable to the selection, Test C
  established broader cache needs zero scan passes for a narrower scope,
  Test D narrower→broader schedules `[30, 365]` work, Test E background
  sync with no visible dashboard scans `[30]`. All pass.
- `SpendDashboardLoadLivenessTests` (16 tests): all pass unmodified — #159
  intact.
- `UsageStoreSpendDashboardCodexCostCatchUpTests` (18 tests incl. 6
  parameterized cases): all pass.
- `SpendDashboardControllerTests` + `SpendDashboardTokenActivityIntegrationTests`
  + `SpendDashboardCachedPresentationTests` +
  `SpendDashboardAllTimeTokenSnapshotTests` + `SpendDashboardPublicationTests`
  (56 tests across 7 suites): all pass.
- `swift build`: complete.
- `swiftlint --strict` on the 5 changed/new files: 0 violations.
- `swiftformat --lint` on the 5 files: only 2 pre-existing
  `wrapIfStatementBodies` notes in `SpendDashboardController.swift`
  (verified present on the base SHA; homebrew formatter version drift, not
  introduced here). Full `./Scripts/lint.sh lint` was intentionally not run
  (pinned-tool installer + full-repo passes are disproportionate for this
  scope; per-file checks above cover the diff).

Broader suites (`make test`, `./Scripts/test.sh`, full Xcode plan) were
intentionally omitted: the change is scoped to the dashboard horizon, and
all directly affected suites pass.

## 9. Self-review Loop 1 findings (semantic / performance)

- Q: Can routine background activity still request 365 accidentally? A: No.
  Every Codex scan producer (`spendDashboardCodexHistoryDays`, catch-up
  worker, `makeRequest`, `load`) now flows from the single policy. The only
  remaining `= SpendDashboardSource.scanDays` defaults are the
  `SpendDashboardConfiguration`/`SpendDashboardLoadRequest` initializers
  (always given explicit values on production paths; the one fallback
  construction is a disabled, request-less stub) and the read-only activity
  slice. Fixed one real instance of this class during review (see below).
- Q: Is every 365 request tied to explicit need? A: Yes — All range,
  configured-365, or read-only cache slicing.
- Q: 365→30 reuse without rescan? A: Yes via existing
  `requestedWindowExpandsCache` directionality + Test C. (A horizon
  narrowing still rotates the worker scope signature and re-evaluates
  catch-up statuses — cheap manifest reads, not a rescan — which is the
  correct conservative behavior.)
- Q: 30 falsely satisfying 365? A: No — scope signature + #159 ownership;
  Test D + existing 30→365 liveness tests.
- Q: #159 intact? A: Yes — ownership/liveness code untouched; 16/16 pass.
- Q: Power/thermal/cancellation/checkpoint preserved? A: Yes — untouched.
- Q: New polling/retries/scans? A: No. The eager controller creation in
  `startSharedSpendDashboardPublication` allocates the same object on the
  same call stack as before; no new tasks or observations.
- Review fix applied: the first implementation read the controller's
  `selectedDays` through observation-tracked state, which risked launch-time
  races and cross-object observation coupling. Reworked to read the already-
  materialized shared controller storage directly (nil until the dashboard
  exists = bounded), plus eager creation before the first observation so a
  persisted All selection applies immediately.

## 10. Self-review Loop 2 findings (diff scope)

`fb7bb64c9be270838d1681e2873ae5cf80196b24..HEAD` contains only: the policy
addition + comment updates in `SpendDashboardController.swift`; the horizon
selection/worker scoping in `UsageStore+SpendDashboardCodexCostCatchUp.swift`;
the eager-controller + comment in `UsageStore+SpendDashboardPublication.swift`;
four test updates in `UsageStoreSpendDashboardCodexCostCatchUpTests.swift`;
and the new `SpendDashboardCodexHistoryHorizonTests.swift`. No #161 code, no
UI changes, no Phase 1 files, no #159 semantic changes, no hidden 365
constants in routine paths (remaining `scanDays`/`365` references are the
policy clamp target, the read-only activity slice, other providers' windows,
or unrelated clamps). Report doc is the only documentation change.

## 11. #161 confirmation

#161 was not implemented in this phase. No code or tests reference it.

## 12. Remaining limitations / deferred optimizations

- Narrowing the horizon (365→30) rotates the catch-up scope signature and
  restarts the worker to re-evaluate statuses. With nothing pending this
  performs only manifest/status reads, but a fully converge-aware worker
  could skip even the restart. Intentionally deferred: the current behavior
  is correct and cheap, and avoiding a second retention mechanism was an
  explicit goal.
- `spendDashboardExtendedCodexHistoryRequired` currently has one consumer
  class (the All range). If a future feature (e.g. annual export,
  reconciliation) needs extended history, it should set demand through this
  predicate/policy rather than adding a new escalation site.
