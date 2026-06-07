# QuotaKit Pro Gates

Status: `done`  
Date: 2026-06-07

## Goal

Complete the existing iOS Pro gates before adding widgets or broad launch rebranding. Free real-data users keep one selected synced provider, basic quota display, manual refresh, setup/privacy/debug screens, and local cleanup controls. Pro and demo mode keep the full current feature surface.

## Already Done

- Launch inventory: `docs/launch-inventory.md`.
- Security model: `docs/security-model.md`.
- Data inventory: `docs/data-inventory.md`.
- Product constants: `Shared/App/ProductConfig.swift`.
- StoreKit foundation: `StoreKitPurchaseService`, `ProEntitlementStore`, StoreKit test configuration, and local entitlement cache.
- First Pro behavior: Free real-data mode shows one selected provider group; Pro and demo mode show all provider groups.

## This Slice

- Add a pure Pro feature policy for testable UI decisions.
- Gate the full Cost dashboard, cost sharing/export, provider detail history/cost charts, advanced merge controls, local cost-history settings, and visible quota notifications.
- Keep silent CloudKit sync free so the selected-provider Free experience continues to refresh.
- Keep privacy/security/troubleshooting screens available.

## Still Next

- Home Screen and Lock Screen widgets.
- Broad CodexBar-to-QuotaKit user-facing rebrand cleanup.
- QuotaKit-safe release/signing scripts and CI release posture.
- Apple Developer provisioning, CloudKit dashboard/schema confirmation, and App Store Connect product setup.
- Privacy disclosure, data deletion controls, support/privacy URLs, and App Store metadata.

## Verification Notes

- Added `ProFeatureAccess` and covered locked, Pro, demo, and merge-gate policy cases in `ProEntitlementStoreTests`.
- Added notification planning and managed quota-subscription cleanup tests in `QuotaTransitionSubscriptionsTests`.
- Added SwiftUI smoke coverage for locked/unlocked Cost tab, Provider detail Pro cards, and locked Cost settings.
- Verification run on 2026-06-07: all commands below passed. The Xcode simulator test logs include pre-existing local noise about a locked physical device notification service and unsigned test-run entitlements, but no test failures.
  - `git diff --check`
  - `swift test --filter JSONCodecConsistencyTests` (16 tests)
  - `xcodebuild -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild test -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO -only-testing:CodexBarMobileTests/ProEntitlementStoreTests` (13 tests)
  - `xcodebuild test -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO -skip-testing:CodexBarMobileUITests` (438 tests)
