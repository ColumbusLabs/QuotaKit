---
summary: "Architecture overview: modules, entry points, and data flow."
read_when:
  - Reviewing architecture before feature work
  - Refactoring app structure, app lifecycle, or module boundaries
---

# Architecture overview

## Modules
- `Sources/CodexBarCore`: fetch + parse (Codex RPC, PTY runner, Claude probes, OpenAI web scraping, status polling).
- `Sources/CodexBar`: state + UI (UsageStore, SettingsStore, StatusItemController, menus, icon rendering).
- `Sources/CodexBarWidget`: WidgetKit source target for the packaged QuotaKit widget extension.
- `Sources/CodexBarCLI`: source target for the bundled `quotakit` usage/status CLI.
- `Sources/CodexBarClaudeWatchdog`: source target for the packaged `QuotaKitClaudeWatchdog` helper process.
- `Sources/CodexBarClaudeWebProbe`: CLI helper to diagnose Claude web fetches.

## Entry points
- `CodexBarApp`: SwiftUI keepalive + Settings scene.
- `AppDelegate`: wires status controller, Sparkle updater, notifications.

## Data flow
- Background refresh → `UsageFetcher`/provider probes → `UsageStore` → menu/icon/widgets.
- Settings toggles feed `SettingsStore` → `UsageStore` refresh cadence + feature flags.
- Runtime-only provider settings flow through typed, descriptor-registered sections in `ProviderSettingsSnapshot`.
- Codex conversation-title enrichment reuses SQLite database discovery per working directory and SQLite home
  during each operation. A later operation resolves paths again so configuration changes and new database versions are visible.

## CLI login lifecycle
- `CodexLoginRunner` and `KiroLoginRunner` resolve their own executable and environment, including Codex home scoping.
- `CLILoginRunner` owns browser-waiting login processes, bounded output capture, timeout/cancellation, and optional
  device-flow progress. It returns one shared result type; provider presentations retain their own recovery messages.
- The login runner and `SubprocessRunner` share `ProcessTermination` and process-tree termination. Cancelling a login
  stops its child process, joins its progress callback task, and produces no failure alert. Timeouts retain captured
  diagnostic output, and inherited pipes cannot keep the caller waiting indefinitely.

## Concurrency & platform
- Swift 6 strict concurrency enabled; prefer Sendable state and explicit MainActor hops.
- macOS 14+ targeting; avoid deprecated APIs when refactoring.
- Cost stores share one utility serial executor per canonical database location, including symlinked cache roots and
  database files. Separate database operations do not share SQLite lock waits. Executors are weakly registered and
  released with their last store or queued job. Normal app fetches still use the separate serial scan queue;
  WAL transactions are unchanged.

See also: `docs/providers.md`, `docs/refresh-loop.md`, `docs/ui.md`.

`TTYCommandRunner` retains the POSIX error number and description when PTY allocation fails, distinguishing descriptor exhaustion from other allocation failures.
