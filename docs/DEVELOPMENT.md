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
| `TestsLinux/` | Linux-specific CLI/core coverage |
| `Shared/` | CloudKit, sync, and shared models |
| `CodexBarMobile/` | iOS companion app |
| `WidgetExtension/` | iOS widget extension project config |
| `Scripts/` | Build, lint, packaging, release, and audit scripts |

## Common Tasks

### Menu Bar Status Item Teardown

Runtime removal retires a status item's autosave identity before removal and restores its saved position if AppKit
clears it. During `applicationWillTerminate`, removal keeps the identity intact: renaming a host just before exit can
leave a blank menu bar slot. Status-menu Quit requests termination after menu tracking unwinds; the termination
callback detaches menus and removes merged and provider items without hiding or renaming them. Recording status-bar
tests cover teardown order, identity, visibility, and saved-position restoration. They cannot prove native Control
Center host removal or placement after process exit.

### Add a New Provider
See the canonical [provider authoring guide](provider.md#adding-a-new-provider) for the complete flow.

1. Add the provider identity to `Sources/CodexBarCore/Providers/Providers.swift`.
2. Add the descriptor and the fetcher, parser, settings-reader, or status-probe pieces the provider needs under
   `Sources/CodexBarCore/Providers/YourProvider/`.
3. Register the descriptor from `Sources/CodexBarCore/Providers/ProviderDescriptor.swift`.
4. Add an app-side `ProviderImplementation` under `Sources/CodexBar/Providers/YourProvider/`; implementations can use
   protocol defaults when no custom UI or macOS integration is needed.
5. Add the provider's exhaustive switch case to
   `Sources/CodexBar/Providers/Shared/ProviderImplementationRegistry.swift`.
6. Add icon assets under `Sources/CodexBar/Resources/`.
7. Add focused tests under `Tests/CodexBarTests/` and, for CLI/core behavior that must run on Linux, `TestsLinux/`.

Add tests for parsing, status, and sync behavior. Add mock-provider coverage when
the provider affects visible UI or sync.

### Debug Cookie Or Credential Issues

1. Enable app logging from the Debug or Settings surface.
2. Reproduce with `./Scripts/compile_and_run.sh`.
3. Check Console.app for the running app process logs.
4. Avoid live credential probes unless the user explicitly requested them.
### Debug Menu Bar Placement

Status-item creation checks the item's saved preferred position and its matching legacy key before assigning the
autosave name. Malformed, non-finite, non-positive, and out-of-bounds positions are removed; unrelated items are
untouched, and each removed key is logged. The bound is the widest connected display's width in points plus a
512-point margin, independent of display arrangement. Finite positive positions are preserved when no display bound
is available. Unlike the older global-coordinate bound, this also clears menu-manager parking positions beyond that
range. Preferred-position repair runs on each creation, independently of the one-time hidden-visibility repair flag.
Items are created with zero length, assigned their stable autosave name, registered, then given variable length.
Startup, provider vending, and visibility recovery all use this synchronous factory; recovery keeps `codexbar-merged`.
Dictionary-backed placement tests and a recording item cover cleanup and creation order without creating live status
items. AppKit exposes no public factory taking an autosave name, so zero-length creation cannot prove how a menu
manager enumerates an item inside AppKit's factory. These tests also do not establish the writer of a position that
changes after launch; recurring placement and Bartender UUID behavior still require isolated runtime evidence.

Runtime removal and visibility changes preserve the current saved position if AppKit clears it. Runtime removal
hides the item under its stable name, removes it with that name intact, then retires the autosave identity to prevent
later cleanup from clearing the restored position. This includes startup visibility recovery when Control Center
has not hosted the items yet: resetting a visible item's name before removal exposes a new automatic identity to
menu bar managers. Replacement items keep the existing `codexbar-merged` and `codexbar-<provider>` names. During
`applicationWillTerminate`, removal instead keeps the identity intact: renaming a host immediately before exit can
leave a blank Control Center slot on macOS 26.6.2. Status-menu Quit requests termination after menu tracking unwinds
and leaves cleanup to that callback; shutdown detaches menus without hiding or renaming the items before removal.
The deterministic tests use in-memory defaults, an injected recording status bar, and a hosting probe that misses
the first startup sample to check recovery and teardown ordering, identity, visibility, and placement restoration.
They compare already-hosted relaunches with delayed hosting; they do not reproduce Sparkle or Bartender's UUID store.
Native proof must use a signed, isolated app with visibly hosted
merged and provider items: record the exact old window IDs, quit normally, confirm those windows disappear, then
relaunch and check custom positions. Also exercise runtime removal/recreation and hide/show. Unit tests cannot prove
Control Center host removal or placement after process exit. This does not diagnose older out-of-range placement reports.

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
