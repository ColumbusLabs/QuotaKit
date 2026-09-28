# Pi native temporal projection

Status: implemented; hosted CI pending (issue #194)

The bounded Codex report projection currently reads file/day and verified/day aggregates. Its `CostUsageDailyReport` therefore has no hourly or exact event-time slices even when the scanner has parsed those rows. Pi-inclusive accounting needs a native-only temporal baseline in both fresh and reopened-cache reads.

## Design

- Derive per-file hour and event-time buckets from the already deduplicated, hydrated Codex rows during the same transaction that persists file/day aggregates. Keep the established scanner bucketing and pricing rules.
- Store compact buckets with the file generation; source replacement and alias deletion remove their old contribution in the same transaction. A pending replacement leaves the prior generation intact.
- Maintain a verified temporal baseline with the same coverage and invalidation transitions as `verified_day_aggregates`, so bounded catch-up can publish the last complete generation.
- Read temporal buckets only for the requested day window, without hydrating `usage_rows` or `token_snapshots`. Merge duplicate timestamps with the existing completeness semantics.
- Treat older stores lacking temporal rows as needing bounded regeneration. Cached presentation must not mark temporal coverage complete until that regeneration is verified.
- Track verified day coverage independently of aggregate rows so an empty verified day removes stale daily, hourly, and quota values from a retained report. Scope wider retained reports to the requested dates.

## Verification

The two disabled `PiNativeProjectionTests` are enabled. Reopened-cache, source-replacement, empty verified-day, and retained-window checks pass without raw event-ledger hydration. Focused Pi, requested-window, migration, and source-recovery tests passed (31 tests in four suites), followed by 11 tests in the two suites affected by the final calendar edit. Lint passed. Hosted exact-head CI is required before merge.
