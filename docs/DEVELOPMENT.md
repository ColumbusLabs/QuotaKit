---
summary: "QuotaKit development workflow: build scripts, logging, project structure, and common checks."
read_when:
  - Starting local development
  - Running build/test scripts
  - Troubleshooting local builds
---

# QuotaKit Development Guide

QuotaKit contains a Mac menu bar app, shared provider/sync code, and an iOS
companion app.

Some internal target and folder names still use inherited identifiers such as
`CodexBar`, `CodexBarCore`, and `CodexBarMobile`. Treat those as implementation
names. Public product copy should say QuotaKit.

## Quick Start

```bash
./Scripts/lint.sh lint
swift build
```

For iOS:

```bash
cd CodexBarMobile
xcodegen generate
xcodebuild -project CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

For Mac local development:

```bash
./Scripts/compile_and_run.sh
./Scripts/compile_and_run.sh --test
```

## Project Structure

| Path | Purpose |
|------|---------|
| `Sources/CodexBar/` | Mac app UI and menu bar implementation |
| `Sources/CodexBarCore/` | Provider and business logic shared by Mac targets |
| `Shared/` | CloudKit, sync, and shared models |
| `CodexBarMobile/` | iOS companion app |
| `WidgetExtension/` | iOS widget extension project config |
| `Scripts/` | Build, lint, packaging, release, and audit scripts |

## Common Tasks

### Add a Provider

1. Add a provider descriptor and fetcher under `Sources/CodexBarCore/Providers/`.
2. Add app-side implementation wiring under `Sources/CodexBar/Providers/`.
3. Register the implementation in the provider registry.
4. Add tests for parsing, status, and sync behavior.
5. Add mock-provider coverage when the provider affects visible UI or sync.

### Debug Cookie Or Credential Issues

1. Enable app logging from the Debug or Settings surface.
2. Reproduce with `./Scripts/compile_and_run.sh`.
3. Check Console.app for the running app process logs.
4. Avoid live credential probes unless the user explicitly requested them.

### Format And Lint

```bash
./Scripts/lint.sh lint
./Scripts/lint.sh format
```

## Distribution

Mac release defaults live in `.mac-release.env`. Public release targets should use:

- Repository: `ColumbusLabs/QuotaKit`
- Setup page: `https://columbus-labs.com/quotakit/mac`
- Appcast: `https://raw.githubusercontent.com/ColumbusLabs/QuotaKit/main/appcast.xml`

See `docs/RELEASING-MOBILE.md` and `docs/RELEASE-CHECKLIST.md` before publishing.
