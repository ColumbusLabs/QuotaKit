# Codex partial cost display on iPhone

**Status:** `done` — implementation, independent source review and hosted iOS verification are complete.

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

The hosted iOS job in [run 37615260450](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37615260450/job/112772042724) passed on reviewed source head `96ddbb368139dab62e9bd31e65ffcc48445e4c34` using Xcode 26.3 and an iPhone simulator: 637 Swift Testing cases in 46 suites, 174 XCTest cases and 4 UI cases passed. The lint job on the same head verified all localized source keys, translations, QuotaKit branding and all 91 provider palettes. Independent GPT-6 source review cleared the certainty fallback, retained tokens, bounded windows, ledger ingestion and share calculations. Local verification was limited to source inspection and `git diff --check`; no local builds, tests or simulators, live accounts, Keychain or CloudKit operations ran.
