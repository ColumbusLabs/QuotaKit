# Four-Provider Teardown Recovery

**Status:** `done`
**Date:** 2026-08-11

## Goal

Restore the complete QuotaKit product and lifetime entitlement surface removed
by PR #125 without rewriting public Git history or risking the existing iPhone
app container, CloudKit data, or lifetime purchase.

## Recovery boundary

- `b45cca797bcc3ba4bc7f17ae751e58e0e9b1362b` is the exact first parent of
  PR #125's merge commit.
- The first recovery commit must have the same Git tree as that commit.
- Only the reviewed headless TestFlight lane may be reapplied before recovery
  fixes and build metadata.
- PR #129 remains deferred so its four-provider assumptions are not mixed into
  the emergency restoration.

## Live exposure

- App Store Connect build 176 contains the stripped product, is internal-only,
  and was installed only on Zach's paired iPhone.
- The installed Mac app is the public pre-teardown 0.32.4.15 build and retains
  the full 67-provider configuration.
- Recovery build 177 therefore uses an in-place upgrade over build 176 as the
  real data- and entitlement-continuity test.

## Required hardening

1. Preserve cached lifetime access across transient StoreKit product-metadata
   failures.
2. Coordinate migration and authoritative clearing across app-group and legacy
   entitlement-cache locations.
3. Remove access when StoreKit reports a revoked transaction update.
4. Pin XcodeGen 2.45.4 for deterministic project generation.
5. Fail the release lane unless the app, push extension, and widget archive
   have the expected versions, bundle IDs, team, profiles, App Group, push, and
   Production CloudKit entitlements.
6. Replace the known timing-racy CLI timeout test with its deterministic
   upstream test harness.
7. Treat StoreKit environments as separate trust domains: production lifetime
   access survives TestFlight/Xcode checks, while sandbox purchases and
   revocations never leak into or erase production ownership.
8. Make entitlement refreshes revision-aware so an older asynchronous result
   cannot overwrite a newer purchase, restore, or transaction update.

## Verification gates

- Exact-tree proof for the restoration commit.
- Focused StoreKit/cache/revocation, sync, notification, widget, and release
  lane tests.
- Full Mac test suite, lint, Swift builds, and full iOS unit/UI suite.
- Fresh exact-head hosted CI.
- Archive entitlement and provisioning inspection before upload.
- App Store Connect processing and internal TestFlight visibility.
- In-place build 176 to 177 upgrade on the paired iPhone, including Pro access,
  provider/history rehydration, widgets, notifications, and mixed-version sync.

## Recovery fixtures

- StoreKit tests cover production, sandbox, Xcode, and unknown environments;
  authoritative empty entitlements; revocations; legacy/app-group cache
  migration; and deterministic purchase/restore/update races.
- The CloudKit subscription fixture starts from build 176's 12 managed
  subscriptions, retains the silent-sync and unrelated subscriptions, adds
  exactly 168 missing subscriptions, and finishes with all 180 managed IDs.
- A non-four provider (Perplexity) is persisted, the SwiftData store is closed,
  and the provider is verified after reopening the store.
- DEBUG test processes use a stable process-unique temporary legacy-cache
  base, while the Alibaba fallback helpers also use task-local temporary cache
  and in-memory Keychain stores. The full suite therefore cannot block on or
  mutate the running production app's cookie-cache lock.

Public App Store or Mac release publication is intentionally outside this
recovery until the internal candidate passes every gate above.

## Completion evidence

- Recovery build 177 was archived from the reviewed source, passed the real
  provisioning/signature/entitlement verifier, uploaded successfully, reached
  App Store Connect state `VALID`, and entered internal TestFlight testing.
- Zach upgraded the affected iPhone from build 176 to 177 in place. The app
  container and app-group preferences were preserved; the lifetime entitlement
  cache migrated from its legacy production-compatible form to explicit
  `production` provenance after StoreKit verification. Zach then confirmed the
  Pro UI remained unlocked.
- On the build 177 launch, CloudKit fetched the four provider records actually
  present for the configured Mac, reported zero deletions, applied four
  per-provider upserts, and refreshed widget timelines. Notification
  authorization completed with `didGrant: 1` and no error.
- The device completed the full subscription modify operation and its
  verification fetch without a CloudKit error. Release builds intentionally do
  not expose the DEBUG subscription diagnostic, so the exact 180 managed-ID
  postcondition remains proven by the injected build-176 fixture rather than a
  production UI count.
- Fresh hosted CI ran on the recovery head before the documentation-only
  closeout. External TestFlight submission and public App Store publication
  remained disabled throughout the recovery.
