# QuotaKit

QuotaKit is a private, maintainable dashboard for the four AI tools used every day:

- Codex
- Claude
- Cursor
- Grok

The Mac app collects quota, usage, and supported cost data locally. It can sync sanitized snapshots through the user's private CloudKit database so the iPhone companion, widgets, and quota notifications stay useful away from the Mac. The bundled `quotakit` command-line tool exposes the same provider data to local scripts.

This repository retains inherited internal target names such as `CodexBar`, `CodexBarCore`, and `CodexBarMobile`. The product name is QuotaKit.

## What Is Included

- A macOS menu bar app for Codex, Claude, Cursor, and Grok.
- Provider quota windows, reset timing, account context, and pace projections where the provider supplies them.
- Local usage and cost history for supported providers.
- Private Mac-to-iPhone CloudKit sync.
- Mac and iPhone widgets.
- Quota depletion, restore, threshold, and predictive-pace notifications, including optional push to iPhone.
- A macOS CLI for usage, cost, diagnostics, local hooks, and private dashboard integrations.

QuotaKit intentionally has a fixed four-provider scope. Retired provider entries in an existing config are left inert for migration safety; they are not fetched, displayed, synced, or offered in settings.

## Daily Setup

1. Build and launch the Mac app with `./Scripts/compile_and_run.sh`.
2. Enable the providers you use in Settings.
3. Turn on iCloud Sync if you want the iPhone companion, widgets, and push notifications.
4. Install the bundled CLI from Advanced settings if local scripts need the data.

The Mac remains the provider-facing collector. The iPhone app reads the private synced snapshots and does not independently sign in to provider accounts.

## Provider Notes

- [Codex](docs/codex.md) — OAuth or local Codex CLI, with optional ChatGPT usage-dashboard enrichment.
- [Claude](docs/claude.md) — OAuth, Admin API, Claude CLI, or claude.ai session data as configured.
- [Cursor](docs/cursor.md) — Cursor account usage and billing windows from the configured local/web session.
- [Grok](docs/grok.md) — Grok CLI billing data with a grok.com session fallback.
- [Provider overview](docs/providers.md) — the authoritative four-provider data-source and capability matrix.
- [CLI](docs/cli.md) — local command-line usage.

## Privacy

Provider collection happens on the Mac. QuotaKit reads only the configured provider credentials, sessions, and local logs needed for these four integrations. Browser and Keychain access can require macOS permission and must not be triggered by unattended tests.

CloudKit sync contains normalized usage/account snapshots rather than raw provider responses or credentials. Existing CloudKit container, zone, record, and bundle identifiers are compatibility boundaries and should not be renamed during maintenance work.

## Development

Common Mac checks:

```bash
./Scripts/lint.sh lint
swift build
make test
```

The normal local loop builds, packages, relaunches, and confirms the Mac app remains running:

```bash
./Scripts/compile_and_run.sh
```

iPhone work lives under `CodexBarMobile/`. Regenerate its project after changing `project.yml`, then run the simulator tests:

```bash
cd CodexBarMobile
xcodegen generate
xcodebuild -project CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Do not run live provider, browser-cookie, Keychain, or production CloudKit probes as routine verification. Use parser fixtures, test stores, and no-UI Keychain queries.

## Upstream And Credits

QuotaKit is derived from [steipete/CodexBar](https://github.com/steipete/CodexBar), and Git history preserves upstream commits and contributors. QuotaKit-specific maintenance and releases belong to Columbus Labs.

See [OPEN_SOURCE_CREDITS.md](OPEN_SOURCE_CREDITS.md) for attribution guidance.

## License

MIT. See [LICENSE](LICENSE).
