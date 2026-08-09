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
  CODE_SIGNING_ALLOWED=NO test
```

For Mac local development:

```bash
./Scripts/compile_and_run.sh

# Also run the sharded test suite before packaging/relaunching
./Scripts/compile_and_run.sh --test
```

## Project Structure

| Path | Purpose |
|------|---------|
| `Sources/CodexBar/` | Mac app UI and menu bar implementation |
| `Sources/CodexBarCore/` | Provider and business logic shared by Mac targets |
| `Sources/CodexBarCLI/` | Bundled `quotakit` command-line tool |
| `Sources/CodexBarWidget/` | WidgetKit support |
| `Tests/CodexBarTests/` | macOS app/core test suite |
| `Shared/` | CloudKit, sync, and shared models |
| `CodexBarMobile/` | iOS companion app |
| `WidgetExtension/` | iOS widget extension project config |
| `Scripts/` | Build, lint, packaging, release, and audit scripts |

## Common Tasks

### Provider Scope

QuotaKit has a fixed provider inventory: Codex, Claude, Cursor, and Grok. Provider work should simplify or maintain
those four integrations rather than introduce a general provider-authoring surface. Keep their descriptors, Mac
implementations, CLI behavior, widgets, shared sync models, and focused tests aligned.

See [providers.md](providers.md) for the supported fetch and presentation contracts.

### Debug Cookie Or Credential Issues

1. Enable app logging from the Debug or Settings surface.
2. Reproduce with `./Scripts/compile_and_run.sh`.
3. Check Console.app for the running app process logs.
4. Avoid live credential probes unless the user explicitly requested them.

### Run Tests Only

```bash
make test
```

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
