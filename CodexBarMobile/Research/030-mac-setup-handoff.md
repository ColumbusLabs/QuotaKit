# 030 — Mac Setup Handoff

- **Status:** `done`
- **Date:** 2026-06-07
- **Scope:** iOS setup/update surfaces plus a Columbus Labs-hosted Mac setup page

## Problem

The iPhone onboarding and legacy-sync prompt linked directly to GitHub releases for the Mac app. That is technically useful, but awkward for TestFlight users: they are holding the phone, while the install must happen on their Mac.

## Decision

Use a branded handoff URL:

```text
https://columbus-labs.com/quotakit/mac
```

The iPhone app shares or copies this setup URL. The Columbus Labs page explains the Mac-first setup and makes the primary CTA a direct download for the latest signed/notarized Mac ZIP, with GitHub Releases kept as the secondary path for notes and older builds.

## Implementation

- Columbus Labs site adds `/quotakit/mac` with QuotaKit branding, Mac setup steps, and a direct `Download QuotaKit for Mac` CTA.
- `ProductConfig` owns the canonical setup URL and display string.
- `OnboardingView` no longer presents a phone-side Mac download button. It presents share/copy handoff actions.
- The legacy KVS update prompt reuses the same share/copy actions.
- Current in-app release notes and 4-language localization catalog describe the setup handoff.

## Validation

- Columbus Labs site: `npm run lint`, `npm run build`, and browser smoke checks for desktop/mobile `/quotakit/mac`.
- iOS: `./Scripts/lint.sh lint` and an iOS simulator build with signing disabled.
- Release gate: verify the production URL responds before TestFlight upload.
