# Cost Freshness Publication

**Status:** done
**Date:** 2026-08-23

## Problem

QuotaKit can have a current local Codex cost snapshot while the iPhone Cost
dashboard still reports zero for today. Cost and quota refresh independently on
the Mac, but the shared cost summary does not carry its own freshness. Mobile
therefore deduplicates Cost Window Ledger rows and invalidates its Cost-tab
cache using the provider quota timestamp. A cost-only update with an unchanged
quota timestamp can be rejected as redundant. The Mac sync observer also
re-arms only after an awaited CloudKit push, so a token-cost mutation during an
in-flight push can be missed. Finally, the Cost dashboard maps an absent today
row to numeric zero and renders it as "No spend today."

## Authority and freshness contract

- `ProviderUsageSnapshot.lastUpdated` remains the freshness authority for
  quota windows, provider status, and provider-level merge selection.
- `SyncCostSummary.costUpdatedAt` is an additive optional wire field describing
  the newest cost-bearing input included in that summary. It is the payload
  revision used for ledger writes and cache invalidation.
- `SyncCostSummary.totalCostUpdatedAt` is the freshness of the source that
  supplied the displayed aggregate/daily totals. It may be older than the
  payload revision when a newer dashboard response contributes only breakdown
  metadata. Legacy payloads omit both fields and mobile materializes the
  contributor provider timestamp before multi-device merging.
- `SyncCostSummary.sourceRevisions` retains each cost-bearing source revision
  independently. Aggregate maxima cannot represent a subordinate dashboard or
  scanner update when another source already has a later timestamp.
- The local cost scanner remains authoritative for local Codex total cost. The
  OpenAI dashboard contributes service breakdowns and may advance the cost
  summary revision, but delayed dashboard data cannot replace a local total.
- Day availability is explicit. A current-day point with zero cost is a
  reported zero; an absent current-day point is unavailable. A session fallback
  is eligible only when its effective cost freshness is in the current local
  calendar day.
- History completeness remains independent from freshness. The existing
  complete > legacy > partial reconciliation order continues to protect a
  complete report from a partial rebuild.

## Design

1. Add optional `costUpdatedAt` and `totalCostUpdatedAt` fields to
   `SyncCostSummary`, populate them from the Mac cost sources, preserve their
   distinct revision/display semantics through history reconciliation and
   CloudKit multi-device merge, and leave `ProviderUsageSnapshot.lastUpdated`
   unchanged.
2. Turn Mac publication into a coalescing drain. Observation re-arms before the
   first network suspension; a mutation during a push marks one trailing push
   pending instead of being discarded.
3. Use the full per-provider `(payload revision, displayed-total revision,
   per-source revision vector)`
   vector for Cost Window Ledger writes, legacy blob seeding, and Cost-tab
   cache identity. Cache identity retains every unmerged device contributor;
   persist both ledger revisions so either dimension can advance independently,
   and schedule cache expiry at both the one-hour stale boundary and local
   midnight.
4. Resolve today spend through one availability-aware helper used by provider
   details, blob aggregation, and ledger aggregation. Render unavailable and
   partial states honestly instead of converting them to `$0.00`.
5. Keep the change migration-free. The field lives in existing encoded blobs;
   old clients ignore it and new clients use the provider timestamp fallback
   for old producers.

## Compatibility and recovery

- Old Mac + new iOS: cost freshness falls back to provider freshness.
- New Mac + old iOS: the optional fields are ignored.
- New Mac + new iOS: cost-only updates overwrite stale ledger rows and
  invalidate the Cost dashboard cache.
- No ledger clearing is required. The next fixed Mac publication has a newer
  cost revision and heals the affected current-day row through normal ingest.
- The blob path remains available if the Cost Window Ledger aggregation fails.

## Verification

- Shared wire tests cover new/legacy payloads and freshness reconciliation.
- Mac coordinator tests block a push, publish one or more cost changes, and
  prove exactly one trailing push carries the newest cost.
- Mobile writer and merge tests cover equal provider timestamps with newer cost
  timestamps, legacy fallback, cross-device freshness, and breakdown retention.
- Cache tests prove every provider's cost-only revision invalidates insights
  and the time-based stale transition invalidates without new sync data.
- Model/view tests cover positive, explicit zero, unavailable, stale, partial,
  and local-midnight behavior on both blob and ledger paths.
- Final gates are focused tests, lint, `swift build`, `make test`, and the
  headless iOS simulator test command when its runtime is available. Tests must
  not perform live provider or Keychain access.
