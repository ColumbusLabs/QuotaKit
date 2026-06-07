# 005: Mac→iOS push provider name — alternatives explored

- **Status**: archive — alternatives that were considered and rejected for the push-with-provider-name work
- **Created**: 2026-04-14
- **Sibling**: [007-push-per-provider-subscriptions.md](007-push-per-provider-subscriptions.md) (the shipped design — Build 54)
- **Also**: [006-push-provider-nse.md](006-push-provider-nse.md) (Build 53 NSE design, superseded when the extension failed to wake on this container)
- **Predecessor**: [004-alert-push-cloudkit.md](004-alert-push-cloudkit.md) (the working state without provider name through Build 52)

## Goal recap

Each iPhone should display a CloudKit-triggered push that includes:
- **Provider name** (Codex / Claude / Cursor / …) — to match Mac's local notification format
- **State** (depleted / restored)
- **iPhone-current locale** (en / ja / zh-Hans / zh-Hant)

Build 52 already delivered locale + state. Build 53 adds provider name.

## Hard constraints (from prior iteration)

- Private CloudKit container `iCloud.com.columbuslabs.quotakit.mac`, Production environment
- `CKQuerySubscription` does not persist on this container
- `CKRecordZoneSubscription` with `titleLocalizationArgs` / `alertLocalizationArgs` does not persist on this container (Build 49 + Build 50 both proved this)
- Static `alertBody` (Build 48 / Build 52 baseline) **does** persist
- 20+ providers in `Sources/CodexBarCore/Providers/Providers.swift`, list grows over time
- No Background App Refresh dependency allowed (v3 silent push abandoned)
- No dedicated server, no third-party push relay, no embedded `.p8` keys
- Must not regress Build 52's working push delivery

## Research process

Three parallel research agents (2026-04-14):
1. Agent A1 challenged the "args silently drop" root-cause conclusion and enumerated the full `CKSubscription.NotificationInfo` API surface
2. Agent A2 enumerated 15 architectural approaches (the table below)
3. Agent A3 catalogued pre-test methodology and surveyed OSS CKSubscription usage with localization args

The table below is A2's enumeration. The chosen approach is variant #14 (NSE with bundled localization + locale resolved at delivery time) — see [006-push-provider-nse.md](006-push-provider-nse.md).

## The 15 approaches

| # | Approach | Output for zh-Hans iPhone, Codex provider | Scales with provider count? | Pre-testable? | Verdict |
|---|---|---|---|---|---|
| 2 | NSE + `desiredKeys` to embed provider in payload (skip the fetch) | Same as #1 | Yes | Partial | Risky — `desiredKeys` is loud-rejected on `CKRecordZoneSubscription`; would require switching to `CKQuerySubscription` which doesn't persist |
| 6 | `UNNotificationContentExtension` (custom expanded UI) | Expanded: full provider+state; collapsed: still generic | Yes | Yes | Rejected — collapsed banners + lock screen still missing provider |
| 7 | NSE + `threadIdentifier = providerID` for grouping | Same as #1, plus iOS visual grouping | Yes | Partial | Worth doing as a follow-up to #1 / #14 |
| 9 | Badge-only push, in-app banner shows full text | No banner / no lock-screen text | Yes | Yes | Rejected — fails the visible-on-lock-screen requirement |
| 10 | Silent push + NSE wake | Same as #1 | Yes | Partial | Equivalent to #1, no advantage |
| 11 | Mac embeds APNs `.p8` key + posts pushes directly | Anything we want | Yes | Partial | Rejected — `.p8` in open-source repo is a security failure (upstream rejected this in v3 era) |
| 12 | Third-party relay (ntfy.sh / Pushover) | Push appears in **third-party app**, not CodexBar | Yes | Yes | Rejected — UX disqualifying |
| 13 | Replace push with WidgetKit / Live Activity | Widget tile or Dynamic Island | Yes | Yes | Rejected — different UX surface, not a push replacement |
| 15 | Pre-register one `UNNotificationCategory` per provider | Equivalent to #4 | No | Yes | Rejected — degenerates to #4 |

## Why #14 won

Reasons #14 beat #1 (the runner-up):

- **Solves the Build 52 locale-staleness side bug as a free side effect**: Build 52 bakes the locale-resolved body into the subscription `alertBody` at sub creation time, so a user who switches iPhone language between launches sees the old language until the app re-launches. #14 resolves the locale at push delivery time inside the extension, so locale changes propagate without an app launch.
- **Same scaling profile as #1** (O(1) in provider count).
- **Same Apple-blessed mechanism** (`UNNotificationServiceExtension`).

In Build 53 the Build 52 body is left in the subscription as a fallback (preserved when the extension fails or times out), and the extension only overrides the **title** with the provider name. This keeps the locale resolution in two places (sub-creation for body fallback, extension delivery for title) and removes the staleness only for the title — but title is the primary visual differentiator vs the previous build, so the gain is meaningful regardless. A future build can move the body resolution into the extension too if desired.

## Why we didn't ship #1 + #2 hybrid

`desiredKeys` was attractive (lets the extension read provider straight from the push `userInfo` without a CloudKit round-trip), but per-Apple-doc + Agent A1's surface check, it is **loud-rejected** on `CKRecordZoneSubscription`. Switching back to `CKQuerySubscription` to support `desiredKeys` would re-introduce the persistence failure mode we resolved in Build 48. The fetch-on-arrival cost is small (zone is low-traffic, debounced 5 minutes on Mac, capped at 10 records per fetch).

## Pre-test methodology (also archived)

Three pre-test methods that proved highest-leverage during this iteration:

1. **CloudKit Console → Subscriptions tab + "Act As iCloud Account"**: log into [icloud.developer.apple.com/dashboard](https://icloud.developer.apple.com/dashboard), pick our container, switch to Production environment, click "Act As" with the test iCloud account, open Subscriptions tab. Shows server-side subscription state directly — the authoritative source of "did our save persist". This is what we should have run during Build 49 / 50 / 51 instead of relying on `allSubscriptions()` round-trips.
2. **Unit tests against pure helpers in `Shared/Notifications/QuotaZoneNotificationParser.swift`**: 7 tests cover zone-name acceptance and `userInfo` parsing edge cases. Caught one bug during development (zone name typo).
3. **`xcrun simctl push booted <bundle> payload.apns`**: would let us verify NSE invocation + content rewriting on Simulator without needing a real iPhone. Not used in Build 53 because constructing a faithful `CKRecordZoneNotification` `userInfo` is non-trivial; deferred to a future iteration if NSE behaviour proves flaky.

## OSS evidence (from Agent A3)

Surveyed 40+ Swift OSS projects via GitHub code search for `CKSubscription` + `titleLocalizationArgs` / `alertLocalizationArgs`:

- **Apple's own `apple/sample-cloudkit-privatedb-sync`**: uses `CKRecordZoneSubscription` on a private DB with a custom zone — **never sets localization args**. Uses silent push with content-available only.
- Major sync engines (`SyncKit`, `Cirrus`, `CloudSyncSession`, `Seam3`, `IceCream` via Manic-EMU, `RunningOrder`, `WWDC`, `Zavala`, `iRASPA`, …): all use `CKRecordZoneSubscription` on private DB + custom zone, **none set localization args**.
- Projects using localization args (`fluffyes/cloudkitPush`, `EVCloudKitDao`, `CloudKitchenSink`, `Conferences`, `ChitChat`, `Cauldron`): all on **public DB + default zone**, not our setup.
- The one project found combining `CKRecordZoneSubscription` + private DB + custom zone + localization args (`Bache94/ListeByBache`): treats push as unreliable and runs a 4-second polling loop in parallel.

This is a strong ecosystem signal that subscription-args-on-private-zone is unsupported in practice, even though the failure mode is not officially documented by Apple.

Whether the exact root cause is "args on `CKRecordZoneSubscription` never persist" or "args referencing un-Queryable schema fields silently drop" or "subscription cache invalidation race" remains undefined — and now moot, because #14 doesn't depend on the answer.
