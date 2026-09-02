# Codex ledger memory and publication repair

Status: implementing final runtime verification

## Goal

Make Codex cost accumulation durable, incremental, and non-regressive across the
Mac menu, Spend Dashboard, widget publication, CloudKit, and the iPhone while
keeping QuotaKit's idle aggregate memory in the low hundreds of megabytes.

## Confirmed failure topology

- The normal Codex cost refresh and Spend Dashboard own independent catch-up
  loops against the same cache.
- Spend Dashboard requests at least 365 days while the ordinary cost surface
  uses the configured display window.
- The cache retains one range-specific previous report, so alternating windows
  can leave a consumer without a matching established fallback.
- Partial replacement protection depends on an established in-memory
  publication. Restart, account invalidation, or repeated failure can remove
  that protection even though SQLite still contains established history.
- Both CloudKit paths overwrite stable per-device/provider records. A partial
  Mac publication can therefore become the only payload available to a cold
  iPhone reader.
- Routine OpenAI dashboard refreshes create hidden WebKit content processes on
  the background cadence even when direct API preflight succeeds.

## Required invariants

1. Scanner state is keyed by source scope, never by a UI display window.
2. Seven-, 30-, 90-, and 365-day totals are projections over the same durable
   day aggregates.
3. An incomplete scan cannot delete or replace an established day.
4. A verified current-day update can advance while historical catch-up remains
   pending.
5. Downward corrections require a complete revision proving truncation,
   deletion, deduplication, or repricing; totals are not protected with a naive
   numeric maximum.
6. App restart and transient refresh failure retain the last verified history.
7. Mac, widget, legacy CloudKit, provider CloudKit, and iPhone ledger consume
   one canonical publication.
8. Only one catch-up worker may operate on a cache identity at a time.
9. A successful background direct API refresh must not create a WebView.
10. A required DOM fallback is serialized and preserves page-only fields.

## Implementation shape

- Preserve verified day aggregates independently of the requested report
  window and migrate existing previous-report data without clearing the cache.
- Make cached report assembly project the requested range from durable rows.
- Coalesce normal and Spend Dashboard catch-up demand into one worker.
- Reconcile publication against durable established history before both
  CloudKit writes, and make mobile day merging completeness/revision aware.
- Retain prior verified history on scanner failures and account refreshes.
- Reduce catch-up hydration and byte budgets after correctness is proven.
- Prefer the authenticated OpenAI API on the normal background cadence and use
  one serialized WebKit fallback only when page data is genuinely required.

## Verification gates

- Alternating 30- and 365-day requests across a store reload never regress
  either projection.
- A complete `$130` history followed by a newer partial `$8` candidate remains
  `$130` plus verified new-day changes on both warm and cold iPhone paths.
- Explicit complete corrections may reduce a day.
- Repeated unchanged refreshes do not write, restart, or launch a second worker.
- The current scale class (6,156 files, including 92 files over 16 MiB, and at
  least 411,000 usage rows) remains
  bounded per pass.
- Focused Mac and mobile suites, lint, release build, and diff checks pass. A
  full repository suite is intentionally not required when the focused suites
  directly cover the changed seams.
- Packaged runtime acceptance, when separately authorized, is median aggregate
  footprint at or below 250 MiB, p95 at or below 350 MiB, no more than 50 MiB
  first-to-final-hour growth in an eight-hour soak, and zero background WebKit
  launches when direct API refresh succeeds.

## Regression found during live qualification

The compact SQLite projection populated projects and sessions but failed to
assign its projected daily report to the publication value. That left the
sync layer consuming a stale or tiny fallback even though the durable database
contained the correct spend. Separately, explicitly unknown costs could still
enter the iPhone ledger as numeric placeholders. The repair makes the compact
daily projection canonical, persists independently verified days across local
midnight while catch-up continues, and carries cost-known state through the
Mac wire payload, mobile cache, CloudKit merge, and durable ledger.

## Completed implementation

- Routine Codex scanning now has hard 16 MiB per-file and 64 MiB per-refresh
  byte ceilings, a four-file hydration ceiling, and a 512-candidate metadata
  page instead of materializing the historical corpus.
- SQLite is the canonical verified ledger. Report windows are query-backed
  projections, bounded refreshes persist deltas, and compatible predecessor
  hashes adopt without discarding established rows.
- Normal cost refresh and Spend Dashboard catch-up share one cache-identity
  worker with durable no-progress and resume semantics.
- Cost publication carries explicit completeness, revision, and exact history
  day bounds. Partial candidates cannot replace established history; complete
  corrections can reduce values; mixed Mac scopes fail closed as partial.
- The iPhone applies authoritative omission only inside an explicitly complete
  history window, so a cold reader cannot mistake a partial Mac payload for a
  deletion.
- OpenAI background refresh is API-first. Page reconciliation is limited to one
  serialized WebView, expires after one hour, and cancels and evicts idle page
  state.
- Incremental mobile refreshes now persist their merged state (including an
  empty authoritative result) so relaunch cannot resurrect stale spend data.
- Nil-email to email account identity transitions preserve only demonstrably
  better history, without conflating two known accounts.

## Verification evidence

- `make test`: 982 selections in 82 groups; 82 first-pass successes, zero
  failures, retries, or timeouts.
- Full iOS simulator test action succeeded, including 552 Swift Testing tests
  and four UI tests; the focused CloudKit merge and CWL writer rerun passed 77
  tests.
- Post-format Mac store, cache, and architecture rerun passed 155 tests.
- `swift build -c release`, parser-hash validation, SwiftFormat, SwiftLint,
  localization, branding, package, and repository audits passed.
- Runtime RSS claims remain deliberately unmeasured because QuotaKit was not
  reopened. The packaged eight-hour acceptance gate above is still required
  before assigning a measured memory number to this repair.
