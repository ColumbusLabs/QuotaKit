# iOS Widgets + QuotaKit Branding

Status: `done`  
Date: 2026-06-07

## Goal

Add the first iOS Home Screen and Lock Screen widgets for QuotaKit Pro, backed only by sanitized iOS-side cached data, and clean up user-facing CodexBar branding in iOS-owned launch surfaces. This slice does not provision Apple Developer resources, change Mac provider collection, or rename internal targets/modules.

## Evidence

- `docs/launch-inventory.md` identifies the existing widget extension as macOS-only and app-group JSON based.
- iOS already maintains sanitized CloudKit/SwiftData display state through `SyncedUsageData`, `SwiftDataBridge`, and `ProviderSnapshotModel`.
- `ProductConfig` already owns QuotaKit bundle, app group, CloudKit, and StoreKit identifiers.
- Existing iOS entitlements need an app group before a WidgetKit extension can read shared app state.

## This Slice

- Add an iOS WidgetKit extension target for QuotaKit widgets.
- Write a sanitized widget snapshot from iOS after snapshot refresh/hydration.
- Share only a verified Pro entitlement cache with widgets.
- Show locked widget placeholders for Free real-data users and unlocked widgets for Pro.
- Replace user-facing iOS CodexBar branding with QuotaKit while preserving upstream attribution.

## Still Next

- Apple Developer provisioning for widget/app-group identifiers — tracked in [029-widget-thermos-fixes.md](029-widget-thermos-fixes.md) Phase 0.
- CloudKit Dashboard/schema confirmation for QuotaKit-owned containers.
- App Store Connect product setup and metadata.
- Privacy/support URLs and user-facing data deletion controls.

## Verification Notes

- `git diff --check` passed.
- `swift test --filter JSONCodecConsistencyTests` passed with 16 Swift Testing cases.
- `cd CodexBarMobile && xcodegen generate` completed and regenerated the checked-in Xcode project.
- `xcodebuild -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build` passed after fixing widget snapshot field names.
- `xcodebuild test -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO -skip-testing:CodexBarMobileUITests` passed: 438 tests in 35 suites.
- Widget tests cover JSON round-trip, redaction from preview providers with account emails, Pro cache product matching, access policy, and locked/unlocked/empty render smoke for small, medium, accessory rectangular, and accessory circular families.
- Xcode emitted repeated `com.apple.mobile.notification_proxy` device warnings for a passcode-protected connected device during simulator tests; they did not fail the final run.
