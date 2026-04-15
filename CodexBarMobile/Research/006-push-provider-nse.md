# 006: Mac→iOS push provider via UNNotificationServiceExtension (chosen design)

- **Status**: superseded by [007-push-per-provider-subscriptions.md](007-push-per-provider-subscriptions.md). Build 53 shipped this design, but on-device verification showed the `UNNotificationServiceExtension` never woke — push titles all stayed as the iOS default "CodexBar". Most likely this CloudKit container silently strips `shouldSendMutableContent = true` the same way it strips `titleLocalizationArgs`. Build 54 moved to a per-provider-subscriptions design (see 007) which is the final shipped form. The extension target is retained but dormant.
- **Sibling**: [005-push-provider-alternatives.md](005-push-provider-alternatives.md) (the 14 alternatives explored and rejected)
- **Builds on**: [004-alert-push-cloudkit.md](004-alert-push-cloudkit.md) (Build 52 zone-split + locale-baked-at-sub-creation)

## What this design ships

For every Mac→iOS quota push, iOS now displays:
- **Title**: provider name ("Codex", "Claude", "Cursor", …) — fetched fresh per push from the triggering record
- **Body**: locale-resolved state text ("会话额度已耗尽" / "Session quota depleted" / etc.) — same as Build 52
- **Sound**: default

The text density and information shown matches Mac's local notification format ("Codex session depleted" + body) while respecting iPhone-side localization conventions (short title + descriptive body in user's locale).

## Architecture

```
Mac SessionQuotaNotifier.post(transition:provider:)
    ↓
QuotaTransitionWriter.write(transition:provider:)
    ↓
CloudSyncManager.writeQuotaTransition(state:providerName:providerID:transitionAt:)
    ↓
CloudKit private DB → QuotaDepletedZone or QuotaRestoredZone (state-specific routing from Build 50)
    ↓ CKRecordZoneSubscription fires
APNs Production with `mutable-content: 1` (NEW in Build 53)
    ↓
iPhone receives push → iOS invokes CodexBarMobilePushExtension (NEW target)
    ↓
NotificationService.didReceive(_:withContentHandler:)
    ↓
QuotaZoneNotificationParser.extractQuotaZoneID(from: userInfo)
    ↓
NotificationService.fetchLatestProviderName(in: zoneID)
    ↓ CKDatabase.records(matching: TRUEPREDICATE, inZoneWith: zoneID, desiredKeys: ["providerName", "transitionAt"], limit: 10)
    ↓ pick max by transitionAt client-side
content.title = providerName
    ↓
contentHandler(content)
    ↓
🔔 Lock screen / banner shows "Codex" + "会话额度已耗尽"
```

## Key design choices

### 1. New target: `CodexBarMobilePushExtension`

| Attribute | Value |
|---|---|
| Type | `app-extension` (UNNotificationServiceExtension) |
| Bundle ID | `com.o1xhack.codexbar.mobile.pushextension` |
| Embedded in | `CodexBarMobile.app` (main app target depends on extension) |
| Entitlements | iCloud-services = CloudKit; container = `iCloud.com.o1xhack.codexbar`; environment = Production |
| Required because | Push payload cannot carry per-record `providerName` on this CloudKit container; extension must fetch the record fresh |

### 2. `shouldSendMutableContent = true` on the subscription

| Property | Effect |
|---|---|
| `info.shouldSendMutableContent = true` | APNs adds `mutable-content: 1` to the push payload, which is what wakes the extension |
| Boolean (not a record-field reference) | Does not trigger the Build 49/50 "args silently drop" failure mode |
| Existing Build 52 sub recreation | The subscription `"already correct"` check now requires `shouldSendMutableContent`, so Build 52 subs are deleted + recreated on first launch of Build 53 |

### 3. Pure parsing helpers in `Shared/Notifications/QuotaZoneNotificationParser.swift`

- `isQuotaPushZone(_:)` and `extractQuotaZoneID(from:)` are both `public static` and unit-tested independently
- Lives in the `Shared/` framework so the test target can verify them without depending on the extension target
- Defensive against: unrelated CloudKit zones, the legacy `QuotaTransitionsZone` (so a stale Build 49 sub doesn't accidentally trigger NSE), empty `userInfo`, non-CloudKit pushes

### 4. CloudKit fetch in extension

```swift
let query = CKQuery(
    recordType: CloudSyncConstants.quotaTransitionRecordType,
    predicate: NSPredicate(value: true))
let (matchResults, _) = try await container.privateCloudDatabase.records(
    matching: query,
    inZoneWith: zoneID,
    desiredKeys: ["providerName", "transitionAt"],
    resultsLimit: 10)
let latest = records.max(by: { ($0["transitionAt"] as? Date ?? .distantPast)
                              < ($1["transitionAt"] as? Date ?? .distantPast) })
```

- Sort **client-side** so we don't depend on `transitionAt` being indexed as Sortable in the Production schema
- `resultsLimit: 10` is generous; the zone is debounced 5 minutes on Mac so realistically holds < 5 records at any moment
- `desiredKeys: ["providerName", "transitionAt"]` keeps the response small and fast

### 5. Failure tolerance

If the extension fails to fetch the record, times out (~30s budget), or the push isn't a recognised zone notification, the extension delivers the **unmodified push content** — which is still Build 52's locale-resolved body. **No regression in this failure path.**

`serviceExtensionTimeWillExpire()` cancels the in-flight task and delivers `pendingContent` (the Build 52 body) before the system kills the extension.

### 6. Concurrency model (Swift 6 strict)

- `NotificationService` is **not** `@MainActor`. The system invokes it on a private dispatch queue that is allowed to vary between `didReceive(_:withContentHandler:)` and `serviceExtensionTimeWillExpire()`.
- Mutable state (`pendingHandler`, `pendingContent`, `fetchTask`) is `nonisolated(unsafe)` because Apple guarantees a single instance per push — no actual sharing.
- The system `contentHandler` and `UNMutableNotificationContent` are wrapped in `@unchecked Sendable` boxes (`ContentHandlerBox`, `ContentBox`) so they can survive a `Task` capture under Swift 6's region-based isolation checker. The `Task` creation is pulled into a static `makeFetchTask(...)` helper because the checker has trouble reasoning about a `Task` created inside a `nonisolated(unsafe)` instance method that captures `self`'s mutable state.

## Files changed in Build 53

| File | Change |
|---|---|
| `CodexBarMobile/CodexBarMobilePushExtension/NotificationService.swift` | New — extension entry point |
| `CodexBarMobile/CodexBarMobilePushExtension/Info.plist` | New — `NSExtensionPointIdentifier = com.apple.usernotifications.service` |
| `CodexBarMobile/CodexBarMobilePushExtension/PushExtension.entitlements` | New — CloudKit Production container access |
| `Shared/Notifications/QuotaZoneNotificationParser.swift` | New — pure parsing helpers shared with tests |
| `CodexBarMobile/project.yml` | Added `CodexBarMobilePushExtension` target; main app depends on it; bumped `CURRENT_PROJECT_VERSION` 52 → 53 |
| `CodexBarMobile/CodexBarMobile/Notifications/QuotaTransitionSubscriptions.swift` | Subscription gains `info.shouldSendMutableContent = true`; "already correct" check requires it |
| `CodexBarMobile/CodexBarMobileTests/QuotaZoneNotificationParserTests.swift` | New — 7 unit tests for the parsing helpers |
| `CodexBarMobile/CodexBarMobile/Localizable.xcstrings` | New 4-language entry for the in-app release-notes bullet describing the title behaviour |
| `CodexBarMobile/CodexBarMobile/ContentView.swift` | Bullet added to `MobileReleaseNotesCatalog` 1.2.0 What's New |
| `CodexBarMobile/CHANGELOG.md` | Build 53 entry |
| `CodexBarMobile/Research/004-alert-push-cloudkit.md` | Status updated to reference Build 53 |

## Pre-tests run before real-device verification

| Test | Result |
|---|---|
| `xcodebuild build -allowProvisioningUpdates` (with new target) | ✓ BUILD SUCCEEDED |
| `xcodebuild test -only-testing:CodexBarMobileTests/QuotaZoneNotificationParserTests` (7 tests on Simulator) | ✓ all 7 passed |

## Real-device verification plan (post-ship)

User-facing QA on iPhone after TestFlight install:

1. iPhone updates to TestFlight `1.2.0 (Build 53 → likely uploads as 54 due to ASC auto-bump)`
2. Open app, grant notification permission if prompted
3. Settings → Developer Tools → Push Setup → **Verify Subscription Persistence** still passes
4. Settings → Developer Tools → Push Setup → tap **Refresh** — `Subscription List` should show 3 subs: `device-snapshot-changes`, `quota-transition-depleted`, `quota-transition-restored` (same as Build 52)
5. Mac → Preferences → Mobile → DEV **Codex Depleted** — iPhone push should show:
   - Title: "Codex"
   - Body: "Session quota depleted" / "会话额度已耗尽" (per iPhone language)
6. Repeat for Codex Restored, Claude Depleted, Claude Restored
7. Continue Build 52's regression baseline: Background App Refresh OFF + app force-quit → push still arrives with the new title

If the extension fails on a particular iPhone (e.g. CloudKit fetch times out), the user sees the Build 52 body without a title — same UX as Build 52, no information loss.

## Future work

- **Move body resolution into the extension too** to fix the locale-staleness corner case for body (currently still resolved at sub creation time)
- **Add `threadIdentifier = providerID`** for visual grouping by provider on iPhone (alternative #7 in [005](005-push-provider-alternatives.md))
- **`xcrun simctl push` CI smoke test** with a captured CKRecordZoneNotification payload, once one is captured from a real device
