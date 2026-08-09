---
summary: "The macOS QuotaKit CLI for Codex, Claude, Cursor, and Grok."
read_when:
  - Calling QuotaKit from a local script or terminal
  - Changing CLI commands, output, provider selection, or source behavior
  - Using the private dashboard or hook integrations
---

# QuotaKit CLI

`quotakit` is the macOS command-line companion to the menu bar app. It uses the same config and fetch implementations for exactly four providers: Codex, Claude, Cursor, and Grok.

Use it for local scripts, structured usage output, diagnostics, quota guards, event hooks, or a private dashboard feed. It is not a separate cross-platform product.

## Install And Build

From the installed app, use **Settings → Advanced → Install CLI**. This links the bundled helper to the standard local command locations.

For repository development:

```bash
./Scripts/package_app.sh
swift build -c release --product QuotaKitCLI
```

The standalone development binary is `.build/release/QuotaKitCLI`. The packaged helper lives inside `QuotaKit.app/Contents/Helpers/QuotaKitCLI`.

## Configuration

The CLI resolves the same config as the Mac app:

1. An explicit `CODEXBAR_CONFIG` compatibility override.
2. `~/.config/quotakit/config.json` for new installs.
3. Existing `~/.quotakit/config.json` when no XDG config exists.

Provider settings include enablement, order, source selection, and account configuration. Retired provider IDs in an older config remain inert and are omitted from CLI selection and output.

See [configuration.md](configuration.md) for the schema and [providers.md](providers.md) for the four fetch pipelines.

## Provider Selection

Use `--provider codex`, `--provider claude`, `--provider cursor`, or `--provider grok`. `--provider all` selects all four. The legacy `both` alias selects Codex and Claude.

Without `--provider`, QuotaKit uses the enabled providers in config and falls back to descriptor defaults when config is unavailable.

Account selection requires one provider:

- `--account <label>` selects a named configured account.
- `--account-index <n>` selects by stable displayed index.
- `--all-accounts` fetches all configured accounts, or all visible Codex accounts for Codex.

## Source Selection

`--source <auto|web|cli|oauth|api>` filters the selected provider's declared fetch strategies:

| Provider | `auto` | Explicit source kinds |
| --- | --- | --- |
| Codex | OAuth/CLI according to runtime, with optional configured ChatGPT web enrichment | `oauth`, `cli`, `web` |
| Claude | Admin API when configured, otherwise OAuth/CLI/web according to runtime policy | `api`, `oauth`, `cli`, `web` |
| Cursor | Authenticated Cursor session/dashboard data | `web` |
| Grok | Grok CLI billing RPC, then grok.com billing fallback | `cli`, `web` |

An unsupported explicit source is an error; it does not silently fall back to a different source kind.

## Core Commands

### Usage And Cards

```bash
quotakit usage
quotakit usage --provider codex --format json --pretty
quotakit usage --provider all --status
quotakit cards --provider all
quotakit cards --provider claude --brief
```

`usage` prints text by default and supports `--format json`, `--json`, `--pretty`, and `--json-only`. Provider-specific information is normalized into `usage.details`; callers should not depend on retired provider-specific JSON keys.

`cards` renders a one-shot terminal grid or `--brief` table. Provider failures appear in a footer and cause a nonzero exit while healthy providers remain visible.

### Cost

```bash
quotakit cost
quotakit cost --provider codex --group-by project
quotakit cost --provider claude --format json --pretty
quotakit cost --provider cursor --refresh
```

`cost` reports supported local/provider-supplied history. Codex and Claude scan local session logs; Cursor can use its authenticated dashboard data. Grok does not currently expose a QuotaKit cost report.

### Diagnostics And Guarding

```bash
quotakit diagnose --provider all --format json
quotakit guard --provider codex
```

`diagnose` reports configuration and source availability without changing credentials. `guard` exits nonzero when the selected provider does not meet the requested quota headroom, making it suitable for local gating scripts.

Do not use routine CLI verification against real accounts when it could import browser cookies or display a Keychain prompt.

### Config And Cache

```bash
quotakit config providers
quotakit config validate --format json --pretty
quotakit config dump --pretty
quotakit config enable --provider grok
quotakit config disable --provider cursor
quotakit cache clear --cookies --provider claude
quotakit cache clear --cost
quotakit cache clear --all --format json --pretty
```

`config dump` redacts secrets unless the explicit secret-output option is used. Treat unredacted output as credential material.

`cache clear` can remove provider cookie caches and local cost-scan caches. It does not rewrite CloudKit records or delete unrelated Keychain items.

### Sessions

```bash
quotakit sessions
quotakit sessions --json
quotakit sessions focus <session-id>
```

Sessions are local agent-process observations, primarily for Codex and Claude workflows. `focus` activates the owning macOS app when possible.

### Hooks

```bash
quotakit hooks list
quotakit hooks enable
quotakit hooks test quota-low --provider codex
quotakit hooks watch
```

Hooks run configured local executables directly, without a shell. They receive `QUOTAKIT_*` variables, legacy `CODEXBAR_*` aliases, and a JSON payload on stdin. Keep hooks disabled unless the local commands are trusted. See [configuration.md](configuration.md#external-event-hooks).

## Private Dashboard Output

`quotakit dashboard` emits one dashboard-v1 JSON snapshot and exits:

```bash
quotakit dashboard --pretty
quotakit dashboard --identity full --output /path/to/private/snapshot.json
```

Identity is redacted by default. `--identity full` is only for trusted private destinations. `--output` writes atomically and requires the parent directory to exist.

`quotakit serve` exposes the same usage, cost, and dashboard data over HTTP:

```bash
quotakit serve
QUOTAKIT_DASHBOARD_TOKEN=YOUR_TOKEN quotakit serve
```

- The default bind is `127.0.0.1`.
- `/health` and the static UI are open.
- `/dashboard/v1/snapshot` always requires `Authorization: Bearer YOUR_TOKEN`.
- A non-loopback bind requires a token and `--allow-plain-http`; all data routes then require the token.
- Plain HTTP exposes the bearer token to the network. Use only on a trusted segment or behind a TLS-terminating reverse proxy.
- Full account identity is opt-in and should remain private.

See [dashboard-api.md](dashboard-api.md) for the payload and threat model.

## Output And Exit Behavior

Common global flags:

- `-h`, `--help`
- `-V`, `--version`
- `-v`, `--verbose`
- `--no-color`
- `--log-level <trace|verbose|debug|info|warning|error|critical>`
- `--json-output` for JSONL logs on stderr
- `--json-only` to suppress non-JSON output where supported

Standard exit codes:

- `0`: success
- `1`: unexpected or aggregate provider failure
- `2`: required provider executable is unavailable
- `3`: parse or format failure
- `4`: provider command timeout

Text output writes data to stdout and diagnostics to stderr. JSON modes keep stdout machine-readable. ANSI color is disabled with `--no-color`, `NO_COLOR`, or `TERM=dumb`.

## Privacy Notes

- The CLI reads only the same four-provider config and local sources as the Mac app.
- Real browser-cookie import and Keychain reads can prompt on macOS.
- Dashboard bearer tokens passed on the command line can be exposed through process inspection; prefer `QUOTAKIT_DASHBOARD_TOKEN`.
- Never publish `--identity full`, unredacted config output, provider cookies, or raw diagnostic responses.
