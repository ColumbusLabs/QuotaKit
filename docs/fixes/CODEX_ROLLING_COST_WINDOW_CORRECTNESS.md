# Codex rolling cost window correctness — Phase 1 report

Issues addressed: **#157** (expired day retained in established rolling totals) and **#158**
(valid partial progress rejected after the oldest day expires). Phase 1 is deliberately limited
to these two issues plus regression coverage; the dashboard reload loop, 365-day background
scanning, and main-actor work tracked by #159–#161 are untouched.

## Identity

| Field | Value |
| --- | --- |
| Base SHA (`origin/main`) | `de6995911f861cc0a9093c048f74e417077d7a98` |
| Branch | `fix/codex-rolling-cost-window-correctness` |
| Worktree | `/Users/zachmac/Documents/Projects/quotakit-rolling-cost-window-fix` |
| Issues | ColumbusLabs/QuotaKit#157, ColumbusLabs/QuotaKit#158 |

Commits (oldest first):

1. `a23988262bae59eb7d6ba7df137636bcacaaa767` — `test: reproduce Codex rolling cost window rollover defects (#157, #158)`
2. `3cc08c82e0bde598741b85b657d69492d5becf97` — `fix: normalize Codex rolling cost snapshots to the candidate window (#157, #158)`
3. `34316c987c4adf47c77d4339257dfba5a7f2974e` — `test: add Codex rolling-window regression matrix (#157, #158)`
4. `fe8e62d320d392ec124426ffd1bb6406ceda0e65` — `test: self-review corrections for rolling-window coverage`

The documentation commit containing this file follows these four, and the independent-review
correction commit `fix: harden Codex rolling cost publication` follows the documentation
commit. Its corrections are recorded in [Independent-review correction](#independent-review-correction)
below.

## Root causes

The producer (`CostUsageFetcher.loadTokenSnapshot` / `loadCachedCodexTokenSnapshotResult`)
builds an inclusive producer-local rolling window: `since = now - (historyDays - 1)` calendar
days, `until = now`, and it already records the exact bounds as `historySinceDayKey` /
`historyUntilDayKey`. The catch-up publication helpers in
`Sources/CodexBar/UsageStore+CodexCostCatchUp.swift` did not use those bounds:

- **#157 — `codexCostSnapshotOverlayingVerifiedCurrentDay`** removed only the row matching the
  candidate's current day, appended the verified day, and summed every remaining row. On a day
  rollover the established snapshot's oldest day was retained, producing N+1 rows and an
  overstated `last30DaysCostUSD` / `last30DaysTokens` / `last30DaysRequests` while
  `historyDays` still claimed N. It also reconstructed the snapshot without
  `historySinceDayKey` / `historyUntilDayKey`, silently dropping the coverage bounds. The
  pending-tail copy helper `codexCostSnapshot` dropped the same fields, and
  `codexCostSnapshotContentEquals` ignored them, so bounds could not survive publication.
- **#158 — `codexCostSnapshotAdvancingPartialLowerBound`** required *every* prior daily row to
  be present in the candidate. That is valid only while both snapshots cover the same
  interval. Once the rolling window advances, the oldest day is expected to disappear, so
  legitimate forward progress was rejected as a regression. The aggregate non-decreasing checks
  were also window-blind: an expensive expired day legitimately lowers the rolling total.

## Implementation

### Shared window helper (`Sources/CodexBarCore/CostUsageDayWindow.swift`)

`CostUsageDayWindow` is the single authority for rolling-window day math:

- `CostUsageTokenSnapshot.historyDayWindow(calendar:)` prefers the exact producer bounds when
  present and falls back to the `updatedAt` anchor plus `historyDays` (clamped 1...365) for
  snapshots persisted before the bounds existed. No elapsed-seconds math is used anywhere.
- `contains(_:)` and `contains(entryDate:calendar:)` normalize `yyyy-MM-dd` keys and parseable
  timestamps through the bucket calendar. `dayKey(_:advancedBy:calendar:)` moves day keys by
  calendar days, which keeps DST transitions on the correct local day.
- `CostUsageLocalDay.key(fromEntryDate:calendar:)` was extracted from the previously private
  `CostUsageTokenSnapshot.localDayKey(for:calendar:)` so both Core and the catch-up helpers
  share one normalization rule. `localDayKey` now delegates to it; behavior is unchanged.

### Overlay fix (#157)

`codexCostSnapshotOverlayingVerifiedCurrentDay` now:

1. Computes the candidate and established windows and requires the candidate window to start
   at/after the established start, to end at/after the established end, and to end no later
   than one calendar day past the established end. That last condition is what refuses to
   claim established coverage across unverified gap days after a multi-day sleep; the helper
   returns `nil` instead of stamping `historyCoverageIsEstablished: true` on a gapped window.
2. Finds the verified current-day row by the candidate window's `untilKey` (not by
   `updatedAt`), so the verified day is always the window end day.
3. Drops every established row outside the candidate window, then upserts the verified day, so
   exactly N rows remain and totals are recomputed over exactly that set.
4. Emits truthful metadata: `historyDays` from the candidate, bounds set to the candidate
   window, established coverage kept only for the gap-free union, and window-scoped fields
   (`meteredCostUSD`, `historyLabel`) carried over only while the window is unchanged.

### Partial-advance fix (#158)

`codexCostSnapshotAdvancingPartialLowerBound` now normalizes both snapshots to the candidate
window and:

1. Rejects a candidate whose window end moved backwards (a shrinking window could otherwise
   silently drop visible in-window rows from comparison).
2. Applies presence + non-decreasing cost/token checks only to prior rows still inside the
   candidate window. Rows before the window start expire; their known values accumulate as the
   only aggregate decrease the candidate may explain. Rows past the window end cannot belong to
   the requested window and are ignored (the rollback guard handles the window level).
3. Keeps the strict same-window aggregate lower bounds by construction: the permitted decrease
   is `currentAggregate - expiredAggregate`, which is exactly the old `>=` check when nothing
   expired. When any expired row's contribution is unknown (`nil` cost/tokens), no credit is
   granted and the strict bound applies instead of accepting an unverifiable decrease.

### Safety model preserved

The lower-bound protections remain in force for everything inside the shared window:
disappearing in-window rows, cost regressions, token regressions, and nil-ing previously priced
values are rejected by the same per-row checks as before; the same-window aggregate check is
bit-for-bit equivalent to the previous behavior because the expired credit is zero. Scope,
account, configuration, history-window, and publication-revision guards in
`publishPendingCodexCostCatchUpSnapshotIfChanged`, `publishTokenSnapshot`,
`codexCostCatchUpContextIsCurrent`, and `tokenSnapshotPublicationForCurrentProviderConfig` are
unchanged. Partial snapshots are never promoted to established coverage.

## Reproduction (pre-fix evidence)

Before the implementation, the reproduction tests were executed against `de6995911` and failed
exactly as the issues described:

- `established history trims the expired day when the verified current day advances` —
  observed 31 rows, `$31`, 3,100 tokens, and `nil` bounds; the fixed expectation is 30 rows,
  `$30`, 3,000 tokens, `2026-08-18...2026-09-16`.
- `partial catch-up accepts rollover when the oldest day legitimately expires` — the helper
  returned `nil`.
- The negative control `partial catch-up still rejects an in-window cost regression` passed
  before and after.

## Regression matrix

`Tests/CodexBarTests/CostUsageDayWindowTests.swift` covers the helper directly: explicit
bounds preferred over `updatedAt`, fallback derivation and clamping, DST-safe day arithmetic
(spring-forward, fall-back, negative/zero offsets, junk keys), entry-date normalization, and
bucket-calendar anchoring.

`Tests/CodexBarTests/CodexRollingCostWindowOverlayTests.swift` covers #157:

- window lengths 1/7/30/365 with row count, cost, token, and request totals, plus
  `summary(forLastDays:)` agreement;
- multi-day gap refusal, window rollback refusal, current-day replacement without duplication;
- narrowing to a smaller window and refusing an expansion the established snapshot never
  covered;
- metadata: bounds, `historyDays`, currency, provenance, fingerprint, ownership, projects,
  sessions, hourly, rollover-scoped `meteredCostUSD` / `historyLabel`;
- unpriced established rows (aggregate stays `nil`, rows stay bounded), stray out-of-window
  rows, LA midnight boundary, both DST transitions.

`Tests/CodexBarTests/CodexRollingCostWindowPartialTests.swift` covers #158:

- expired-oldest-day rollover for 1/7/30/365 days, unchanged same-window values, multi-day
  offline rollover, expanded window, LA midnight and both DST transitions;
- rejection of disappearing in-window rows, cost regressions, token regressions, nil cost or
  token on previously known in-window rows, window rollback, aggregate decreases beyond the
  expired credit, and decreases with unknown expired contributions;
- acceptance of a legitimate aggregate decrease caused solely by an expensive expired day;
- timestamp entry dates compared by bucket day;
- an end-to-end publication-loop test proving that a pending catch-up republishes when only
  the coverage bounds advance and that the published snapshot retains those bounds.

## Verification actually run

| Command | Result |
| --- | --- |
| `swift test --filter 'CodexRollingCostWindowOverlayTests\|CodexRollingCostWindowPartialTests\|CostUsageDayWindowTests'` | 39 tests passed |
| `swift test --filter 'UsageStoreCodexCostCatchUpTests\|UsageStoreSpendDashboardCodexCostCatchUpTests'` | 76 tests in 5 suites passed (combined focused batch) |
| `swift test --filter 'CostUsageTokenSnapshotDaySelectionTests\|CostUsageWindowSummaryTests\|CostProvenanceTests\|UsageStoreCachedTokenHydrationTests\|CostUsageCalendarTests\|SpendDashboardPartialCostTests\|SpendDashboardCachedPresentationTests\|UsageStoreLocalLedgerPublicationTests'` | 85 tests in 10 suites passed |
| `swift test --filter 'SyncCoordinator\|SyncCostIsEstimatedTests\|SyncCodexMultiAccountIntegrationTests\|CostUsageFetcherCacheSnapshotTests'` | 179 tests in 10 suites passed |
| `./Scripts/lint.sh lint` | 0 SwiftFormat/SwiftLint violations across 2,113 files; audits passed |
| `CODEXBAR_TEST_GROUP_SIZE=6 ./Scripts/test.sh` (full sharded suite, twice) | Final run: exit 0, 970 suites / 10,401 tests, 168/168 groups first-pass, 0 failures, 0 timeouts, 871.8 s |

The first full-suite run failed only `ProviderArchitectureGatekeeperTests`, whose line-anchored
allowlist tracks exact source lines in `UsageStore+CodexCostCatchUp.swift`. The construct
fingerprints were unchanged; only the anchor line numbers moved, and the catalog was refreshed
in the self-review commit. The final full-suite run on the finished branch is clean.

## Self-review loops

- **Loop 1 — correctness vs acceptance criteria.** Re-read both issues line by line. Result:
  all acceptance criteria covered; found test gaps for partial-path DST/midnight coverage and a
  test-only `86400` day offset. Both corrected.
- **Loop 2 — adversarial edge cases.** Walked midnight during a pass, multi-day sleep, DST
  spring/fall, no current-day row, sparse partial history, missing cost/tokens, unpriced rows,
  expensive-expired-day decreases, and stale config/account/scope publications. Found that a
  stale `historyLabel` could cross a window change; `historyLabel` now follows the same
  window-scoped rule as `meteredCostUSD`.
- **Loop 3 — diff/regression review.** Reviewed the entire branch diff against `origin/main`.
  No unrelated changes, no duplicated date logic (tests reuse fixtures, Core centralizes the
  window), no metadata dropped from reconstructed snapshots, and no concurrency/publication,
  account-isolation, or formatting regressions. The only correction was the gatekeeper anchor
  refresh required by moved lines.

## Independent-review correction

The independent review of `8e8eaac62beed61d440ea279656c9d4b7e9f2d1b` accepted the #157/#158
architecture and raised exactly two findings, both corrected in the
`fix: harden Codex rolling cost publication` commit.

### Finding 1 — floating-point false rejection in the expired-cost lower bound

`optionalLowerBoundAfterExpiry` compared `Double` dollar aggregates with exact arithmetic. A
mathematically equal rollover could be rejected because the producer and the helper can
accumulate the same values in different orders:

- prior daily costs `$0.10` + `$0.20` + `$0.30` sum to `0.6000000000000001`;
- the expired credit is `$0.10`, so the computed bound is `0.5000000000000001`;
- the valid retained total `$0.20` + `$0.30` is exactly `0.5`;
- `0.5 >= 0.5000000000000001` is false, so the helper returned `nil`.

**Correction.** The generic exact comparison remains for `Int` token totals. A `Double`
specialization now compares the candidate, the current aggregate, and the expired credit as
signed nanodollar units — the accounting resolution both local scanners already use
(`CostUsageScanner.costScale`, `PiSessionCostScanner.costScale`, and the verified aggregate
store all produce `Int64((value * 1_000_000_000).rounded())`). `nanodollarUnits` returns `nil`
for non-finite or out-of-range values and those fall back to the exact comparison. Rounding
can only absorb sub-nanodollar representation noise: the largest regression the bound can hide
is below one nanodollar (`$0.000000001`), which is not a meaningful cost change at the
scanners' accounting resolution, while a real dollar regression still falls below the bound.
Token comparisons are untouched and remain exact.

### Finding 2 — overlay cost completeness ignored `unpricedRequestCount`

`codexCostSnapshotOverlayingVerifiedCurrentDay` treated a window cost as complete whenever
every retained row had `costUSD != nil`. The canonical builders
(`CostUsageFetcher.tokenSnapshot` and `CostUsageDailyReport.merged`) deliberately refuse to
call a window complete when any row still has unpriced requests. A merged row can carry a
non-nil known subtotal beside `unpricedRequestCount > 0`, and the overlay would have promoted
that subtotal into an apparently complete `last30DaysCostUSD`.

**Correction.** The overlay now mirrors the canonical invariant:

```swift
let allEntriesCarryCost = !daily.isEmpty && daily.allSatisfy {
    $0.costUSD != nil && ($0.unpricedRequestCount ?? 0) == 0
}
```

Tokens, requests, pricing architecture, Pi scanning, and `summary(forLastDays:)` are unchanged.

### Targeted tests and results

The two regression tests were added and executed against `8e8eaac62` before the correction,
where they failed exactly as the review described; the nearby negative control passed both
before and after:

- `partial accepts a floating-point equal rollover that drops the expired cost` — failed on
  `8e8eaac62` (helper returned `nil`), passes after the correction.
- `partial still rejects a meaningful cost regression after expiration` — rejects both a
  plainly below-bound total (`$0.49`) and a one-nanodollar below-bound total (`$0.499999999`),
  before and after the correction.
- `overlay keeps an unpriced historical row from completing the window cost` — failed on
  `8e8eaac62` (`last30DaysCostUSD` was non-nil), passes after the correction and keeps the
  unpriced row in `daily` with a `nil` aggregate while tokens still total normally.

| Command | Result |
| --- | --- |
| `swift test --filter 'floating-point equal rollover\|unpriced historical row\|meaningful cost regression after expiration'` | 3 tests passed after the fix (2 failed before it) |
| `swift test --filter 'CodexRollingCostWindowPartialTests\|CodexRollingCostWindowOverlayTests'` | 36 tests in 2 suites passed |
| SwiftFormat + SwiftLint on the four modified files | 0 violations |

Follow-up: the correction commit inserted code above three exact-line gatekeeper constructs in
`UsageStore+CodexCostCatchUp.swift`. The `ProviderArchitectureGatekeeperTests` catalog was
refreshed for those anchors only (lines 739/757/804 to 783/801/848) with provider IDs,
reference counts, fingerprints, and reasons unchanged, and
`cross provider case clusters are derived or specifically justified` passed.

The fixture now mirrors the canonical completeness rule and supports
`unpricedRequestCount` rows. Two focused self-review loops covered the modified helpers, the
new tests, and the complete diff from `8e8eaac62`; no further corrections were needed.

## Remaining risks

- The helpers rely on producers recording `historySinceDayKey` / `historyUntilDayKey`. Legacy
  snapshots without bounds use the `updatedAt` + `historyDays` fallback; for a retained previous
  report whose `updatedAt` predates its window end, the overlay's gap guard can be conservative
  and skip a pending-tail publication until the authoritative stable publication runs. No
  incorrect data is published in that case.
- The aggregate "expired credit" is only granted when every expired row's cost/tokens are
  known. An unpriced expired day therefore keeps the strict aggregate bound until the next
  authoritative publication, which can delay a visible decrease but cannot publish a regression.
- `summary(forLastDays:)` remains anchored on `updatedAt`; for snapshots whose `updatedAt` is
  older than their window end the two can describe different windows. That producer-side
  `updatedAt`/bounds reconciliation is out of scope here and was already present upstream.
- `CostUsageDayWindow` duplicates the concept of the internal `CostUsageScanner.CostUsageDayRange`
  because the latter is vendored and not part of the public Core surface. If the vendored range
  becomes public later, the two should be unified.

## Deferred to #159–#161

Nothing from #159, #160, or #161 is implemented in this branch. Specifically untouched:
`SpendDashboardController` reload/reconciliation architecture, 365-day background collection
policy, snapshot hashing, model memoization, and main-actor execution changes.
