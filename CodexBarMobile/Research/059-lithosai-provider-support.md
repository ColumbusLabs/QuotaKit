# LithosAI provider support

**Status:** `done` — implementation and independent contract review complete; integration remains gated on hosted Mac/iOS verification before merge.

## Goal and approach

Adopt upstream `cd244a0f0` as a console-backed balance and optional UTC spend provider across QuotaKit Mac, widgets and iPhone. Register the new `lithosai` identifier without changing any existing identifier. Reuse the established plugin/cookie, branding, settings and sync abstractions.

## Contracts

- The full catalog grows from 88 to 89 providers. LithosAI exposes no quota window, so the 72 quota-provider identifiers and their 216 state subscriptions stay unchanged.
- `providerCost.used` is a remaining prepaid balance. The sync mapper explicitly excludes it from used/limit budgets and local spend summaries. Billing detail rows and an explicit prepaid-balance status remain available to iPhone through the existing backward-compatible provider-details payload.
- Cookie sessions require the console session and CSRF cookies. The host owns URL-scoped cookie selection and the CSRF-header echo; JavaScript receives opaque session handles. Fixtures use secure host-only records and synthetic HTTP responses.
- Keep existing non-Tier-A account grouping, bundle/CloudKit/App Group/notification identifiers, versions and build numbers. Merge the iPhone release-note detail into the existing version block and translate its key in all four supported locales.

## Evidence and verification

Independent source review confirmed the catalog append, unchanged quota subscriptions, balance semantics, scoped cookie fixtures and mobile branding/localization. Synthetic regressions assert no mobile budget, cost summary or quota windows, and retained balance/UTC-spend details. Repository-owned manifest/site/index checks confirm 89 providers. The integration's exact-head hosted gate executes Mac/plugin tests, iOS simulator coverage, lint and portable builds; do not treat this source note as evidence of test execution or binary distribution. Final merge/test evidence is recorded in `docs/upstream-sync-2026-10-03.md` and the automation ledger.
