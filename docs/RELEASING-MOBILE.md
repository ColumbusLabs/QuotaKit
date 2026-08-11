---
summary: "QuotaKit Mac and iOS release pointers."
read_when:
  - Preparing a QuotaKit Mac release
  - Preparing an iOS TestFlight/App Store upload
  - Checking appcast or GitHub release ownership
---

# QuotaKit Release Guide

QuotaKit releases are owned by Columbus Labs.

## Public Release Targets

- Repository: `ColumbusLabs/QuotaKit`
- Setup page: `https://columbus-labs.com/quotakit/mac`
- Appcast: `https://raw.githubusercontent.com/ColumbusLabs/QuotaKit/main/appcast.xml`
- Release artifacts: use the `QuotaKit` names configured in `.mac-release.env`

## Mac Release Defaults

Read `.mac-release.env` before packaging. It defines the QuotaKit app name, bundle ID, release repo, appcast URL, download URL prefix, and artifact naming rules.

The first Columbus Labs Mac release must use a Columbus Labs Sparkle signing key. Do not reuse inherited private keys or publish to inherited GitHub release feeds.

## iOS Release Defaults

The iOS app uses `CodexBarMobile/project.yml` for `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.

Before a pushed iOS release change:

1. Increment every `CURRENT_PROJECT_VERSION`.
2. Run `cd CodexBarMobile && xcodegen generate`.
3. Run `./Scripts/lint.sh lint`.
4. Run the full iPhone simulator test command in `AGENTS.md`.
5. Archive/upload with `./Scripts/ios_testflight_xcode.sh`.

## CloudKit

All release builds must use CloudKit Production for `iCloud.com.columbuslabs.quotakit`.

Before a Mac release, review `docs/cloudkit-deploy-audit.md` to decide whether CloudKit schema changes need a Production deploy.

## Safety Checks

- Confirm GitHub release drafts are on `ColumbusLabs/QuotaKit`.
- Confirm appcast entries point at `ColumbusLabs/QuotaKit` release assets.
- Confirm public setup links point at `https://columbus-labs.com/quotakit/mac`.
- Confirm no release script is targeting inherited repos.
