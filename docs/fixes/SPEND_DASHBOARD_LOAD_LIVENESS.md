# Spend dashboard load liveness — Phase 2 report

Issue addressed: **ColumbusLabs/QuotaKit#159** (spend dashboard can discard
completed loads and restart indefinitely under revision churn). Phase 2 is
deliberately limited to this control-flow/liveness defect plus deterministic
regression coverage; #160 (history/scan horizons) and #161 (model caching /
snapshot hashing) are untouched.

No runtime CPU improvement is claimed. The purpose of this phase is eliminating
the confirmed liveness/wasted-work control-flow defect; production frequency
still needs native profiling.

## Identity

| Field | Value |
| --- | --- |
| Base SHA (reviewed Phase 1 head) | `fac6ccc2cebb5f80cb5b77d1e2b5316bec113faa` |
| Base branch | `fix/codex-rolling-cost-window-correctness` |
| Branch | `fix/spend-dashboard-load-liveness` |
| Worktree | `/Users/zachmac/Documents/Projects/quotakit-spend-dashboard-liveness-fix` |
| Issue | ColumbusLabs/QuotaKit#159 |

## Old failure sequence

The controller already recognized same-owner revision churn in
`update(configuration:)` and let the in-flight load finish — but the ordinary
completion path in `handleBuiltRequest` then discarded the finished work:

1. Ordinary dashboard load starts with configuration revision A.
2. Codex catch-up advances while the load runs; the observer delivers
   same-owner revisions B, C, D (only `sourceRevisions` advance; ownership is
   unchanged). `update(configuration:)` adopts each revision and lets the load
   continue — no B/C/D loads start.
3. Load A completes successfully.
4. `handleBuiltRequest` evaluates `request.configuration == latestConfiguration`
   (A != D), starts another ordinary load for D, returns, and never applies A.
5. If another revision lands before the D load completes, the same cycle
   repeats: **load → discard → restart → discard → restart** with no
   user-visible progress, while every discarded load paid the full cost
   (Codex snapshot loaders, provider-input refresh, model construction, serial
   scan-executor queueing).

The 250 ms observation debounce does not bound this: any load slower than the
debounce interval can be starved indefinitely.

## New controller invariants

The controller now distinguishes two classes of configuration change:

- **Hard invalidation.** When source identity/ownership is no longer compatible
  (account owner/source change, credential scope change, incompatible Codex
  home/source identity, bucket/calendar semantics, provider identity change),
  decided by the existing `sameSourceOwnership(...)` plus loaded-input
  scope/invalidation machinery, the completed result is discarded and the new
  identity is loaded. Old-owner data never publishes.
- **Soft freshness change.** When ownership is still safe and only
  content/progress/source revisions advanced, the completed result publishes.
  Revisions received during the load are coalesced into at most one follow-up
  load targeting the newest known configuration.

Concretely: every completed identity-safe load is eligible to advance the
visible state even if a newer same-owner revision arrived while it ran; at most
one newest-state reconciliation is queued after that completion.

## Latest desired configuration vs. result provenance

`apply(...)` previously set the controller configuration from the finished
request, which would roll the desired configuration backward (D → A) when
publishing a stale-but-safe result. The fix separates the two concerns:

- **Result provenance** remains the request's configuration: `loadedInputScopes`
  entries, `lastSuccessfulConfiguration`, `loadedAt`, and invalidation
  decisions still describe the revision under which inputs were captured.
- **Latest desired configuration** (`self.configuration`) is now passed
  explicitly as `desiredConfiguration` and is never rolled back: presentation,
  subsequent reconciliation, model rebuilding, and the next request all use the
  newest observer-delivered revision.

## Ordinary-load coalescing behavior

- Configuration unchanged → apply normally, no follow-up.
- Configuration changed but ownership safe → apply the completed result against
  the newest desired configuration, then `reconciliationIsRequired` decides the
  follow-up: display-only drift (filter/currency/hide settings with unchanged
  source revisions) is already reflected by rebuilding against the newest
  configuration and schedules no source work; source-revision drift schedules
  exactly one ordinary follow-up for the newest coalesced configuration.
- Ownership changed → discard without publishing and load the new identity.

A → B → C → D therefore performs exactly two loads (A + D): A's safe result
becomes visible, B and C are never individually loaded, and one follow-up
converges on D. Churn continuing through the follow-up (D/E arriving while the
D-targeted load runs) publishes the follow-up result as well, then coalesces
again — progress every completion, never a pre-publication restart loop.

## Hard ownership invalidation behavior

The ordinary completion path now rejects with `sameSourceOwnership`, and the
reconciliation/capture drift path requires same ownership across the forced
request, the capture request, and the newest target. Any owner/scope change
falls through to the existing cancel/restart paths (`startLoad` with the new
identity, generation-guarded stale rejection, `invalidatedSourceIDs` clearing,
`restartAfterBuildMismatch` forcing the new owner). Loader-level
auth-fingerprint rechecks and retained-data rules are unchanged.

## Forced-refresh behavior

- An explicit force still executes the provider loader exactly once per manual
  refresh; same-owner revisions arriving during `.forcing` adopt the newer
  configuration without starting another force.
- The forced outcome transitions to a single `.reconciling` capture; the
  capture/apply barrier is now progress-safe: a same-owner-drifted capture
  merges into the forced outcome and publishes (preserving learned
  confirmed-empty/confirmed-nonempty observations) instead of restarting
  captures indefinitely, with at most one follow-up capture for the newest
  revision.
- Ownership change at any forced stage discards the old outcome and forces the
  new owner; stale generations are still rejected.

## Deterministic regression tests

New suite `Tests/CodexBarTests/SpendDashboardLoadLivenessTests.swift`
(controllable loader gate + scripted request builder; no timing sleeps):

1. `same-owner burst publishes in-flight result and coalesces one follow-up` —
   A starts; B/C/D arrive with no new loads; A publishes (visible total 5) with
   the controller still on D; exactly one follow-up targets D; loader
   configurations are exactly [A, D].
2. `churn during follow-up still publishes each safe completion` — A publishes
   despite B/C; the C follow-up publishes despite D/E; loader configurations
   are exactly [A, C, E].
3. `true owner change still invalidates the in-flight completion` — owner-1
   load starts; owner-2 configuration cancels it; the stale owner-1 completion
   never publishes; owner-2 applies.
4. `forced refresh under same-owner churn forces providers exactly once` —
   builder modes are exactly [.forceRefresh, .captureOnly], loader forces are
   exactly [true], forced Codex success merges with capture drift (total 12).
5. `five revision burst performs exactly two loads and keeps progress visible` —
   A→…→E performs loads [A, E] only (generation == 2); A's result stays visible
   while the E follow-up runs.

Pre-fix run (counters stubbed, behavior unchanged): tests 1, 2, and 5 fail
(completed results discarded, nothing published); tests 3 and 4 pass, confirming
the safety/force paths were already strict. Post-fix: all 5 pass.

## Targeted test commands and results

- `swift test --filter 'SpendDashboardLoadLivenessTests'` — 5/5 pass.
- `swift test --filter
  'SpendDashboardControllerTests|SpendDashboardForceStateMachineTests|SpendDashboardControllerRevisionTests|SpendDashboardRequestTimeTests'`
  — 37/37 pass (includes force state-machine A–M, notably C and E which
  exercise the touched reconciling paths).
- Combined re-run after the final formatting edit: 42/42 pass.
- `swift test --filter 'cross provider case clusters are derived or
  specifically justified'` — passes (gatekeeper anchors re-verified).
- `swiftformat --lint` on the three changed files — clean except two
  pre-existing `wrapIfStatementBodies` findings that also fail on the base SHA
  (left untouched).
- `swiftlint --strict` on `SpendDashboardController.swift` and
  `SpendDashboardLoadLivenessTests.swift` — 0 violations.
- Broader suites (`./Scripts/test.sh`, full package suite) intentionally
  omitted per the phase testing strategy; no targeted failure gave a reason to
  widen.

## Lightweight instrumentation

Added `SpendDashboardLoadLivenessCounters` (test-visible, `@ObservationIgnored`
so counter updates never trigger UI refreshes): ordinary/forced/reconciliation
starts, applied vs. ownership-discarded completions, same-owner drift
coalesced, and follow-up loads scheduled. No production telemetry subsystem was
built; the deterministic tests asserting these counters are the observability
deliverable for this phase.

## Self-review findings and corrections

- **Loop 1 (liveness):** walked A→B→C→D, churn-during-follow-up, no-change,
  completion-before-revision, and revision-immediately-before-completion. All
  publish every identity-safe completion with at most one coalesced follow-up.
  Pre-loader build restarts (cheap capture rebuilds targeting the newest
  configuration, no loader work discarded) were deliberately left as-is.
- **Loop 2 (safety/force):** the first draft of the reconciling drift branch
  checked ownership only for the forced outcome vs. target, which could have
  merged a foreign-owner capture. Corrected to require same ownership across
  forced request, capture request, and target; owner change now always falls
  through to the forcing restart. Re-ran the affected suites (42/42 pass).
  Also verified: force never degrades to ordinary (follow-ups preserve
  `.reconciling`), stale generations are rejected, and `stop()` nil-config
  completions return safely.
- **Loop 3 (diff/scope):** `git diff fac6ccc2cebb5f80cb5b77d1e2b5316bec113faa..HEAD`
  touches only `SpendDashboardController.swift` (state machine + counters),
  the new test file, 4 gatekeeper line integers, and this report. #160
  (`scanDays`, history policy) and #161 (`snapshotRevision`, hashing,
  `rebuildModel`) are untouched; Phase 1 rolling-window code is untouched; no
  `Task.sleep` in tests; no new concurrency (serial executor path preserved).

## Gatekeeper anchors changed

`Tests/CodexBarTests/ProviderArchitectureGatekeeperTests.swift` — line integers
only (anchor strings, provider IDs, counts, fingerprints, reasons unchanged):

- 1667 → 1744 (`provider: .codex,` OpenCodex enrichment)
- 1696 → 1773 (`if providerID == UsageProvider.codex.rawValue {`)
- 1713 → 1790 (`if sourceID.hasPrefix("codex:") { return .codex }`)
- 1740 → 1817 (`guard input.provider == .codex,`)

## Deferred to #160/#161

- Pre-loader capture rebuilds can still chase a continuously advancing revision
  without running the loader; bounded in practice (captures are cheap relative
  to loads) but noted for #161's caching work.
- No change to 365-day scan horizons (#160), snapshot hashing/fingerprint
  caching/`rebuildModel` memoization/MainActor placement (#161), or the shared
  dashboard publication debounce path (no integration change was needed).
