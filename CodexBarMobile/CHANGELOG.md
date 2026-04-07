# Changelog — CodexBar Mobile (iOS)

All notable changes to the CodexBar iOS companion app will be documented in this file.

## [1.1.0 (37)] — 2026-04-06

### Changed
- **Promoted Setup Guide to a top-level Settings row.** It now sits at the very top of the first section (above About & Sync), opens the existing Setup Guide sheet on tap, and uses the `sparkles` icon.

### Removed
- The standalone "How It Works" section in Settings (previously listed 3 informational items plus a Show Setup Guide button). Now redundant with the promoted Setup Guide entry.
- The "How It Works" section inside About & Sync detail — duplicated the same information.
- Dead localization keys: `How It Works`, `Show Setup Guide`, `CodexBar on your Mac pushes usage data to iCloud`, `Data syncs automatically when both devices are online`, `This app reads the latest snapshot via iCloud Key-Value Store`.

## [1.1.0 (36)] — 2026-04-06

### Changed
- **Consolidated dev tools under a single "Developer Tools" entry** — Settings → Developer now shows one row that navigates into a dedicated page listing Raw Sync Data and Push Diagnostic. Future tools can be added there without cluttering the main Settings list.

## [1.1.0 (35)] — 2026-04-06

### Changed
- Renamed the Settings → Developer section to **Developer Tools**, now housing both "Raw Sync Data" and "Push Diagnostic". These screens are intentionally shipped to production builds so end users can self-diagnose sync/push issues (no sensitive data exposed).

## [1.1.0 (34)] — 2026-04-06

### Added
- **Push Diagnostic** developer view (Settings → Developer → Push Diagnostic) that surfaces every step of the Mac→iOS push notification chain in-app: APNS registration, CKSubscription status, UN authorization, last silent push received, last fetch result, last transitions, last local notification post, and a rolling event log
- `PushDiagnosticStore` — observable store tracking registration/subscription/push/fetch/transition/notification state with a 100-entry event log
- Manual diagnostic actions: "Fetch Now", "Re-create CKSubscription", "Post Test Local Notification", "Clear Event Log"
- `CloudSyncReader.setupSubscriptionWithDiagnostics()` wrapper that captures any error thrown from the shared `CloudSyncManager.setupSubscription()` instead of letting it be swallowed by `try?`
- `LocalNotificationManager.postDiagnosticTestNotification()` for verifying the UN pipeline end-to-end from the Diagnostic view

### Changed
- `AppDelegate` now reports every remote-notification lifecycle event (registration success/failure, push received, fetch result, transitions, notification post) into `PushDiagnosticStore` so the diagnostic view updates live
- `LocalNotificationManager.postSessionQuotaNotification` now returns `Bool` so the caller can record success/failure in diagnostics

## [1.1.0 (33)] — 2026-04-06

### Changed
- Subscription Utilization section title now uses `.headline` (was `.title3.bold()`), matching every other section header in the Cost tab
- Provider share rows are now merged directly into the Subscription Utilization section — the previous "Provider Share" sub-header (title + caption) is gone, and the cards sit under the daily chart as part of the same section
- Section subtitle updated to describe the whole section ("Session quota usage trend across synced providers.")

## [1.1.0 (32)] — 2026-04-06

### Removed
- Release notes items mistakenly appended to the 1.1.0 in-app catalog (`MobileReleaseNotesCatalog`) in build 31. The in-app catalog is reserved for major version updates and should not be touched on minor build bumps.

## [1.1.0 (31)] — 2026-04-06

### Changed
- **Subscription Utilization chart redesigned with daily granularity** — bars are now per-calendar-day (matching the Cost chart's 30-day window) instead of per-week
- **Four period summary cards** — Today, This Week, 14 Days, 30 Days, each with delta vs previous period (orange ↑ / green ↓)
- **Provider Share breakdown** — replaces raw average % with proportional share% (sums to 100% across providers), styled to match the Cost tab's Provider Share section
- 30-day raw average shown as subtitle context for each provider in the share breakdown

### Added
- 4-language localization for new strings: `14 Days`, `This Week`, and `30-day utilization share across synced providers.`

## [1.1.0 (25)] — 2026-04-01

### Added
- **Session quota push notifications** — iOS receives silent push from CloudKit when Mac detects quota changes, posts local notification for depleted/restored events
- `AppDelegate` with remote notification handler for CloudKit silent push processing
- `SessionQuotaMonitor` for detecting quota state transitions (depleted ≤0.01% / restored)
- `LocalNotificationManager` for posting user-visible notifications with sound
- Notification toggle in Settings → Usage → Notifications section (enabled by default)
- 4-language localization for all notification strings

### Changed
- App architecture upgraded: added `UIApplicationDelegateAdaptor` for background notification handling

## [1.0.0 (23)] — 2026-03-23

### Changed
- **iCloud sync upgraded from KVS to CloudKit** — each Mac now writes its own device record; iPhone merges all devices
- Multi-Mac support: providers from different Macs are combined on iPhone instead of last-write-wins
- Cost data from local-source providers (Claude, Codex, VertexAI) is summed across devices; account-level providers deduplicate
- Sync status now shows specific CloudKit errors (network, auth, quota) instead of generic "synced/not synced"
- Mac side generates a stable device UUID (persisted in UserDefaults) for CloudKit record identity
- KVS dual-write maintained for backward compatibility with older iOS builds

### Added
- `CloudSyncError` enum with CKError-to-user-readable mapping
- `MultiDeviceSyncResult` for multi-device CloudKit fetch results
- `SyncStatus` enum (`.synced` / `.syncing` / `.error` / `.noData` / `.incompatibleData`)
- `deviceID` field on `SyncedUsageSnapshot` for per-device CloudKit records
- CKQuerySubscription setup for silent push notifications on record changes
- Multi-device merge logic with per-provider cost aggregation strategy
- CloudKit + background remote notification entitlements (iOS + Mac)
- 13 new tests: multi-device merge (9), sync error mapping (14 total in suite)

## [1.0.0 (22)] — 2026-03-21

### Added
- App Store screenshot source assets under `AppStoreScreenshots/v0` and `AppStoreScreenshots/v1-screenshot`
- Finalized Chinese App Store screenshots under `AppStoreScreenshots/v1-styled`
- Matching English App Store screenshots under `AppStoreScreenshots/v1-styled-en`
- Reusable screenshot generation script for localized marketing images

## [1.0.0 (21)] — 2026-03-20

### Added
- Vibe (cyberpunk) share card style with arc gauges, neon glow, and "Did you vibe today?" headlines
- Style picker in share sheet: Classic / Vibe
- Dark and light theme support for both Classic and Vibe styles
- Save to Photos option in share sheet (NSPhotoLibraryAddUsageDescription)
- QR code and link updated to codexbarios.o1xhack.com

### Changed
- Share card headlines forced to single line across all 4 languages (minimumScaleFactor)
- In-app release notes now merge updates within the same marketing version
- AGENTS.md Step 5 updated with release notes merge rule

### Fixed
- Share sheet not showing "Save Image" option due to ShareLink Transferable limitation

## [1.0.0 (15)] — 2026-03-20

### Added
- One-tap share button on Cost tab to generate shareable cost report images
- Share sheet with period picker (Today / 7 Days / 30 Days) and live card preview
- Three share card styles: today (provider breakdown), 7-day and 30-day (stacked bar chart)
- Stacked bar chart colored by provider (top 3 + "Others" for 4+ providers)
- QR code footer linking to CodexBar project
- Feature research framework under Research/ with status tracking (draft → done → dropped)
- Research doc 001: Daily Utilization Chart (blocked-upstream, PR #565)
- Research doc 002: Cost Share Card (done)

### Changed
- CLAUDE.md simplified to project overview; AGENTS.md now holds complete 7-step workflow
- Share card charts follow dataviz conventions (largest segment at bottom for stable baseline)

## [1.0.0 (13)] — 2026-03-19

### Changed
- Refined in-app release note: replaced screenshot coverage note with clearer label readability improvement

## [1.0.0 (12)] — 2026-03-19

### Fixed
- In-app release notes now preserve the original 1.0.0 launch notes while prepending the latest build updates

## [1.0.0 (11)] — 2026-03-19

### Changed
- Usage percentage labels now keep a larger, fixed layout instead of scaling down under pressure
- Cost overview cards and trailing metrics in Cost lists now use adaptive fixed-width layouts for crisper numbers

### Fixed
- Blurry `% used` and `% left` labels on provider usage cards
- Soft or blurry trailing amount/share text in Provider Share and Model Mix rows

## [1.0.0 (10)] — 2026-03-18

### Changed
- Daily spend chart now scrolls horizontally, showing 30 days at a time with swipe for history
- Consolidated release notes into "What's New" and "Improvements & Fixes" sections
- Updated CLAUDE.md with jj workflow and commit automation rules
- Enriched demo data to 50 days with realistic spend curves

## [1.0.0 (9)] — 2026-03-17

Initial App Store release line, corresponding to the earlier Mobile `0.1.0` build.

### Added
- iOS companion app for CodexBar with iCloud Key-Value Store sync
- Provider list with dynamic rate limit progress bars and labels (Session, Weekly, Sonnet, etc.)
- Tappable provider cards with cost teaser line ("Today: $X.XX · 30d: $Y.YY")
- Provider detail view with interactive daily spend bar chart (SwiftUI Charts)
- Cost summary grid (session cost, 30-day cost, token counts)
- Budget progress bar with color-coded thresholds (red >90%, orange >70%)
- "Show remaining usage" toggle in Settings to display quota left instead of quota used
- iCloud sync error display (quota exceeded, account change notifications)
- iOS 26 Liquid Glass UI support (glass effect cards, soft scroll edges, tab bar minimize)
- Demo mode for previewing the app without Mac data
- About tab with sync status, developer info, and open source credits
- Display Mac app version and Sync version from iCloud payload in About tab
- Empty state views for waiting-for-sync and no-providers states
- Cost tab with provider share, model/service mix, and 30-day spend analysis
- In-app release notes page with the latest update summary and collapsible version history
- Privacy manifest, privacy policy, and dark mode app icon
- Onboarding flow, setup guide, and pull-to-refresh support
- Native localization for English, Simplified Chinese, Traditional Chinese, and Japanese

### Changed
- Usage and Cost charts support both Bar Chart and Line Chart styles
- 30-day charts support press-and-hold inspection for exact daily values
- Daily spend chart now scrolls horizontally, showing 30 days at a time with swipe to view history
- Chart Y-axis uses smart integer tick marks for cleaner readability
- Setting tab reorganized into Usage, Charts, and Privacy sections
- Mobile versioning is now aligned directly with the iOS app version number
- Dynamic version display now surfaces synced iPhone and Mac versions more clearly

### Fixed
- Pull to refresh now asks iCloud Key-Value Store to synchronize before reading the latest snapshot
- Mac sync status now reports missing iCloud entitlements or unavailable iCloud accounts instead of showing a false success state
- Fix iCloud sync entitlement check on iOS
