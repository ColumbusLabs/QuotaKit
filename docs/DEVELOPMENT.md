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

## CI aggregate contract

The `lint-build-test` check requires successful lint, applicable macOS test shards and Xcode compatibility,
applicable iOS simulator tests, and both x86_64 and ARM64 entries of `build-linux-cli` when required. Mac and
Linux share the conservative docs/site path gate: source, tests, shared/mobile contracts, widgets, workflows,
and embedded Markdown resources require verification. Linux has no draft deferral. The Linux job builds
`CodexBarCLI`, runs portable `CodexBarLinuxTests`, checks CLI help, and runs synthetic private-account and
RPC-pipe proofs. Only `required=true / result=success` or `required=false / result=skipped` passes the aggregate;
failures, cancellations, missing or unknown values, and unexpected skips or executions fail it. Required Mac
tests deferred on a draft leave the aggregate incomplete. The Xcode compatibility job also builds the unsigned
Mac widget extension to verify its packaged locale resources. `Scripts/test_ci_path_gate.sh` covers the path
and result combinations, including workflow dependencies and verifier arguments.

Portable lint also compares every package identity, revision, and version in the root and widget workspace
`Package.resolved` files with an offline, read-only check and synthetic regression tests. Pin order and
workspace-specific `originHash` values are ignored. After changing dependencies, resolve the widget workspace
from the repository root and commit both resolved files together:

```bash
xcodebuild -resolvePackageDependencies -project WidgetExtension/CodexBarWidgetExtension.xcodeproj
```

The check names drifted packages and prints the repair command before packaging fails on stale pins.

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

### Optional local macOS direct test groups

The default `make test` and `./Scripts/compile_and_run.sh --test` flows keep the existing sharded SwiftPM runner.
For an opt-in local macOS run, use `./Scripts/test.sh --direct-workers 4` (between one and eight workers).
SwiftPM still builds and discovers the suite; the adapter enumerates XCTest and Swift Testing with the selected
Xcode toolchain helpers and requires an exact, duplicate-free match with `swift test list` before any group runs.
An inventory mismatch fails closed. Unsupported toolchains and Linux use the serial SwiftPM path locally.

Each group runs in a fresh process with temporary `HOME`, `CFFIXED_USER_HOME`, and `CODEX_HOME` paths, while retaining
the existing test-file isolation and Keychain suppression. Group deadlines, retry behavior, and process-group cleanup
remain active, and output is buffered per group. A failure after direct execution starts fails the run rather than
silently switching runtimes. This opt-in mode depends on SwiftPM's toolchain helper contract and should be
rechecked when updating Xcode.

Hosted macOS CI runs four path-gated shards with two direct workers per shard. The union covers the complete
SwiftPM-discovered inventory; each direct launch requires an exact, duplicate-free inventory match. The existing
120-second group deadlines, strict timeout isolation, zero ordinary failure retries and keep-going policy remain.
Focused path selections still use SwiftPM directly. No separate nonblocking smoke substitutes for required coverage.
Verified cache inputs bind content hashes, permissions and symlinks to the selected toolchain and SDK. QuotaKit
includes its Shared target paths; mismatched metadata or changed resource graphs clean compiled products while
retaining dependency checkouts. Existing dependency cache keys and storage limits remain in use.
When a required test step fails, CI prints only fresh Swift test crash reports, with credential values and local home
identities redacted.

## Project Structure

| Path | Purpose |
|------|---------|
| `Sources/CodexBar/` | Mac app UI and menu bar implementation |
| `Sources/CodexBarCore/` | Provider and business logic shared by Mac targets |
| `Sources/CodexBarCLI/` | Bundled `quotakit` command-line tool |
| `Sources/CodexBarWidget/` | WidgetKit support |
| `Tests/CodexBarTests/` | macOS app/core test suite |
| `TestsLinux/` | Portable CLI/core coverage in the Linux CI matrix |
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

### Test file isolation and native test discovery

`Scripts/test_environment.sh` removes inherited secret-shaped environment variables by name before test processes start. The sharded runner, plugin-engine tests, Makefile TTY/live lanes, and Linux portable-test jobs source the same helper. Nonsecret build and local dependency paths remain available; explicit live mode preserves its requested policy. `Scripts/test_test_environment.py` verifies the entrypoints through synthetic child processes without running provider requests or SwiftPM.

`Scripts/test.sh` denies ambient Codex credential files and provider session files in test processes and their children. Codex credential tests use `CodexCredentialFixtures` or an explicit `CodexCredentialFileAccess.withFixtureScope` for synthetic files. A child process must receive its own `FixtureScope.childEnvironment`; it does not inherit a parent's fixture grants. `Scripts/test_codex_file_isolation_child.sh` and `Scripts/test_provider_session_file_isolation.sh` provide optimized synthetic child proofs without live account access.

Settings tests skip automatic app-group migration and shared defaults discovery. Migration tests inject their own defaults, file manager, and snapshot paths. Widget snapshot tests can persist to an injected URL without reloading WidgetKit timelines.

The sharded runner retries `swift test list` once only when it detects the known missing Sparkle framework path. It validates the built framework before repairing the test bundle's `PackageFrameworks` symlink. Other discovery failures retain their original result.

### Format And Lint

`Scripts/install_lint_tools.sh` installs repository-pinned SwiftFormat and SwiftLint archives after checksum verification.
SwiftFormat targets the package's Swift 6.2 language floor. Plugin TypeScript is transpiled by the bundled runtime;
this repository does not currently install or run the upstream TypeScript, Oxlint, or Oxfmt validation toolchain.

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

## Retained process environments

Retained process-environment dictionaries use `@ProcessEnvironment`, including optional dictionaries. Its getter and setter preserve execution values, while automatic descriptions, reflection, dumps, and Swift Testing diagnostics expose only an entry count. Computed accessors and function-local dictionaries are not retained properties. Avoid explicit logging of the unwrapped dictionary.

`ProcessEnvironmentTests` exercises dictionary access and diagnostics with synthetic values; `ProcessEnvironmentStorageTests` checks declaration scopes in shipped source. Do not use real credentials or live provider imports to test redaction.
