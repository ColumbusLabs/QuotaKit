# Changelog — QuotaKit iOS

Notable changes to the QuotaKit iOS companion app are documented here.

Older build-by-build notes remain in Git history. This file now focuses on the
current Columbus Labs product surface and recent release history.

## [Unreleased] — Mobile UX performance bundle

### Changed

- Synced usage data now refreshes automatically when the app returns to the
  foreground (staleness-gated at 60 s), so reopening the app shows current Mac
  data without a manual pull-to-refresh. Quick app switches skip the network
  round-trip, and the foreground fetch coalesces with the launch fetch.
- Cost dashboard insights are now memoized on the snapshot identity key
  instead of being re-aggregated 2–3× per render (the Cost Window Ledger path
  previously re-ran a SwiftData fetch + re-aggregation on the main thread per
  access). First-frame rendering stays synchronous — the prior async-cache
  regression (empty first render) does not apply.
- Chart axis date labels (Cost Daily Spend, Subscription Utilization history)
  now use cached `DateFormatter` instances instead of allocating one per label
  per frame, keeping chart scrubbing smooth.

## [1.11.1 (163)] — 2026-06-10 — Paid widget refinement

### Changed

- Refined QuotaKit Pro widgets with session/weekly usage configuration and
  cleaner paid quota glance layouts.
- Redesigned the small widget glance: provider-first header, large remaining
  percent, delta chip, and a two-tone pace footer.
- Widget usage bars now share the main app's bar component, including provider
  brand tints and the triple-stripe pace marker showing deficit or buffer.

## [1.11.1 (160)] — 2026-06-07 — Observatory UI and remote guardrails

### Changed

- Full Observatory dark-first UI redesign across Usage, Cost, and Settings tabs.
- New design system with themed surfaces, line progress bars on usage cards, cost
  hero strip, and panel-based settings.
- Appearance picker (Dark / Light / System) with dark as the default for new installs.
- Unified sync status chips across Usage and Cost tabs (single demo indicator, shared
  stale threshold).
- Sync freshness chips now tick live, can be tapped to refresh, and keep showing
  refreshing or failed-refresh state after pull-to-refresh releases.
- Provider tints now mirror the Mac registry without near-collisions, stay
  readable in light and dark appearances, and keep synced-time VoiceOver status
  intact when the chip is tappable.
- Added public Columbus Labs remote config guardrails for safe setup-link overrides,
  announcements, and feature kill switches. Native app changes still require a
  TestFlight/App Store build.

## [1.11.1 (159)] — 2026-06-07 — QuotaKit logo refresh

### Changed

- App icons, Mac release icons, static docs artwork, and the Columbus Labs
  setup-page asset now use the black-and-gold QuotaKit logo.
- Onboarding and legacy sync/update prompts now share or copy the Columbus Labs
  setup page (`columbus-labs.com/quotakit/mac`) instead of sending iPhone users
  directly to a GitHub Mac download.
- Pro cache persistence no longer triggers widget reloads directly; app-level and
  snapshot-level reload paths are separated so WidgetKit updates happen from the
  correct owner.
- Widget snapshot debounce now compares encoded payload data instead of deprecated
  hash values.
- Usage cards and widgets now show the same Mac-resolved quota pace labels and
  expected-usage stripe, including deficit/reserve state and projected run-out
  timing.

## [1.11.1 (155)] — 2026-06-07 — Widget entitlement hardening

### Fixed

- Pro purchase, restore, and revoke events now reload widget timelines immediately.
- The app and widget extension now share one app-group Pro entitlement cache, with
  migration from older cache keys.
- Widget publishing moved out of synced data storage into a dedicated publisher.
- Widget snapshots redact sensitive fields and publish only the sanitized data that
  widgets need.

## [1.11.1 (154)] — 2026-06-07 — QuotaKit Pro widgets and branding

### Added

- Added the iOS WidgetKit extension with Home Screen and Lock Screen widgets.
- Added a sanitized widget cache backed by iOS app-group storage.

### Changed

- Updated user-facing iOS display names, onboarding, Settings, share cards, update
  prompts, and widget copy to use QuotaKit / Columbus Labs branding.

## [1.11.1 (153)] — 2026-06-07 — QuotaKit Pro feature gates

### Added

- Added QuotaKit Pro gates for the full cost dashboard, history charts, share
  actions, advanced merge controls, visible quota alerts, and widgets.
- Kept silent CloudKit sync free for the selected-provider experience.

## [1.11.1 (152)] — 2026-06-07 — Free provider gate

### Added

- Free real-data mode now shows one selected provider group on iOS.
- Pro and demo mode continue to show the full provider list.

## [1.11.1 (151)] — 2026-06-06 — Daily Spend chart scroll fix

### Fixed

- The Cost tab's Daily Spend chart now shows a readable viewport and scrolls through
  longer history windows instead of compressing every day into one screen.

## [1.11.0 (149)] — 2026-06-04 — Usage provider search

### Added

- Added provider search at the top of the Usage tab.

## [1.10.0] — 2026-06-03 — Synced provider detail improvements

### Added

- Added DeepSeek usage and cost detail.
- Added Codex Spark and Antigravity quota lanes.
- Added cost request counts and synced currency display.

## [1.9.0] — 2026-05-29 — Cost dashboard improvements

### Changed

- Improved Cost Overview, Daily Spend, model mix, and Codex standard/fast split
  presentation.
- Added the opt-in local Cost Window Ledger for longer on-device cost history.
