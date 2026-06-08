# 029 · Widget Thermos Fixes (Build 154 → 155+)

- Status: `done`
- Date: 2026-06-07
- Parent: [028-ios-widgets-branding.md](028-ios-widgets-branding.md)

## Goal

Close all P0–P3 Thermos review findings from the iOS WidgetKit + QuotaKit branding slice before TestFlight.

## Implemented (build 155)

### Phase 1 — Ship blockers

- [x] **1E** Unified `ProEntitlementCacheStore` to app-group `UserDefaults` with legacy standard + widget-cache migration
- [x] **1A** `WidgetTimelineRefresher` on Pro save/clear, `CodexBarMobileApp.onChange`, and cold-start Pro cache
- [x] **1B** `SWIFT_EMIT_LOC_STRINGS` on widget target; `String(localized:)` sweep; new accessory + price format keys
- [x] **1C** Linkage cache fallback from `com.codexbar.linkageCache.v1`
- [x] **1D** SwiftData legacy store copy from Application Support `CodexBar/` / `QuotaKit/`

### Phase 2 — Security & product

- [x] **2A** `statusMessage` email/credential redaction in widget snapshot builder
- [x] **2B** Pro-gated `WidgetSnapshotPublisher.publish`
- [x] **2C** Dynamic locked-widget price via `ProductConfig.launchPriceCopy`

### Phase 3 — Architecture

- [x] `WidgetSnapshotPublisher` extracted from `SyncedUsageData`
- [x] Removed unused widget `Cost` field; added `schemaVersion`
- [x] Debounced timeline reload via JSON hash
- [x] `os.Logger` on snapshot store I/O failures

### Phase 4 — Polish

- [x] Store round-trip test with injectable `baseDirectory`
- [x] Removed `displaySnapshot` passthrough on `QuotaKitWidgetEntry`

## Phase 0 — Apple Developer provisioning (manual, complete)

- [x] Register app group `group.com.columbuslabs.quotakit`
- [x] Enable App Groups on main + widget App IDs
- [x] Regenerate/fetch Dev + Distribution profiles through Xcode automatic provisioning
- [x] Archive verify `CodexBarMobileWidgets.appex` embedded
- [x] App Store Connect widget extension + privacy labels

## Phase 5 — QA

| Scenario | Status |
|----------|--------|
| Unit tests (446, all suites) | passed on iPhone 17 Pro simulator |
| Purchase → widget unlock immediately | needs device QA |
| Upgrade 153→155 migrations | needs device QA |
| zh-Hans / ja widget copy | needs simulator locale QA |
| Lock Screen accessories on device | needs device QA |

## Verification Notes

- `xcodegen generate` succeeded after `project.yml` widget target updates.
- `xcodebuild test -scheme CodexBarMobile CODE_SIGNING_ALLOWED=NO -skip-testing:CodexBarMobileUITests` passed (446 tests).
- New/updated tests: `QuotaKitWidgetTests` (sanitization, pro-cache migration, store I/O), `LinkageRecordMergeTests` (legacy linkage migration), `ModelContainerFactoryTests` (legacy path discovery + sidecar copy).
- 2026-06-08 provisioning pass: Apple Developer lists QuotaKit iOS, push, widget, Mac App IDs and the QuotaKit app group under Columbus Labs team `78PXX669LQ`; main iOS and widget App IDs have App Groups enabled. `Scripts/ios_testflight_xcode.sh --team-id 78PXX669LQ --skip-lint --archive-only` succeeded and verified `CodexBarMobileWidgets.appex` in the archive. A local App Store Connect export produced `CodexBarMobile.ipa`; exported entitlements include `group.com.columbuslabs.quotakit` on the app and widget, `iCloud.com.columbuslabs.quotakit`, CloudKit Production, and production push on the app. App Store Connect privacy metadata for QuotaKit app `6777747568` is published with privacy policy `https://columbus-labs.com/privacy` and "Data Not Collected" based on the current no-backend/no-analytics/private-iCloud sync model.
