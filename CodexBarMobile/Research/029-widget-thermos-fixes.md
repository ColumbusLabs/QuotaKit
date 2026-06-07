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

## Phase 0 — Apple Developer provisioning (manual, still pending)

- [ ] Register app group `group.com.columbuslabs.quotakit`
- [ ] Enable App Groups on main + widget App IDs
- [ ] Regenerate Dev + Distribution profiles
- [ ] Archive verify `CodexBarMobileWidgets.appex` embedded
- [ ] App Store Connect widget extension + privacy labels

## Phase 5 — QA

| Scenario | Status |
|----------|--------|
| Unit tests (446, all suites) | passed on iPhone 17 Pro simulator |
| Purchase → widget unlock immediately | needs device QA |
| Upgrade 153→155 migrations | needs device QA |
| zh-Hans / ja widget copy | needs simulator locale QA |
| Lock Screen accessories on device | needs device QA + Phase 0 |

## Verification Notes

- `xcodegen generate` succeeded after `project.yml` widget target updates.
- `xcodebuild test -scheme CodexBarMobile CODE_SIGNING_ALLOWED=NO -skip-testing:CodexBarMobileUITests` passed (446 tests).
- New/updated tests: `QuotaKitWidgetTests` (sanitization, pro-cache migration, store I/O), `LinkageRecordMergeTests` (legacy linkage migration), `ModelContainerFactoryTests` (legacy path discovery + sidecar copy).
