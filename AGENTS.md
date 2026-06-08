# QuotaKit — Agent Workflow

This repository is the Columbus Labs QuotaKit codebase. QuotaKit tracks AI quota, usage, and spend on Mac, then syncs that data to the iPhone app through iCloud.

## Scope

- Primary mobile work lives in `CodexBarMobile/`.
- Shared sync code lives in `Shared/`.
- Mac-side targets still carry inherited implementation names such as `CodexBar`, `CodexBarCore`, and `CodexBarCLI`. Treat those as internal identifiers unless the task explicitly asks for a Mac rename/refactor.
- The public product name is **QuotaKit** and the company name is **Columbus Labs**.
- Current upstream alignment is recorded in `version.env` through `UPSTREAM_VERSION` and `UPSTREAM_SYNC_DATE`.

## Development Flow

Use this sequence for feature and fix work:

1. Research: read relevant source, SDK docs, upstream changes, and existing data.
2. Design: record the approach in `CodexBarMobile/Research/NNN-feature-name.md` when the change is non-trivial.
3. Implementation: keep changes scoped and buildable.
4. Testing: run the narrowest useful checks, then broader checks when shared behavior changes.
5. Documentation: update changelogs, release notes, and research status as needed.
6. Commit: bump iOS build numbers only when preparing a Git commit for push.
7. Release: archive/upload only when explicitly requested.

## iOS Documentation Rules

- Update `CodexBarMobile/CHANGELOG.md` for iOS user-facing or App Review relevant changes.
- Update `MobileReleaseNotesCatalog` in `CodexBarMobile/CodexBarMobile/ContentView.swift` for in-app release notes.
- Same `MARKETING_VERSION` means the same release-notes block; merge related details instead of creating duplicate entries.
- Mark research docs `done` after the implemented behavior is verified.

## Version Control

Use normal Git only for this repository. Do not use alternate VCS wrappers for QuotaKit commits or pushes.

```bash
git status --short --branch
git add -A
git commit -m "message"
git push origin main
```

Do not push to `upstream`. Push QuotaKit work to `origin`, which is `https://github.com/ColumbusLabs/QuotaKit.git`.

## iOS Build Numbers

When preparing a pushed iOS change:

1. Open `CodexBarMobile/project.yml`.
2. Increment every `CURRENT_PROJECT_VERSION` value by 1.
3. Do not change `MARKETING_VERSION` unless explicitly requested.
4. Run `cd CodexBarMobile && xcodegen generate`.

## Localization

The current iOS build pipeline requires every new user-facing `String(localized:)` key to be present in `CodexBarMobile/CodexBarMobile/Localizable.xcstrings` for all supported app locales, with every entry marked `translated`.

Do not remove runtime localization files as part of public repository cleanup unless the product localization policy is intentionally changed and the lint/build scripts are updated at the same time.

## Testing

Common checks:

```bash
./Scripts/lint.sh lint

xcodebuild -project CodexBarMobile/CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

Never run tests/checks or ad-hoc validation that can display macOS Keychain prompts unless the user explicitly asks for live provider validation; use parser tests, stubs, test stores, or `KeychainNoUIQuery`.

## Release Configuration

Mac release configuration is QuotaKit-owned:

- Repo: `ColumbusLabs/QuotaKit`
- Setup page: `https://columbus-labs.com/quotakit/mac`
- Appcast: `https://raw.githubusercontent.com/ColumbusLabs/QuotaKit/main/appcast.xml`
- Release artifacts should use `QuotaKit` names from `.mac-release.env`.

Before a Mac release, audit CloudKit Production schema requirements with `docs/cloudkit-deploy-audit.md`.

## Public Repo Identity

Public-facing docs, GitHub metadata, release notes, support links, appcast entries, and install instructions should use QuotaKit / Columbus Labs framing. Upstream references belong in explicit provenance, credits, or sync-planning context.
