# Replicate billing sync

Status: done

## Goal

Adapt upstream Replicate billing support for QuotaKit's Mac provider catalog and
iPhone companion without treating monthly spend as a quota allowance. Keep
credential handling isolated to the Mac and preserve existing CloudKit records.

## Product and data shape

- The Mac provider reads Replicate's billing page with a website session Cookie
  header and reports current-month spend plus an optional unused-credit balance.
  A Replicate API token is not interchangeable with that session.
- The existing `SyncBudgetSnapshot` represents spend without an allowance when
  `limitAmount <= 0`. iPhone's `BudgetProgressView` renders that as `Spend` with
  no progress bar or invented cap. No new CloudKit field or provider-ID migration
  is required; the new `replicate` provider is appended to the Mac catalog.
- Saved Cookie accounts keep their labels as per-device record-name suffixes.
  The plugin's authenticated username is preserved through account labeling
  and sent as an opaque `replicate:user` or `replicate:organization` identity,
  so iPhone keeps two same-Mac accounts separate and merges the same Replicate
  account across Macs even if local labels differ. Missing identities are not
  guessed from labels or credentials.
- Replicate is spend-only and does not become a quota-alert provider. Existing
  notification IDs and subscription ordering remain untouched.

## Verification

- Plugin and Cookie-source fixtures on both JavaScript engines; cancellation
  races use stub requests only.
- Mac account-label, CloudKit fan-out, and normalized account-identity tests.
- iPhone same-Mac and cross-Mac merge tests, spend-only budget rendering, and
  localization/source-key audits.
- Provider-manifest, scoped lint, build, and diff checks. No real browser
  cookies, Keychain access, provider account, or CloudKit write.
