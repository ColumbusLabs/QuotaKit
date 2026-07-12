# 037 · Widget Glass Glance

- Status: `done`
- Date: 2026-07-12

## Goal

Match the focused small-widget reference for a selected quota window: compact
window badge plus provider name, a large centered remaining percentage, a
neutral quota bar, and a reset countdown on the system-provided glass surface.

## Decisions

- Redesign the small widget's Session and Weekly modes. Keep Both mode's two
  rows so the existing global setting continues to show both promised windows.
- Let WidgetKit replace the declared container background in tinted and clear
  appearances. Remove the extra opaque background outside that container.
- Keep a dark full-color fallback for iOS 17+ and use a white visual hierarchy
  that remains legible when WidgetKit switches to accented clear/tinted modes.
- Derive compact badges from real window titles when they contain a duration
  (`5-hour` -> `5H`, `7-day` -> `7D`). Use `7D` for a weekly window without a
  numeric title and the localized mode title for other fallbacks.
- Reuse the app's deterministic reset countdown formatter in the widget target
  rather than introducing a second formatting implementation.
- Remove pace and sync-age chrome from the focused small-widget presentation;
  those details remain available in Both mode, the medium widget, and the app.

## Verified

- `QuotaKitWidgetTests`: 69 tests passed on iPhone 17 Pro simulator with code
  signing disabled, including compact badge formatting, localized countdown
  catalog coverage, and 148 / 155 / 170-point render checks.
- `MobileDisplayFormattingTests`: 12 tests passed, preserving the shared reset
  formatter's rounding and English output behavior.
- The attached 170 x 170 `98%` / `7D` fixture was exported from the XCTest
  result bundle and visually inspected after correcting duplicate-header and
  vertical-layout regressions found during the render pass.
- `./Scripts/lint.sh lint` passed, including SwiftFormat, SwiftLint, i18n,
  customer-branding, and provider-palette audits.
- `make test` passed all 675 discovered selections in 57 first-pass groups with
  no failures, retries, or timeouts.
- `git diff --check` passed.
