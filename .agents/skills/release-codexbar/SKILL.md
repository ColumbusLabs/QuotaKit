---
name: release-codexbar
description: "Release QuotaKit for macOS through signed and notarized GitHub and Sparkle publishing, or archive and upload the iPhone companion to App Store Connect and TestFlight. Use for QuotaKit release preparation, versioning, signing, notarization, appcast verification, TestFlight uploads, and live release validation."
---

# Release QuotaKit

Use the repository's current release scripts and documentation. Keep the macOS
and iOS release lanes separate, and complete only the lane the user authorized.

## Guardrails

1. Work from the QuotaKit repository and inspect the live branch, worktree,
   remotes, versions, tags, releases, and release documentation before acting.
2. Do not publish a GitHub release or upload an iOS build unless the user
   explicitly authorized that operation.
3. Use QuotaKit and Columbus Labs names, identifiers, release feeds, and
   credentials. Confirm `.mac-release.env` points to `ColumbusLabs/QuotaKit`.
4. Keep secrets out of output and the repository. Use the configured Keychain or
   environment and `Scripts/load-release-secrets.sh`; never print key material.
5. Preserve upstream-tracking automation. An ordinary release must not edit
   `version.env` upstream-alignment fields, `Scripts/check_upstreams.sh`,
   `Scripts/review_upstream.sh`, or `.github/workflows/upstream-monitor.yml`.
6. Keep distribution limited to the supported Mac app and iPhone companion
   release surfaces described below.
7. Before a Mac release, review `docs/cloudkit-deploy-audit.md` and deploy any
   required additive CloudKit Production schema changes before shipping.

## macOS Lane

Read `docs/RELEASING.md`, `docs/RELEASING-MOBILE.md`, `.mac-release.env`, and
the current `Scripts/release.sh` before changing release metadata.

Prepare the release:

1. Confirm the intended version and build number in `version.env` and inspect the
   latest tag, GitHub release, and appcast entry. Do not change upstream-alignment
   fields in the same edit.
2. Finalize the matching top `CHANGELOG.md` section with concise user-facing
   notes. The release script rejects an `Unreleased` or mismatched section.
3. Confirm the worktree is clean and release prerequisites are available.
4. Run the repo checks required by the current release documentation. Do not run
   live account probes or checks that can prompt for provider Keychain access.

Stage the signed release with the repository's first phase:

```bash
./Scripts/release.sh
```

This builds, signs, notarizes, creates the QuotaKit DMG, app ZIP, and dSYM ZIP,
pushes the version tag, and creates a draft GitHub release. Review the draft
title, notes, tag, and all three assets before continuing.

Publish and update Sparkle only after the draft review passes:

```bash
./Scripts/release.sh --finalize
```

This publishes the draft, generates and signs the appcast entry, commits and
pushes `appcast.xml`, and verifies the release assets. Treat this phase as the
live-publication boundary.

Verify the public chain:

```bash
gh release view v<VERSION> --repo ColumbusLabs/QuotaKit \
  --json tagName,name,isDraft,isPrerelease,url,assets,body
./Scripts/check-release-assets.sh v<VERSION>
./Scripts/verify_appcast.sh <VERSION>
```

Also confirm the raw appcast contains the new version, enclosure URL, size, and
EdDSA signature; the enclosure responds successfully; and the downloaded DMG
mounts and contains a stapled, Gatekeeper-accepted `QuotaKit.app`. Test the
Sparkle update from the previous public build when the release scope requires
end-to-end updater proof. A successful build or draft alone is not a release.

## iOS Lane

Read `docs/RELEASING-MOBILE.md`, `CodexBarMobile/project.yml`, and the current
`Scripts/ios_testflight_xcode.sh` before preparing an upload.

For an actual TestFlight or App Store build:

1. Update `CodexBarMobile/CHANGELOG.md` and the matching
   `MobileReleaseNotesCatalog` entry in
   `CodexBarMobile/CodexBarMobile/Models/MobileReleaseNotesCatalog.swift` for user-facing changes.
2. Increment every `CURRENT_PROJECT_VERSION` in
   `CodexBarMobile/project.yml` exactly once. Change `MARKETING_VERSION` only
   when the user explicitly requests a new marketing version.
3. Regenerate the project and run the required lint and simulator tests:

```bash
cd CodexBarMobile && xcodegen generate
cd ..
./Scripts/lint.sh lint
xcodebuild -project CodexBarMobile/CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

4. Archive and upload through the canonical direct-Xcode lane:

```bash
./Scripts/ios_testflight_xcode.sh
```

Use `--archive-only` when the user authorized archive validation but not an
upload. Use `--skip-archive --archive-path <PATH>` only to resume an already
verified archive. Do not use the deprecated upload wrapper.

After upload, verify App Store Connect accepted the exact marketing version and
build number, wait for TestFlight processing as appropriate, and confirm the app,
push extension, and widget are embedded and signed with the current QuotaKit
profiles. An archive without App Store Connect acceptance is not a completed
upload.

## Closeout

Report the exact version, build, tag or App Store Connect result, checks run,
and live verification. Preserve unrelated work and leave no temporary release
sessions, secret files, mounts, or generated artifacts that the established
workflow does not retain. Do not perform an automatic post-release version bump
unless the user explicitly requests it.
