# Changelog — CodexBar Mobile (iOS)

All notable changes to the CodexBar iOS companion app will be documented in this file.

## [1.2.0 (53)] — 2026-04-14

### Added
- **Push notifications now include the provider name as the title.** Mac local notifications have always shown e.g. "Codex session depleted" — iOS push from Build 52 only showed the state ("会话额度已耗尽") without provider. Build 53 closes this gap via a new `UNNotificationServiceExtension` (`CodexBarMobilePushExtension`) target that intercepts the push, fetches the latest `QuotaTransition` record from the triggering zone, reads `providerName`, and sets it as `content.title`. The Build 52 locale-resolved body is preserved as `content.body`, so a Chinese iPhone now sees title "Codex" + body "会话额度已耗尽" instead of just "会话额度已耗尽".

### Architecture notes
- The extension target carries its own iCloud + CloudKit container entitlements (Production environment) so it can fetch records from the same private database the main app uses.
- Subscriptions now set `info.shouldSendMutableContent = true` so APNs flags pushes with `mutable-content: 1`, which is what wakes the extension. This boolean does not reference any record fields, so it does not trigger the Build 49/50 "args silently drop" failure mode (`titleLocalizationArgs` / `alertLocalizationArgs` referencing record fields). The "already correct" check on existing subscriptions is updated to require `shouldSendMutableContent`, so Build 52 subs are recreated on first launch of Build 53.
- Extension fetch path: `CKQuery(recordType: "QuotaTransition", predicate: TRUEPREDICATE)` against the state-specific zone with `desiredKeys: ["providerName", "transitionAt"]`, sorted in code by `transitionAt` (no Sortable schema requirement). If the fetch fails or times out (~30s budget), the extension delivers the unmodified push content — same UX as Build 52, no regression.
- Pure parsing helpers moved to `Shared/Notifications/QuotaZoneNotificationParser.swift` so the test target can verify them without depending on the extension target. Seven new unit tests in `CodexBarMobileTests/QuotaZoneNotificationParserTests.swift` cover zone-name acceptance, legacy-zone rejection, empty/non-CloudKit `userInfo` handling.

### Research
- 15 alternative architectures for adding provider-in-push were enumerated by parallel research agents and are documented in `Research/005-push-provider-alternatives.md`. The chosen `UNNotificationServiceExtension` design (matching alternative #14 in that doc) is fully described in `Research/006-push-provider-nse.md`.

## [1.2.0 (52)] — 2026-04-13

> **Version label note:** `xcodebuild -exportArchive` auto-bumps `CFBundleVersion` on App Store Connect collision. The commit that produced this build (`8654c6d7`) was authored with `CURRENT_PROJECT_VERSION = 51` but uploaded as 52 because 51 was already present on ASC. The `project.yml` bump 51 → 52 in the subsequent commit reconciles the label.

### Fixed
- **Push notification subscription persistence — regression from Build 51 fixed.** Build 51 (the commit that shipped as TestFlight 52 — see label note above; the preceding TestFlight 51 was labelled "Build 50" in the commit that produced it) tried to use `CKSubscription.NotificationInfo.titleLocalizationArgs = ["providerName"]` on the assumption that `providerName` (present in the Production schema since the post-Build-48 Shared changes) was safe to reference. On-device verification proved otherwise: `allSubscriptions()` returned only the legacy `device-snapshot-changes` sub after install, same failure mode as the earlier arg-stripping build (commit `65960ac8`). **Any subscription carrying args is silently dropped by CloudKit on this container, regardless of which field the args reference.**

### Changed
- **Push notification text is now localized on the iOS side via `String(localized:)`.** The `alertBody` is resolved at subscription-creation time against the iPhone's current locale (using the pre-translated `Push.QuotaDepleted.body` / `Push.QuotaRestored.body` keys in `Localizable.xcstrings`) and baked into the subscription payload as a literal string. CloudKit delivers that string verbatim at push time — no args, no server-side substitution. Each iPhone sees the push in its own language (en / ja / zh-Hans / zh-Hant); Mac-side language is irrelevant.
- If the user switches iPhone locale between sessions, the push text updates on next app launch: the `"already correct"` check compares the stored `alertBody` against a freshly-resolved `String(localized: …)`, mismatches, and recreates the subscription with the new locale's text.
- The Build 50 zone split (`QuotaDepletedZone` / `QuotaRestoredZone`) is **retained**. State differentiation still comes from the zone, which is how iOS knows at setup time which localized body to bake into which subscription.

### Notes
- Definitive takeaway recorded in `Research/004-alert-push-cloudkit.md`: subscription localization args are unusable on this CloudKit container. Pass-through-from-record designs (Plan A) are not viable. The replacement pattern is iOS-side `String(localized:)` at subscription-creation time, keyed off the zone (which is state-specific).

## [1.2.0 (51)] — 2026-04-13

> **Version label note:** This entry was committed as "(build 50)" in commit `c899e997` (`project.yml` = 50), but `xcodebuild -exportArchive` auto-bumped the upload to 51 after App Store Connect rejected 50 as a duplicate. TestFlight delivered build 51. **Build 51 turned out to have a regression (see 52 below) — iOS `allSubscriptions()` returned only the legacy `device-snapshot-changes` sub, the two new quota subs did not persist.**

### Added (attempted — regressed)
- **Locale-aware Mac→iOS push notifications.** Each iPhone was intended to render the quota push in its own locale (English / 简体中文 / 繁體中文 / 日本語) using the pre-translated `Push.QuotaDepleted.*` and `Push.QuotaRestored.*` keys in `Localizable.xcstrings`. Mac writes only the untranslated `providerName` field into the record; CloudKit was to substitute it into the title template at push time via `titleLocalizationArgs = ["providerName"]`, and iOS was to resolve the templates against its current locale.

### Changed
- **Quota transition state differentiation moved from predicate to zone.** Instead of a single zone-wide subscription with a static `alertBody = "Session quota changed"`, iOS now carries two `CKRecordZoneSubscription`s — one on the new `QuotaDepletedZone` and one on `QuotaRestoredZone` — each with its own localization key. The split lets each subscription own a static `titleLocalizationKey` / `alertLocalizationKey` while staying on the persisting subscription type (`CKRecordZoneSubscription` — `CKQuerySubscription` is still silently non-persisting on this container).
- `CloudSyncManager.writeQuotaTransition` picks the destination zone from the transition state and drops `notificationTitle` / `notificationBody` parameters (no longer needed). `recordName` is now `(providerID, hourBucket)` — state is implicit in the zone.
- The Build 42–49 legacy subscription `quota-transition-zone-sub` is explicitly deleted on upgrade. The legacy `QuotaTransitionsZone` is left in place (no harm: Mac no longer writes to it).

### Notes
- **No CloudKit Dashboard schema deploy is required for this change.** Zones are created on-demand, and the only field referenced by subscription args (`providerName`) has been in the Production schema since Build 48. This avoids the Build 49 (`65960ac8`) failure mode where args referencing undeployed fields caused subscriptions to silently not persist.
- Covers the v4 push notification iteration through Builds 43–49 (subscription type, DB, zone, localization). See `Research/004-alert-push-cloudkit.md`.

## [1.2.0 (42)] — 2026-04-08

### Added
- **Mac→iOS push notifications, v2 (CloudKit alert push design).** When a session quota becomes depleted or restored on the Mac, iPhone receives a visible push notification ("Codex" / "Session quota depleted") delivered directly by APNs without the iOS app needing to wake up. **Background App Refresh is no longer required.** See `Research/004-alert-push-cloudkit.md` for the full design rationale.
  - Mac side: when a transition is detected, write a small `QuotaTransition` record to CloudKit (provider name + state + timestamp + deviceID), debounced 5 minutes per (provider, state).
  - iOS side: two `CKQuerySubscription`s on `QuotaTransition` (one filtered by `state == "depleted"`, one by `state == "restored"`), each with a `notificationInfo.titleLocalizationKey` + `titleLocalizationArgs = ["providerName"]` that lets CloudKit fill in the provider name from the record at push time.
  - Localized in 4 languages (en / ja / zh-Hans / zh-Hant).
- **Independent Mac and iOS notification toggles.** Mac local notifications (Settings → General) and iOS push notifications (Mac Settings → Mobile → "Push notifications to iOS") are now decoupled. You can keep Mac silent and still get alerts on your iPhone, or vice versa, or both, or neither.
- **Mac DEV "iOS Push Test" buttons** (Settings → Mobile, debug build only) — writes a real `QuotaTransition` record so the full pipeline can be exercised end-to-end without waiting for an actual quota change.

### Changed
- `UsageStore.handleSessionQuotaTransition` refactored: transition computation moved before the `sessionQuotaNotificationsEnabled` gate, so the Mac local notification path and iOS push path can be controlled independently. Existing Mac local notification behaviour (gated by `sessionQuotaNotificationsEnabled`) is preserved unchanged.

### Notes
- Compared to the v1 silent-push design (rolled back in build 41): no Background App Refresh dependency, no UN authorization required for the silent-push path, no iOS app wake-up needed, no client-side baseline tracking, no diagnostic infrastructure. Net deletion of ~700 lines from build 40 → 41 → 42.

## [1.2.0 (41)] — 2026-04-08

### Removed
- **Mac→iOS push notification feature, in its entirety.** The CloudKit silent push (`shouldSendContentAvailable=true`) architecture is dropped because it requires Background App Refresh to be enabled on the device — and even then is silently throttled by iOS in many real-world conditions. The feature will return in a future release built on a different architecture (alert push triggered by a small server-decided record, no client-side wake-up needed).
- `AppDelegate.swift` (remote notification handler), `SessionQuotaMonitor.swift` (transition detection), `LocalNotificationManager.swift` (local notification posting), `PushDiagnosticStore.swift` (debug store)
- iOS Push Diagnostic developer tool and its navigation entry under Developer Tools
- iOS "Session quota notifications" toggle in Usage Setting
- iOS `aps-environment` entitlement and `UIBackgroundModes` from `Info.plist`
- Mac `MacPushDiagnostics.swift` (Mac-side debug pane) and the entire DEV "iOS Push Testing" section in `PreferencesMobilePane`
- Mac "Push notifications to iOS" toggle and `notificationPushToiOSEnabled` setting
- `SyncCoordinator.pushTestSnapshot` and the test-lock plumbing
- `CloudSyncManager.setupSubscription` and `subscriptionID` constant

### Notes
- iCloud data sync (Mac→iOS usage data display) is unaffected — that path still uses `pushSnapshot` / `fetchAllDeviceSnapshots` on the existing custom zone.
- The `DeviceSnapshotsZone` custom record zone is intentionally kept (rather than reverting to `_defaultZone`) so the future Plan B work can reuse it without another data migration.

## [1.2.0 (40)] — 2026-04-08

### Added
- **`UIBackgroundModes: fetch`** in Info.plist alongside the existing `remote-notification`. Apple's `CKQuerySubscription` documentation explicitly requires both Background Modes to be enabled for silent push notifications to wake the app. The previous build was missing `fetch`.
- **Runtime Environment** section in Push Diagnostic showing the values that actually shipped in the signed binary, not what the source files claim:
  - `aps-environment` read from `SecTaskCopyValueForEntitlement` — proves whether the device registered with Sandbox or Production APNs
  - `icloud-container-environment` — must match Mac side
  - `Background App Refresh` status — required for silent push delivery
  - `Low Power Mode` — iOS throttles silent push when on
  Mismatches are highlighted in orange so the user can spot them at a glance.

## [1.2.0 (39)] — 2026-04-08

### Fixed
- **CloudKit silent push delivery (root-cause fix)** — `DeviceSnapshot` records now live in a custom record zone (`DeviceSnapshotsZone`) instead of `_defaultZone`, and iOS subscribes via `CKRecordZoneSubscription` instead of `CKQuerySubscription`. The previous architecture was the documented dead-end for private-database silent push: query subscriptions on the default zone do not deliver pushes reliably (Apple's official `apple/sample-cloudkit-privatedb-sync` uses the same custom-zone + zone-subscription pattern). On first launch the iOS app self-heals: it queries the server for the existing subscription, deletes the legacy `CKQuerySubscription` if found, and creates a fresh `CKRecordZoneSubscription` bound to the current APNs device token.

### Changed
- `CloudSyncManager.fetchAllDeviceSnapshots()` now reads from BOTH the custom zone (where build 39+ Macs write) and the default zone (where pre-39 Macs may still be writing). Snapshots are deduped by `deviceID` keeping the most recent `syncTimestamp` per device, so the iOS app stays correct during the cross-device migration window.
- `CloudSyncManager.ensureCustomZoneExists()` and `setupSubscription(forceRecreate:)` use a fetch-first self-healing pattern: every call queries the server's actual state instead of trusting a local UserDefaults flag. This is robust to iCloud account switches, manual server-side resets, and external dashboard deletions.
- Push Diagnostic "Re-create CKSubscription" button now passes `forceRecreate: true`, bypassing the no-op fast path so the user can manually refresh the device-token binding after a TestFlight reinstall.

## [1.2.0 (38)] — 2026-04-06

Marketing version bump that rolls up all the utilization, multi-device sync, and Settings reorganization work since 1.1.0.

### Added
- **Subscription Utilization section in the Cost tab** — 30-day daily bar chart aligned with the cost chart, four period summary cards (Today / This Week / 14 Days / 30 Days) each with delta vs the previous period, and an inline Provider Share breakdown that shows each provider's proportional share of total utilization (sums to 100%).
- **Subscription Utilization History chart on each provider detail page** — scrollable per-period bars (V4 Capsule style) covering session, weekly, and opus limits.
- **Push Diagnostic developer tool** — Settings → Developer Tools → Push Diagnostic. Surfaces APNS registration, CKSubscription state, UN authorization, last silent push, fetch/transition/notification results, and a 100-entry rolling event log. Manual actions: Fetch Now, Re-create CKSubscription, Post Test Local Notification, Clear Log.
- **Multi-device utilization merge** — utilization entries from all Macs are combined and deduped by `(hourSlot, resetEpoch)` so the chart stays consistent no matter how many devices report.
- Setup Guide promoted to a top-level Settings row (above About & Sync); tapping opens the existing onboarding sheet.

### Changed
- Provider breakdown in the Cost tab now shows proportional share (summing to 100%) instead of raw average percentages, matching the visual style of the cost Provider Share section.
- Subscription Utilization section title uses `.headline` to match every other Cost-tab section header.
- Developer Tools consolidated under a single Settings entry that navigates into a dedicated container page listing Raw Sync Data and Push Diagnostic.
- About page build timestamp is forced to `en_US` locale regardless of system language (app is English).

### Removed
- "How It Works" section from Settings (previously listed 3 informational items plus a Show Setup Guide button) — redundant with the promoted Setup Guide entry.
- "How It Works" subsection inside About & Sync detail — duplicated the same info.
- Dead localization keys for the removed strings.

### Fixed
- CloudKit utilization merge now picks the entry with the freshest `capturedAt` per hour bucket instead of the one with more entries — prevents stale data from an inactive Mac from overwriting fresh data from an active one.

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
