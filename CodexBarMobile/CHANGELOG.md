# Changelog — QuotaKit iOS

Notable changes to the QuotaKit iOS companion app are documented here.

Older build-by-build notes remain in Git history. This file now focuses on the
current Columbus Labs product surface and recent release history.

## [1.11.3 (172)] — 2026-07-17 — Codex banked reset visibility

### Added

- Codex provider details now show the backend-authoritative count of banked
  limit resets and each synced reset's exact expiration date, year, time, and
  time zone. Partial backend detail lists are identified without understating
  the available inventory.

## [1.11.3 (171)] — 2026-07-12 — Background sync reliability

### Fixed

- Background sync no longer starts a local database write after iOS closes the
  silent-push execution window, preventing repeated suspension terminations.

### Changed

- Provider presentation, colors, icons, and quota-alert subscriptions now
  recognize ClinePass, LongCat, and Neuralwatt synced from the Mac app.

## [1.11.2 (170)] — 2026-07-11 — Provider details and sync reliability

### Added

- CrossModel balances plus daily, weekly, and monthly usage, spend, token, and
  request details now sync from Mac to iPhone.
- Codex credit-limit windows now appear in companion app and widget data.

### Changed

- Provider ordering is clearer, and Sakana and Wayfinder use their branded
  presentation on iPhone.
- Small Session and Weekly widgets now use a cleaner glass-ready glance with a
  compact window badge, large remaining percentage, neutral quota bar, and
  reset countdown. Both mode keeps its two-window overview.

### Fixed

- Quota reset times and large token totals render more accurately.
- Hardened multi-account CloudKit sync and widget background refresh handling.
- Background sync no longer starts a local database write after iOS closes the
  silent-push execution window, preventing repeated suspension terminations.

## [1.11.1 (169)] — 2026-06-18 — Provider logos in app and widgets

### Changed

- Synced provider metadata for Qoder so Mac quota data displays with the
  correct name, tint, icon, and notification subscription identity on iPhone.
- Provider rows, usage cards, details, dashboard provider-share lists, and
  QuotaKit widgets now use the same provider logo assets as the Mac app. Generic
  aggregate rows keep neutral markers so provider logos only appear where they
  identify a real provider.
- QuotaKit widgets now refresh their stored snapshot directly from background
  CloudKit silent pushes, so new Mac sync data can update the widget without
  opening the app first.

## [1.11.1 (168)] — 2026-06-17 — Provider order and widget provider controls

### Changed

- The Usage tab now lets users choose the provider shown in QuotaKit widgets
  and reorder providers directly in the app. Widgets follow the selected
  provider immediately; if no provider is selected, they fall back to the saved
  Usage order.
- The provider reorder control now sits beside the live sync status as a labeled
  "Provider order" button, making the action clearer on the Usage tab.

## [1.11.1 (167)] — 2026-06-12 — Widget quota window controls

### Changed

- QuotaKit widgets now show both Session and Weekly quota windows by default
  when both are available, with a Usage Settings picker to switch all widgets to
  Both, Session, or Weekly display. Both mode keeps pace markers in the compact
  quota bars; switch to Session or Weekly when you want textual pace chips.
- The small widget sync badge is brighter, shorter, and constrained to stay
  inside the top-right corner.
- Widget weekly-window detection no longer mistakes daily or monthly day-count
  labels such as "1 day" or "30 days" for weekly quota.
- Widgets now show freshness from the phone's last synced usage timestamp, and
  request regular timeline refreshes on a WidgetKit-friendlier 15-minute cadence
  while still reloading immediately when the phone publishes fresh sync data.

## [1.11.1 (164)] — 2026-06-11 — Mobile UX performance bundle

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
