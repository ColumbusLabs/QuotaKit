# QuotaKit — Agent Workflow

This repository is the Columbus Labs QuotaKit codebase. QuotaKit tracks AI quota, usage, and spend on Mac, then syncs that data to the iPhone app through iCloud.

## Build, Test, Run
- Dev loop: `./Scripts/compile_and_run.sh` kills old instances, builds, packages, relaunches the Mac app, and confirms it stays running; add `--test` for the sharded full suite.
- Quick build/test: `swift build` (debug) or `swift build -c release`; `make test` for the sharded full suite.
- Package locally: `./Scripts/package_app.sh` to refresh the Mac app bundle, then restart with the QuotaKit-owned app path for the current checkout.
- Release flow: `./Scripts/release.sh`; app metadata lives in `.mac-release.env`, repo build/signing stays in `Scripts/sign-and-notarize.sh`, and validation steps live in `docs/RELEASING.md`.

## Scope

- Primary mobile work lives in `CodexBarMobile/`.
- Shared sync code lives in `Shared/`.
- Mac-side targets still carry inherited implementation names such as `CodexBar`, `CodexBarCore`, and `CodexBarCLI`. Treat those as internal identifiers unless the task explicitly asks for a Mac rename/refactor.
- The public product name is **QuotaKit** and the company name is **Columbus Labs**.
- Current upstream alignment is recorded in `version.env` through `UPSTREAM_VERSION` and `UPSTREAM_SYNC_DATE`.

## Testing Guidelines
- Add/extend Swift Testing or XCTest cases under `Tests/CodexBarTests/*Tests.swift` (`FeatureNameTests` with descriptive test methods).
- Swift Testing: prefer backticked sentence names; no camelCase.
- Model names in tests/code: released models or clearly fictitious names only; never expose unreleased names.
- Always run `make test` before handoff; add focused `swift test --filter ...` runs for parser/provider fixes when possible.
- After any code change, run the relevant lint/build checks and fix reported format/lint issues before handoff.
- Prefer CLI/focused tests over app-bundle live tests when behavior can be verified without relaunching CodexBar.
- Never run tests/checks or ad-hoc validation that can display macOS Keychain prompts. Live provider probes, browser-cookie imports, `codexbar usage` against real accounts, and real SecItem reads must be explicitly requested; otherwise use parser tests, stubs, test stores, or `KeychainNoUIQuery`.
- macOS CI is brittle around headless AppKit status/menu tests. Prefer covering menu behavior through stable state/model seams (`MenuDescriptor`, `ProvidersPane`, `CodexAccountsSectionState`, etc.) instead of constructing live `NSStatusBar`/`NSMenu` flows unless the AppKit wiring itself is the thing under test.

## Development Flow

Use this sequence for feature and fix work:

1. Research: read relevant source, SDK docs, upstream changes, and existing data.
2. Design: record the approach in `CodexBarMobile/Research/NNN-feature-name.md` when the change is non-trivial.
3. Implementation: keep changes scoped and buildable.
4. Testing: run the narrowest useful checks, then broader checks when shared behavior changes.
5. Documentation: update changelogs, release notes, and research status as needed.
6. Commit: keep build numbers unchanged for ordinary branch or PR commits.
7. Release: bump iOS build numbers only when preparing an actual TestFlight/App Store build; archive/upload only when explicitly requested.

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

When preparing an actual iOS build for TestFlight or App Store distribution:

1. Open `CodexBarMobile/project.yml`.
2. Increment every `CURRENT_PROJECT_VERSION` value by 1.
3. Do not change `MARKETING_VERSION` unless explicitly requested.
4. Run `cd CodexBarMobile && xcodegen generate`.

Do not bump build numbers for routine local commits, review branches, PR updates,
or merges that are not being archived/uploaded as a new iOS build.

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
  CODE_SIGNING_ALLOWED=NO test
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
