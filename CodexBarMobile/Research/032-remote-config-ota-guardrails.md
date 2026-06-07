# Remote Config OTA Guardrails

Status: `done`
Date: 2026-06-07

## Summary

QuotaKit iOS is a native SwiftUI app, so TestFlight/App Store builds remain required for app code and UI changes. This work adds a narrow remote-config lane for safe OTA guardrails: setup URL overrides, known feature kill switches, and short public announcements.

## Boundary

- Remote config is public, non-secret JSON hosted by Columbus Labs.
- Remote config must never contain provider credentials, provider API inputs, StoreKit entitlement grants, CloudKit schema policy, or executable logic.
- Unsupported schema versions, invalid JSON, invalid responses, and non-HTTPS setup URLs fall back to cached or bundled defaults.

## Implementation

- Hosted config: `https://columbus-labs.com/quotakit/config/ios.json`.
- iOS source of truth: `RemoteConfigStore`, cached in app-group `UserDefaults`.
- App fetch cadence: launch, foreground, and manual refresh in About & Sync.
- Feature kill switches use known `FeatureGate.rawValue` IDs only; unknown IDs are ignored.

## Validation

- Unit tests cover decoding, unsupported schemas, cache fallback, defaults, setup URL override, and disabled-feature lookup.
- Site validation covers JSON validity and Next static public-file serving.
