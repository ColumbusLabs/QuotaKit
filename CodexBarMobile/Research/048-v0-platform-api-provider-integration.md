# v0 Platform API provider integration

Status: done

## Goal

Add v0 billing and rate-limit visibility to QuotaKit Mac and the iPhone
companion while preserving existing provider, notification, and sync contracts.
Mac displays the full Platform API billing details. iPhone receives only the
existing generic billing and rate-limit windows; detailed balances are deferred.

## Upstream source and behavior

Port the provider slice from upstream `steipete/CodexBar` commit
`7bb3dfe9697b56f9fd2b162ad2fe3749d6ef0f58` (v0 provider plugin). Excluded
upstream release/branding, Linux desktop, website, and social bookkeeping.

The bundled plugin requests `/v1/user/billing` and `/v1/rate-limits` from
`api.v0.dev` with a bearer API key and optional URL-encoded Scope. Token billing
uses the reported token balance and billing-cycle reset; legacy billing can
report a limit without remaining balance; rate-limit values remain in the API's
units. On-demand balance is separate from the allowance, including a real zero.
Missing balances are shown as unavailable, never synthesized. HTTP statuses,
retry-after, malformed responses, and finite numeric fields are classified and
bounded. All tests use fixture responses and a stub transport.

## QuotaKit integration

- Append `.v0` to the existing `UsageProvider` catalog and regenerate the
  provider/implementation/alias manifests with the repository-pinned generator.
- Use the established provider configuration fields: API key in `apiKey` and
  optional Scope in `workspaceID`, with `V0_API_KEY` / `V0_SCOPE` environment
  overrides. Scope is trimmed and encoded for the request.
- Add v0's Billing and Rate limit labels, CLI `rateWindowLabels`, brand marks,
  settings, docs, and three notification subscriptions at the end of the
  existing 61-provider sequence. Existing notification provider IDs and order
  are pinned as an unchanged prefix.

## Mac-to-iPhone contract

`SyncCoordinator` already converts the generic quota windows, identity, and
supported cost/budget models to `ProviderUsageSnapshot`; generic
`UsageSnapshot.details` are not included. Therefore v0's detailed balance rows
remain Mac-only, while its billing and rate-limit windows use the existing
shared snapshot, CloudKit merge, SwiftData, and widget contracts. Scope remains
local to Mac and is never included in those shared fields.

Do not add a v0-specific shared field or SwiftData property in this slice. The
repository has no generic optional detail carrier, and proving a new optional
SwiftData column against existing installs is not currently safe. The full
balance/on-demand detail should be revisited only with a real pre-change store
fixture or an independently reviewed versioned migration design.

## Persistence migration

`CodexBarSwiftDataSchema` is an unversioned `@Model` list passed directly to
`ModelContainer(for:configurations:)`. The repo has no `VersionedSchema`,
`SchemaMigrationPlan`, or archived pre-change SQLite fixture. Existing
`CWLMigrationTests` create old-style rows using the current schema and reopen
them; they do not instantiate an older compiled schema. `ModelContainerFactory`
also deletes and recreates a store after an open failure, so a failed open
cannot be treated as evidence of successful data-preserving migration. This
slice intentionally leaves the SwiftData schema and CloudKit payload unchanged.

## Verification

- `swift test --filter 'ProviderFetchErrorTests'` — 4 tests passed, including
  bounded retry delay and one-retry behavior.
- `./Scripts/test-plugin-engines.sh` — 79 tests across 7 suites passed under
  both JavaScriptCore and QuickJS; includes fixture-only v0 API/auth/error,
  scope, balance, redaction, and retry-after cases.
- `swift test --skip-build --filter 'CLIProviderWindowLabelTests|ProviderArchitectureGatekeeperTests|QuotaProviderListTests'`
  — 57 tests across 3 suites passed; provider catalog/manifest, v0 CLI window
  labels, notification identifiers/order, account-identity classification,
  and descriptor color fingerprints are covered.
- Focused iOS simulator run on iPhone 17 Pro (iOS 27) — 42 tests passed across
  provider-list, palette, branding, and widget suites, including the v0
  Billing/Rate limit window snapshot and Scope omission assertion. The v0
  assertion was subsequently moved into a separate XCTest class in the same
  already-included test source to avoid further expanding the large widget
  test class; that mechanical relocation was not rerun in Xcode.
- Repository-pinned SwiftFormat lint passed for all changed Swift files;
  strict SwiftLint passed for 13 changed core/provider/test files. The focused
  iOS test code was SwiftFormat-checked; broader legacy iOS-file SwiftLint
  findings predate this slice.
- Provider manifests match at 70 providers; all 287 localized source keys are
  present and translated. Customer-branding and provider-palette audits pass.

No live v0 account, Keychain, browser-cookie, CloudKit, release, or full-suite
validation was run.
