# 038 · Background Suspension SQLite Lock

- Status: `done`
- Date: 2026-07-12

## Incident

TestFlight 1.11.2 (170) was terminated by iOS with RunningBoard code
`0xDEAD10CC`. The matching release dSYM symbolicated the app frames to
`SwiftDataBridge.saveChangeToken` and
`SyncedUsageData.performIncrementalRefresh`. The triggered queue was the
Core Data SQL queue for `QuotaKitStore.sqlite`.

## Root Cause

The silent-push delegate awaited the widget-only CloudKit refresh, posted an
in-memory incremental-refresh notification, and immediately invoked the
background-fetch completion handler. The notification observer launched its
own task, which could outlive the system-owned push window. iOS could therefore
suspend the process while that task committed the CloudKit change token to
SwiftData and still held SQLite's file lock.

## Fix

- Background and inactive silent-push wakes update only the widget snapshot.
  They do not start the scene model's unowned incremental refresh. A memory-only
  pending flag coalesces those pushes and triggers one incremental refresh when
  the scene next becomes active, bypassing the normal freshness gate once. The
  pending refresh waits for any older in-flight query, then runs instead of
  being swallowed by the ordinary refresh coalescer.
- Active pushes still notify the in-memory model immediately.
- Sync-related SwiftData transactions use a narrow UIKit background-execution
  lease. The lease starts immediately before local persistence and ends with
  the synchronous transaction; it never covers CloudKit network work.
- Lease cleanup is idempotent so expiration and normal scope exit cannot end
  the same UIKit task twice.

## Verification

- Seven focused routing/lease tests pass, covering active, inactive, background,
  coalesced activation, success, throw, expiration, and invalid identifiers.
- The complete mobile unit target passes all 623 tests on the iPhone 17 Pro
  simulator with code signing disabled.
- The app builds, installs, launches, and exposes its expected onboarding UI on
  the booted iPhone 17 Pro simulator.
- `./Scripts/lint.sh lint` passes SwiftFormat, SwiftLint, i18n, branding, and
  provider-palette audits; `git diff --check` passes.
- `make test` passes all 675 discovered selections in 57 first-pass groups with
  no failures, retries, or timeouts.
