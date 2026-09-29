# Sparse priority reconciliation and cost/history backlog audit

Status: done (implementation verified locally; merge tracked by the integration PR)

## Outcome

Keep Codex priority metadata proportional to recorded days while preserving turn
repricing and metadata outside the inspected window. Audit the 59 unresolved
cost/history rows against QuotaKit source at
`005c2e48efce0467d84e7cf62b9f93655cde7536`; record exact missing behavior and
verified representations in the fixed-cut ledger.

## Source evidence and scope

- Upstream ordinal 800 (`c5c253abdfd1d97f86c5021a02d7c967b70015b2`)
  replaces calendar-day enumeration with unions of recorded priority day keys.
  Inspected entries absent from fresh metadata must be removed, while entries
  outside the inspected window survive within the retained window.
- Upstream ordinal 776 (`5aa521311240bc1c5c7f9c8114c00bd76659e904`)
  clamped budgeted discovery to the first partition. Ordinal 800 later removed
  that clamp to preserve daily discovery accounting. QuotaKit's
  `CostReportingPeriod.allTime` is the last 365 days, and the fetcher clamps
  production history requests to 1...365 days. The existing
  `CostReportingPeriodTests` verifies that horizon. This row requires an
  evidence-backed exclusion rather than a new unbudgeted partition search.
- QuotaKit uses directory pages and fair scheduling. Preserve those paths and
  their work budgets, cancellation, and resume cursors.

## Implementation

Replace the priority-change helpers' calendar ranges with unions of recorded
keys filtered to the inspected range. Share the sparse replacement merge for
hashes and turn-ID lists; remove inspected empty days rather than persist empty
arrays. Retain data outside the inspected range and remove data outside the
retained range. Remove the now-unused calendar-day enumeration helper.

## Acceptance checks

Focused deterministic tests cover additions, removals, changed hashes/turn IDs,
scan margins, pre-2020 records, wider retained windows, and multi-year ranges
with work measured against occupied day keys. Run the existing reporting-period and
priority/fair-scheduling regression suites needed for these callers, relevant
lint and build checks, and the required hosted CI once the full branch is ready.

The completion surface is a reviewed, verified merge to QuotaKit `main`, plus
updated ledger accounting and issue #149. Cursor and release metadata remain
pinned until the complete applicable upstream range is dispositioned.

## Verified behavior

- 3 sparse-metadata tests passed on the final formatted source.
- 12 existing reporting-period tests passed, including the 365-day horizon.
- 39 priority/repricing, persisted-cursor, and fair-scheduling tests passed after
  updating the generated parser hash to `005a869f36400f7e`.
- Independent source review found no introduced defects in the scanner change,
  its refresh/cache consumers, or the new tests.
- Portable lint checks, strict SwiftLint, localized-key coverage, customer
  branding, and provider palette checks passed. A new-test SwiftFormat finding
  was fixed with the pinned formatter and the affected file passed recheck.

No full local package suite or live provider validation was needed for this
pure reconciliation change. Hosted CI remains the required integration gate.
