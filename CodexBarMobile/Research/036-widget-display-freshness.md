# Widget Display Mode + Freshness

Status: done
Date: 2026-06-12

## Summary

QuotaKit widgets now default to showing both Session and Weekly quota windows
when distinct windows are available, and the iOS app exposes a global widget
quota-window setting under Settings -> Usage. Widgets also show the Mac-confirmed
sync timestamp so a user can tell whether the glance is still useful.

## Decisions

- Keep widgets on `StaticConfiguration`; the setting is global and stored in
  app-group defaults so the app and widget extension share one display mode.
- Default missing or invalid widget-display preferences to `both`.
- Resolve `both` through distinct display windows: Session/primary plus Weekly
  when available, and only one lane when a provider exposes one usable window.
- Publish widget `lastSyncedAt` from `SyncedUsageSnapshot.syncTimestamp`, not
  the time the iOS app happened to encode the widget JSON.
- Normalize snapshot reload fingerprints by ignoring `generatedAt`, but include
  `lastSyncedAt`; this avoids churn while still reloading timelines when fresh
  phone sync data arrives.
- Schedule widget timelines around freshness boundaries, with WidgetKit still
  retaining final authority over exact refresh timing.

## Verification

- Widget preference store tests cover missing, invalid, and round-trip values.
- Resolver tests cover two distinct windows and single-window fallback.
- Widget render tests cover small, medium, accessory rectangular, and accessory
  circular families in `both` mode.
- Accessory rectangular tests check that provider, quota, and sync rows each
  produce visible pixels inside the constrained Lock Screen frame.
- Accessory rectangular tests assert the user-visible `both` detail line uses
  display-mode labels (`Session` / `Weekly`) instead of raw provider window
  labels.
- Sync freshness tests cover the strict stale-threshold decision used by the
  widget badge.
- Settings tests cover rendering the Widgets picker and saving the app-group raw
  value.
- Release notes and changelog mention that widgets show both quota windows by
  default and can be changed globally in the app.

## Verified

- `xcodebuild test -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO -only-testing:CodexBarMobileTests/QuotaKitWidgetTests` passed: 45 tests.
- `./Scripts/lint.sh lint` passed, including i18n source/catalog coverage.
- `git diff --check` passed.
