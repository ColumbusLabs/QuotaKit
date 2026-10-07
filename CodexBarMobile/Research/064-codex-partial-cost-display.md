# Codex partial cost display on iPhone

**Status:** `awaiting CI` — implementation and regression coverage are in place; hosted iOS verification is pending.

## Goal

Keep Codex's priced subtotal visible while some requests have no usable price. Clearly mark partial amounts as lower bounds, and never present an unknown zero-dollar subtotal as measured zero spend.

## Implementation

- Resolve daily cost certainty from the most specific available value: the day's `costIsKnown` flag, then the summary-level flag. A point explicitly marked known remains known when another day made the overall summary partial; markerless legacy summaries retain their previous known interpretation.
- Preserve token counts independently from cost availability, including when an unknown zero subtotal is withheld.
- Carry the per-day certainty fallback through live ledger ingestion and one-time seeding so the existing local ledger does not erase the summary marker.
- Mark dashboard, provider detail, teaser, and share-card amounts with a lower-bound indicator; use the existing translated `Partial provider data` label. Unknown zero cost remains unavailable, and incomplete data does not claim provider or model shares as complete.
- Keep the wire format, CloudKit schema, and iOS build numbers unchanged.

## Regression coverage

- `SyncModelTests` covers positive partial subtotals, unknown zero with retained tokens, and an explicitly known day under an incomplete summary.
- `CloudKitMergeTests` covers merged partial Today totals and share-card ranking semantics.
- `CWLWriterTests` and `CWLSeedTests` cover point-first certainty fallback, explicit point overrides, and legacy nil behavior.
- `CostFormattingTests` covers provider-detail display semantics and accessibility labeling.

## Verification

Source review and `git diff --check` are permitted locally. Per the upstream integration run policy, do not run local iOS tests, builds, lint, simulators, or devices. The final reviewed head must pass the hosted iOS CI jobs before this document can be marked `done`.
