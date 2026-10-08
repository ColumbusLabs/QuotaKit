---
summary: "QuotaKit CLI for fetching usage from the command line."
read_when:
  - "You want to call QuotaKit data from scripts or a terminal."
  - "Adding or modifying Commander-based CLI commands."
  - "Aligning menubar and CLI output/behavior."
---

# QuotaKit CLI

A lightweight Commander-based CLI that mirrors the menu bar app’s provider fetchers and config file.
Use it when you need usage numbers in scripts, CI, or dashboards without UI.

## Install
- In the app: **Preferences → Advanced → Install CLI**. This symlinks `QuotaKitCLI` to `/usr/local/bin/quotakit` and `/opt/homebrew/bin/quotakit`.
- From the repo, after installing `QuotaKit.app` in `/Applications`: `./bin/install-quotakit-cli.sh` (same symlink targets; requires macOS administrator approval).
- Manual: `ln -sf "/Applications/QuotaKit.app/Contents/Helpers/QuotaKitCLI" /usr/local/bin/quotakit`.

The repo installer requires an executable `/Applications/QuotaKit.app/Contents/Helpers/QuotaKitCLI`; a missing
helper is an error. It starts the system POSIX shell with `-p` to ignore inherited functions and startup hooks
before helper validation or failure handling. This shell mode does not elevate privileges; macOS administrator
approval is still required. The installer uses absolute system tools, clears the inherited environment before
requesting approval, and stops on installation failure. The in-app installer is separate and uses Foundation symlinks.

### Manual standalone packages (macOS/Linux)

QuotaKit does not currently publish standalone CLI release tarballs. The supported Mac install is the
helper bundled with `QuotaKit.app`. Maintainers can manually run the **Release CLI** workflow to produce
workflow artifacts for macOS (arm64/x86_64) and Linux glibc (aarch64/x86_64); a manual run does not publish
a GitHub release. Static musl packages are not supported by that workflow.

For a manually supplied package, extract it and run `./quotakit` or `./QuotaKitCLI`. The package contains
the matching Core resource bundle, which must remain beside the executable. See [RELEASING.md](RELEASING.md)
for the current public distribution policy.

## Build
- `./Scripts/package_app.sh` (or `./Scripts/compile_and_run.sh`) bundles `QuotaKitCLI` into `QuotaKit.app/Contents/Helpers/QuotaKitCLI`.
- Standalone: `swift build -c release --product CodexBarCLI` (internal build binary at `./.build/release/CodexBarCLI`). Packaging names the public executable `QuotaKitCLI`.
- Dependencies: Swift 6.2+, Commander package (`https://github.com/steipete/Commander`).

## Configuration
QuotaKit reads the resolved config file for provider settings, secrets, and ordering. New installs use
`~/.quotakit/config.json`; absolute `XDG_CONFIG_HOME` paths, `QUOTAKIT_CONFIG`, and the compatibility
`CODEXBAR_CONFIG` override are supported. An existing `~/.config/quotakit/config.json` is preferred when no override is set. See [Configuration](configuration.md) for the schema and [Providers](providers.md)
for registered sources and setup guides. The [provider ID list](provider-ids.md) is generated from the registry, and
`quotakit config providers` lists registered providers and their configured enablement without fetching usage.

## Command
- `quotakit` defaults to the `usage` command.
  - `--format text|json|toon` (default: text).
  - JSON uses the generic `usage.details` array for provider-specific information. Each section contains an optional
    `title`, `rows` (`label`, `value`, and optional `secondaryValue`), and an optional `bars` or `line` chart. The same
    shape is returned by `GET /usage` from `quotakit serve`.
  - Grok purchased Extra Usage Credits appear as `usage.providerCost.balance` in USD. Zero balances are retained;
    missing or invalid wallets are omitted. The wallet is separate from quota windows and local token-cost history.
  - Legacy provider-specific keys such as `openRouterUsage`, `clawRouterUsage`, and `sub2APIUsage` are not compatibility
    aliases; clients must read `usage.details`. Unknown legacy keys in cached or iCloud-synced snapshots are ignored
    when decoding.
  - `--format toon` emits the same payload as `--format json` (and implies `--json`'s credits/no-color behavior),
    rendered as [TOON](https://github.com/toon-format/spec) instead: uniform arrays of scalar-only objects (for
    example `usage.details[].rows`) collapse into a compact `rows[N]{label,value}:` table, everything else falls
    back to an indented list form. This is a presentation-only mapping of the existing JSON schema — no new fields,
    no denormalization — intended for agents that want a token-cheaper alternative to parsing JSON. `usage --format
    toon` is the only command that supports it; every other command still advertises and accepts only
     `--format text|json`, and treats `toon` like any other unrecognized value.
- `quotakit cost` prints token cost usage for Claude, Codex, and Cursor.
  - Claude and Codex are scanned from local session logs without web/CLI access.
  - [Pi](pi.md) reads supported Pi/OMP local assistant history. Selecting Pi alongside Claude/Codex keeps those providers native-only so combined totals count each source once.
  - Muse Code reads bounded local session logs and reports recorded token history without credentials, provider requests, or invented dollar costs. Partial and unavailable history remain distinct from measured zero (see [Muse Code](muse.md)).
  - Antigravity reads supported local token history without provider CLI or credential access. Known models receive API-price estimates from the pricing catalog, which may be refreshed from public models.dev data over the network; unknown models remain unpriced. These estimates are not Antigravity charges or credit deductions. Unsupported timestamps leave history unavailable. An incomplete scan still reports the rows it decoded, with every total marked a lower bound (see `docs/antigravity.md`). The same provider selection applies to `serve /cost` and dashboard cost collection.
    Text output labels priced results as local estimates and token-only results as token history, and distinguishes unavailable or lower-bound history from a complete period with no recorded usage.
  - Cursor is fetched from the cookie-authenticated cursor.com dashboard API (macOS only; see `docs/cursor.md`) and honors the configured cookie source: a non-empty Manual header is required and forwarded, while Off fails explicitly instead of silently omitting Cursor.
  - `--format text|json` (default: text). `--json` includes the same cost concepts as Settings → Usage & Spend (token mix, `provenance`, coverage), but it is not the dashboard Export JSON schema. CLI places mix fields under each provider's `totals` and emits `provenance`/`coverage` on that provider object; Export JSON nests `tokenMix`, `provenance`, and `coverage` under `groups[]`.
  - OpenCodex appears as a separate `opencodex` payload only when **Include OpenCodex usage logs** is on in Settings. That payload does not invent `projects` (OpenCodex logs have no workspace path).
  - `--refresh` ignores cached scans.
  - `--provider-native-only` is experimental and excludes pi and OMP session mirrors from Claude and Codex history.
  - `--breakdown` adds Claude-only daily and top-model sections to text output. Both use the same latest seven calendar days, or the shorter requested interval; stale snapshots fall back to the latest recorded days and label them as recorded. Incomplete history or unattributed totals are marked partial. JSON and default text output are unchanged.
  - `--provider codex --remote <ssh-host>` produces one manual report with separate local and remote summaries. Histories are never added together, since sessions can overlap across machines. SSH uses the host's existing trusted configuration and noninteractive authentication, without agent or port forwarding. It requires an already trusted host key and a remote CLI supporting `--summary-only`. Each successful text report includes `Snapshot updated:` from that source's `updatedAt` in UTC; it is the source snapshot time, not the last usage event or command time.
  - `--provider codex --format json --summary-only` emits a one-element, versioned summary array with no account identity, project paths, model rows, or session content. Schema version 1 retains `updatedAt`, `bucketTimeZone`, `historyDays`, `currencyCode`, `historyCoverageIsEstablished`, and separate `today`/`history` totals with optional `totalTokens`/`costUSD`, incomplete-request counts, coverage categories, and provenance. Missing totals remain unavailable.
  - Host reports always scan native Codex history only. `--days` and `--refresh` apply on both hosts; the local `--period` or saved period resolves to a day count before the remote request. Each host retains its own calendar and pricing. Both modes reject `--group-by`; `--remote` and `--summary-only` cannot be combined. Ordinary `cost` output remains compatible.
  - Remote capture is bounded to 16 KiB per stream during execution, with a 60-second client process timeout. Unsupported versions, invalid totals, overflow, and unexpected output fail closed. Remote failure retains a successful local row and exits nonzero; JSON remains one document. Ctrl-C and termination signals cancel collection and await local SSH subprocess cleanup. The remote scanner follows its SSH server's disconnect behavior and may finish after the client exits.
- `quotakit cards` prints a one-shot usage snapshot as a responsive terminal card grid.
  - Reuses the same provider, source, account, credits, and status flags as `quotakit usage`.
  - Account lines and plan badges are included in the card grid by default.
  - `--brief` renders a compact table (Provider / Usage / Reset) instead of the card grid.
  - Stdout is always rendered text; `--json-output` only affects stderr logs (no JSON card payload).
  - Failed providers are summarized in a footer (not rendered as error cards).
  - When the opt-in Claude claude-swap integration returns two or more accounts—or one account with
    `claudeSwapShowSingleAccount` enabled—cards renders every account in active-first/slot order instead of the
    ambient or token-account Claude cards. This applies on macOS and Linux, including an explicit
    `--provider claude`; `--source auto` remains eligible.
  - `--account`, `--account-index`, `--all-accounts`, and explicit non-auto source flags preserve their requested
    ambient behavior and do not invoke claude-swap. Zero-account lists always retain ambient Claude output;
    one-account lists do so unless `claudeSwapShowSingleAccount` is enabled.
  - claude-swap sentinel accounts remain successful cards with their problem text and no fabricated usage metrics.
    A list adapter, parser, or timeout failure retains useful ambient Claude output, adds a distinct
    `Claude (claude-swap)` failure footer entry, and makes the command exit non-zero.
  - This precedence is cards-only: `quotakit usage` and `quotakit serve` keep their existing output cardinality.
  - Honors `$COLUMNS` for layout; falls back to 80 columns. Use `--no-color` for plain output.
  - Kitty, Ghostty, WezTerm, and other truecolor terminals auto-enable enhanced gradients/outlines.
  - Force enhanced mode elsewhere with `CODEXBAR_CARDS_ENHANCED=1`.
  - Exit code is non-zero when any provider fetch fails.
- `quotakit dashboard` prints one dashboard-v1 JSON snapshot and exits.
  - Honors enabled providers in stable order, carries configured display sort keys, and redacts account identity by default. `--identity full` includes real account emails and should be used only with trusted, private output destinations.
  - Provider failures remain row-level errors alongside healthy rows; a valid partial snapshot exits `0`.
  - Stdout contains only the snapshot document. Diagnostics and optional `--json-output` logs go to stderr.
  - `--pretty` formats the document. `--timeout <seconds>` accepts `0...86400`, defaults to `30`, and uses `0` to disable the command deadline.
  - `--output <path>` atomically writes the snapshot to a file (`0644`) instead of stdout — staged in the destination directory, fsync'd, then renamed over the target so readers never observe a partial document. The parent directory must already exist (it is not created), and stdout stays silent on success.
  - Starts no HTTP server and requires no dashboard bearer token. See `docs/dashboard-api.md` for the shared payload contract.
- `quotakit serve` starts a foreground HTTP server for usage and cost JSON, a token-gated dashboard snapshot, and a built-in web UI at `/`.
  - `GET /accounts` and `GET /accounts/<id>` discover saved provider token accounts and managed Codex accounts without fetching usage or exporting credentials. IDs are stable opaque lookup keys; `active` reflects the saved selection. Discovery includes disabled providers, excludes system/profile-home discovery, follows the serve identity setting (redacted by default), and requires bearer authentication on non-loopback binds. See [account discovery](dashboard-api.md#account-discovery).
  - Web usage bars follow the app's **Usage bars fill** setting, read per request on macOS. Dashboard snapshots from
    both `serve` and `quotakit dashboard` expose it as `host.usageBarsShowUsed`. An absent setting defaults to remaining
    percentages, including on Linux; earlier web dashboards always showed used percentages. Quota values are unchanged.
  - `--host <host>` accepts `localhost` or an IPv4 address and defaults to `127.0.0.1`; `localhost` is normalized to `127.0.0.1`. Binding a non-loopback host requires a dashboard token **and** `--allow-plain-http` (see `docs/dashboard-api.md` for the threat model).
  - `--port <port>` defaults to `8080`.
  - `--refresh-interval <seconds>` defaults to `60` and controls the in-memory response cache TTL.
  - `--request-timeout <seconds>` defaults to `30` and bounds each request before returning `504 Gateway Timeout`; use `0` to keep waiting indefinitely. Slow builds continue past the deadline, commit their finished result to the cache, and feed any same-config request already waiting so a 504 self-heals on retry.
  - `--dashboard-token <token>` sets the static bearer token for `GET /dashboard/v1/snapshot`. Prefer the `QUOTAKIT_DASHBOARD_TOKEN` environment variable (it wins over the flag; a flag value leaks via `ps`; legacy `CODEXBAR_DASHBOARD_TOKEN` is also accepted). Empty or whitespace-only tokens are startup errors. Without a token the snapshot route fails closed with `401`.
  - `--identity full` includes real account emails in snapshots served to every authorized dashboard client; the default is redacted. Reserve full identity for trusted private networks.
  - On a **non-loopback** host the token gates **all data routes** — `/usage`, `/cost`, and `/dashboard/v1/snapshot` all require `Authorization: Bearer YOUR_TOKEN`, so account data is never exposed to the network unauthenticated. The static web UI at `/` and `/health` are always open. On the default loopback bind, `/usage` and `/cost` stay unauthenticated.
  - `--allow-plain-http` is the explicit acknowledgment that the bearer token crosses the network **in cleartext on every request** when serving on a non-loopback host. `serve` refuses to start on a non-loopback host without it.
  - Provider config is reloaded for each usage/cost request; cache entries are keyed by the loaded config so provider toggles and source changes do not require restarting `serve`.
  - Transient refresh failures fall back to the last good response for up to ten refresh intervals (minimum five minutes) so polling clients do not flicker between data and errors; disabled when `--refresh-interval 0`.
  - After a cached response expires, `serve` returns the last-good response immediately while rebuilding it in the background; `--refresh-interval 0` keeps every request blocking.
  - The default loopback bind rejects non-loopback `Host` headers; a configured non-loopback `--host` additionally accepts its own name. No CORS, TLS, or daemon mode.
  - Endpoints: `GET /` (web UI), `GET /health`, `GET /usage`, `GET /usage?provider=<id|both|all>`, `GET /cost`, `GET /cost?provider=<id|both|all>`, `GET /dashboard/v1/snapshot` (plus `provider=<id>` and `detail=<full|shell>`).
  - `GET /dashboard/v1/snapshot` requires `Authorization: Bearer YOUR_TOKEN`; responses (and all `401`s) carry `Cache-Control: no-store`. The token is never accepted via query string. See `docs/dashboard-api.md` for the payload contract.
  - `GET /health` returns `{"status":"ok"}` plus a `version` field with the running build (e.g. `"0.37.2"`) when resolvable; clients can compare it against `quotakit --version` to detect a `serve` process still running an older binary after an update.
  - Codex usage responses include every visible Codex account, matching the menu bar switcher.
- `quotakit cache clear` clears local QuotaKit caches.
  - `--cookies` removes cached browser-cookie headers from the QuotaKit Keychain cache.
  - `--cookies --provider <id>` removes browser-cookie cache entries for that provider, including managed Codex account scopes.
  - `--cost` removes local cost-usage scan caches.
  - `--all` clears both cookies and cost caches. `--provider` is cookie-only and cannot be combined with `--cost` or `--all`.
- `quotakit plugins` lists installed user-provider plugins and their approval/runtime state. Plugin manifests can describe settings, detail rows, and charts; see `docs/plugins.md` for install paths, permissions, and the JavaScript/TypeScript sandbox.
- `--provider <id|both|all>` (default: enabled providers in config; falls back to defaults when missing).
  - Provider IDs live in the config file (see `docs/configuration.md`).
  - With three or more providers enabled, the default stays scoped to enabled providers; use `--provider all` to query
    every registered provider.
  - `--account <label>` / `--account-index <n>` / `--all-accounts` (token accounts from config, or all visible Codex accounts for Codex; requires a single provider).
  - `--no-credits` (hide Codex credits in text output).
  - `--pretty` (pretty-print JSON).
  - `--status` (fetch provider status pages and include them in output).
  - `--antigravity-plan-debug` (debug: print Antigravity planInfo fields to stderr).
- `--source <auto|web|cli|oauth|api>` (default: `auto`).
    - `auto`: provider-specific fallback order in [Providers](providers.md#fetch-strategies-current).
    - `web`: web-only where that provider exposes an explicit web source; no CLI/API fallback. Browser import is macOS-only, while supported providers can use configured manual cookies on Linux.
    - `cli`: CLI/local-helper source where the provider exposes one (for example Codex RPC/PTy, Claude PTY, Kilo CLI fallback, Kiro CLI, local probes).
    - `oauth`: OAuth-backed source where supported (Codex, Claude, Vertex AI).
    - `api`: API-backed flow where supported; credentials may be API keys or existing tokens. See the [provider source table](providers.md#fetch-strategies-current) and each provider guide for supported modes.
    - v0: set `V0_API_KEY`; optional project scope is `V0_SCOPE`. Both values can also be set in provider config.
    - Output `source` reflects the strategy actually used (`openai-web`, `web`, `oauth`, `api`, `local`, `cli`, or provider CLI label).
    - Codex web: OpenAI web dashboard (usage limits, credits remaining, code review remaining, usage breakdown).
        - `--web-timeout <seconds>` (default: 60)
        - `--web-debug-dump-html` (writes HTML snapshots to `/tmp` when data is missing)
    - Claude web: claude.ai API (session + weekly usage, account metadata, and prepaid Usage credits balance when
      available).
      CLI Auto falls back to the installed Claude executable when web credentials are unavailable. This foreground
      command delegates authentication to Claude Code; the app keeps its stricter prompt-free background availability
      gate for scheduled refreshes.
    - Command Code web: commandcode.ai browser session cookies on macOS, or a configured manual cookie on Linux, for monthly credit usage.
    - OpenCode Go auto: local SQLite cost history on macOS with API usage-window enrichment when
      `OPENCODE_API_KEY` is configured, plus legacy manual-cookie web fallback.
    - Kilo auto: app.kilo.ai API first, then CLI auth fallback (`~/.local/share/kilo/auth.json`) on missing/unauthorized API credentials.
    - Linux: automatic browser import is unavailable. Cursor `auto`/`cli` can read the signed-in app token, including Cursor and Grok Bot usage; explicit Cursor `web` requires a manual cookie. Other local sources and configured manual-cookie paths remain available where documented.
- Global flags: `-h/--help`, `-V/--version`, `-v/--verbose`, `--no-color`, `--log-level <trace|verbose|debug|info|warning|error|critical>`, `--json-output`, `--json-only`.
  - `--json-output`: JSONL logs on stderr (machine-readable).
  - `--json-only`: suppress non-JSON output; errors become JSON payloads.
- `quotakit config validate` checks the resolved config file for invalid fields.
  - `--format text|json`, `--pretty`, and `--json-only` are supported.
  - Warnings keep exit code 0; errors exit non-zero.
- `quotakit config dump` prints normalized config JSON with credentials redacted by default. `--show-secrets` explicitly includes raw credentials; `--pretty` formats the output.
- `quotakit hooks list` shows the local hook configuration; `--format json` and `--pretty` are supported.
- `quotakit hooks enable|disable` changes the explicit top-level opt-in switch in the local config file.
- `quotakit hooks test <event> --provider <id>` invokes matching enabled rules with a representative event. Hook
  commands run directly without a shell and receive `QUOTAKIT_*` variables (plus legacy `CODEXBAR_*` aliases) and JSON on stdin. `--format json` and
  `--json-only` return structured per-rule results. See
  `docs/configuration.md#external-event-hooks` for the event, payload, timeout, and security contract.
- The macOS app and `hooks watch` emit `usage_updated` after a successful current refresh, throttled to at most
  one attempt per 600 seconds for each provider/account. Its primary and secondary positional quota windows include
  their cadence in minutes. Synthetic placeholder windows are omitted.
- `quotakit hooks watch` polls enabled providers and fires matching hooks on real quota and status transitions.
  Without it, hook rules only ever fire from the macOS app, so a headless install can configure hooks that never run.
  - `--interval <seconds>`: poll period. Default `300`, minimum `60`; a smaller value is rejected rather than
    clamped, because each tick fetches every selected provider.
  - `--provider <id>`: restrict to one provider; repeatable. Defaults to every enabled provider.
  - `--format json`/`--json`/`--pretty`: emit each attempted event as JSON, excluding throttled candidates.
  - Events are edge-triggered against the previous poll, so a condition that merely persists (a saturated window,
    an ongoing outage) does not re-fire every tick. State is in-memory only: a restart re-establishes baselines and
    the first poll establishes each lane's transition baseline. A successful first poll can immediately attempt
    `usage_updated`. Repeated attempts within 600 seconds are dropped, including after command failure; no latest-value
    queue or trailing delivery is scheduled. Private account throttle keys are never included in event payloads.
  - Run `watch` as one continuous process. Repeated one-shot invocations cannot preserve transition baselines or event
    rate limits between polls.
  - Runs read-only, like `quotakit guard`: it never prompts for credentials. A failed refresh reports
    `refresh_failed` with a coarse category (`timeout`, `offline`, `auth_required`, `network_error`) and never
    forwards the raw provider error.
  - Stops cleanly on `SIGINT`/`SIGTERM`/`SIGHUP`.

### Token accounts
The CLI reads multi-account tokens from the same resolved config file as the app.
- Select a specific account: `--account <label>` (matches the label/email in the file).
- Select by index (1-based): `--account-index <n>`.
- Fetch all accounts for the provider: `--all-accounts`.
Account selection flags require a single provider (`--provider claude`, etc.).
For Claude, token accounts accept either `sessionKey` cookies or OAuth access tokens (`sk-ant-oat...`).
OAuth usage requires the `user:profile` scope; inference-only tokens will return an error.

### Codex accounts
For Codex, `--all-accounts` and `quotakit serve` enumerate the same visible accounts as the app switcher:
managed Codex accounts from `managed-codex-accounts.json` plus the live system account when present.
Each fetch is scoped to that account's Codex home before the normal Codex web/OAuth/CLI strategy runs, and JSON
payloads include the visible account label in `account`.

### Cost JSON payload
`quotakit cost --format json` emits an array of payloads (one per provider).
- `reportingPeriod` and `historyLabel` identify the selected rolling window, calendar month to date, or available 365-day history. `--days` overrides `--period` and the saved Mac selection.
- `provider`, `source` (`local` for Claude/Codex log scans, `web` for Cursor dashboard data), `updatedAt`
- `sessionTokens`, `sessionCostUSD`
- `last30DaysTokens`, `last30DaysCostUSD`: with histories longer than 30 days, these cover the latest 30 local calendar dates ending at `updatedAt`; an empty window reports zero only for metrics established by a complete scan, and otherwise stays unknown. Shorter histories retain their available window totals.
- `historyCoverageIsEstablished`: `false` while a bounded Codex scan still has catch-up work pending; `true` once the requested history is covered.
- Cursor only: `meteredCostUSD` — what Cursor's plan actually deducts over the window, alongside the API-rate estimate in `last30DaysCostUSD`.
- `daily[]`: `date`, `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheCreationTokens`, `totalTokens`, `totalCost`, `modelsUsed`, `modelBreakdowns[]` (`modelName`, `cost`)
- Codex only: `projects[]`: `name`, `path`, `totalTokens`, `totalCost`, `daily[]`, `modelBreakdowns[]`, `sources[]`
- `totals`: `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheCreationTokens`, `totalTokens`, `totalCost`
- `error`: structured provider error when a fetch fails (for example Cursor requested while its cookie source is Off).

## Example usage
```
quotakit                          # text, respects app toggles
quotakit --provider claude        # force Claude
quotakit --provider all           # query all registered providers
quotakit --format json --pretty   # machine output
quotakit --format json --provider both
quotakit cost                     # local cost usage (default 30-day window + today)
quotakit cost --days 90           # choose a 1...365 day cost window
quotakit cost --period month-to-date # use the pinned cost calendar month
quotakit cost --period all        # use the available 365-day horizon
quotakit cost --provider codex --group-by project
quotakit cost --provider claude --format json --pretty
quotakit cost --provider cursor   # Cursor dashboard cost (API-rate + Cursor-metered)
quotakit cost --provider muse     # local Muse token history; dollar costs unavailable
quotakit serve --port 8080        # localhost HTTP JSON server
quotakit serve --request-timeout 0 # disable serve request deadlines
QUOTAKIT_DASHBOARD_TOKEN=YOUR_TOKEN quotakit serve # token-gated dashboard snapshot
QUOTAKIT_DASHBOARD_TOKEN=... quotakit serve --host 0.0.0.0 --allow-plain-http # LAN, cleartext accepted
COPILOT_API_TOKEN=... quotakit --provider copilot --format json --pretty
quotakit --status                 # include status page indicator/description
quotakit --provider codex --source oauth --format json --pretty
quotakit --provider codex --source web --format json --pretty
quotakit --provider codex --all-accounts --format json --pretty
quotakit --provider claude --account steipete@gmail.com
quotakit --provider claude --all-accounts --format json --pretty
quotakit --json-only --format json --pretty
quotakit --provider gemini --source api --format json --pretty
KILO_API_KEY=... quotakit --provider kilo --source api --format json --pretty
MOONSHOT_API_KEY=... quotakit --provider moonshot --source api --format json --pretty
quotakit config validate --format json --pretty
quotakit config dump --pretty
printf '%s' "$OPENAI_ADMIN_KEY" | quotakit config set-api-key --provider openai --stdin
quotakit config enable --provider grok
quotakit config set-source --provider claude --source cli
quotakit config set-source --provider claude --source auto
quotakit cache clear --cookies
quotakit cache clear --cookies --provider claude
quotakit cache clear --all --format json --pretty
```

`config set-source` writes the provider's `source` in the resolved config file, using the same
store as Settings. It accepts the provider names and aliases used by `config enable`, and rejects
sources not offered by that provider's fetch plan. `--source auto` removes the override. Provider
enablement, credentials, and other config fields are preserved. JSON output includes `provider`,
`displayName`, `enabled`, `source`, and `configPath`; `source` reports `auto` after clearing an override.
Invalid arguments are rejected before reading or writing the config, leaving any existing file byte-identical.
Successful writes use the shared store's normal defaults and JSON formatting; setter output contains no credentials.

### Sample output (text)
```
== Codex 0.6.0 (codex-cli) ==
Session: 72% left [========----]
Pace: 12% in deficit | Expected 16% used | Projected empty in 2h 30m
Resets today at 2:15 PM
Weekly: 41% left [====--------]
Pace: 6% in reserve | Expected 47% used | Lasts until reset
Resets Fri at 9:00 AM
Credits: 112.4 left

== Claude Code 2.0.58 (web) ==
Session: 88% left [==========--]
Pace: On pace | Expected 13% used | Lasts until reset
Resets tomorrow at 1:00 AM
Weekly: 63% left [=======-----]
Pace: On pace | Expected 37% used | Runs out in 4d
Resets Sat at 6:00 AM
Sonnet: 95% left [===========-]
Account: user@example.com
Plan: Pro

== Kilo (cli) ==
Credits: 60% left [=======-----]
40/100 credits
Plan: Kilo Pass Pro
Activity: Auto top-up: visa
Note: Using CLI fallback
```

### Sample output (JSON, pretty)
```json
{
  "provider": "codex",
  "version": "0.6.0",
  "source": "openai-web",
  "status": { "indicator": "none", "description": "Operational", "updatedAt": "2025-12-04T17:55:00Z", "url": "https://status.openai.com/" },
  "usage": {
    "primary": { "usedPercent": 28, "windowMinutes": 300, "resetsAt": "2025-12-04T19:15:00Z" },
    "secondary": { "usedPercent": 59, "windowMinutes": 10080, "resetsAt": "2025-12-05T17:00:00Z" },
    "tertiary": null,
    "updatedAt": "2025-12-04T18:10:22Z",
    "identity": {
      "providerID": "codex",
      "accountEmail": "user@example.com",
      "accountOrganization": null,
      "loginMethod": "plus"
    },
    "accountEmail": "user@example.com",
    "accountOrganization": null,
    "loginMethod": "plus"
  },
  "pace": {
    "primary": { "stage": "ahead", "deltaPercent": 12, "expectedUsedPercent": 16, "willLastToReset": false, "etaSeconds": 9000, "summary": "12% in deficit | Expected 16% used | Projected empty in 2h 30m" },
    "secondary": { "stage": "slightlyBehind", "deltaPercent": -6, "expectedUsedPercent": 47, "willLastToReset": true, "summary": "6% in reserve | Expected 47% used | Lasts until reset" }
  },
  "credits": { "remaining": 112.4, "updatedAt": "2025-12-04T18:10:21Z" },
  "antigravityPlanInfo": null,
  "openaiDashboard": {
    "signedInEmail": "user@example.com",
    "codeReviewRemainingPercent": 100,
    "creditEvents": [
      { "id": "00000000-0000-0000-0000-000000000000", "date": "2025-12-04T00:00:00Z", "service": "CLI", "creditsUsed": 123.45 }
    ],
    "dailyBreakdown": [
      {
        "day": "2025-12-04",
        "services": [{ "service": "CLI", "creditsUsed": 123.45 }],
        "totalCreditsUsed": 123.45
      }
    ],
    "updatedAt": "2025-12-04T18:10:21Z"
  }
}
```

## Exit codes
- 0: success
- 2: provider missing (binary not on PATH)
- 3: parse/format error
- 4: CLI timeout
- 1: unexpected failure

## Notes
- CLI uses the config file for enabled providers, ordering, and secrets.
- CLI binary discovery checks explicit overrides, captured login PATH, inherited PATH, and known install paths before falling back to an interactive shell probe.
- Automatic executable discovery and child PATHs use absolute directories only; empty, `.` and relative entries are ignored. Install CLIs in an absolute PATH directory. Explicit executable overrides and shell startup files remain trusted user configuration.
- Bundled helpers and plugin resources are located relative to the resolved running executable, including symlinked CLI installations, rather than the invocation directory.
- Reset lines follow the in-app reset time display setting when available (default: countdown).
- Text output uses ANSI colors when stdout is a rich TTY; disable with `--no-color` or `NO_COLOR`/`TERM=dumb`.
- Copilot CLI queries require an API token via config `apiKey` or `COPILOT_API_TOKEN`.
- OpenAI API charts require an Admin API key for organization costs/usage. Normal API keys can only use the legacy balance fallback.
- Claude Admin API charts require an Anthropic Admin API key (`sk-ant-admin...` or `ANTHROPIC_ADMIN_KEY`).
- Codex CLI `auto` tries the OpenAI web dashboard, then Codex CLI RPC/PTy; the app’s Codex `auto` path prefers OAuth when credentials are present, then CLI.
- Claude CLI `auto` tries web, then CLI PTY; the app’s Claude `auto` path prefers OAuth, then CLI, then web.
- Kilo text output splits identity into `Plan:` and `Activity:` lines; in `--source auto`, resolved CLI fetches add
  `Note: Using CLI fallback`.
- Kilo auto-mode failures include a fallback-attempt summary line in text mode (API attempt then CLI attempt).
- OpenAI web requires a signed-in `chatgpt.com` session in a supported browser or a manual cookie header. No passwords are stored; QuotaKit reuses cookies.
- Safari cookie import may require granting QuotaKit Full Disk Access (System Settings → Privacy & Security → Full Disk Access).
- The `openaiDashboard` JSON field is normally sourced from the app’s cached dashboard snapshot; `--source auto|web` refreshes it live via WebKit using a per-account cookie store.
- Future: optional `--from-cache` flag to read the menubar app’s persisted snapshot (if/when that file lands).

## Managed Codex accounts (macOS)

`quotakit codex-accounts list --json` lists managed account UUIDs, emails, and whether each readable
saved identity matches the current system authentication. It never emits tokens or private home paths.

`quotakit codex-accounts promote <uuid-or-email>` explicitly promotes one managed account to system
authentication. Use the exact UUID when several accounts share an email. Promotion preserves the
current live credentials in their managed account (or imports that account) before publishing the
target's authentication through the private atomic writer. Missing, unreadable, conflicting, or
workspace-mismatched state fails without replacing live authentication. Participating app/CLI
account-store writers share a nonblocking process lock and report contention rather than waiting for
each other. The operating system releases the lock if a process exits or crashes; do not delete the
lock file. A changed live or selected managed auth file detected before replacement requires retrying
the operation. External writers do not share this lock, so avoid running `codex login` concurrently.

This command does not add accounts, sign in, rotate accounts automatically, change the app's display
selection, or restart existing Codex processes. Already-running processes may retain their old identity.
External Codex clients do not participate in QuotaKit's process lock.

Both commands use local account metadata and auth files only: they do not access Keychain, import
browser cookies, or make provider requests. `CODEX_HOME` selects the system destination; the managed
account list still comes from QuotaKit's account store for the current macOS user.
The destination must be separate from every managed home, including symlink aliases, so preservation
cannot be overwritten by the promotion itself. If it is a managed home, unset `CODEX_HOME` or choose
a separate live home before promoting.

Promotion does not renew expired credentials. Use **Reauthenticate** on the affected managed row in
Settings → Providers → Codex, or run `CODEX_HOME='/absolute/path/to/that/managed/home' codex login`
with that account's existing home and select the intended workspace. Ordinary browser login remains
available when device-code login is disabled. There is no `codex-accounts reauth` command or automatic
managed-workspace renewal: a safe CLI flow also needs staged login, post-login identity/workspace
validation, and a locked commit that rejects a removed or changed account.

## Hooks selections and reset credits

`hooks watch --provider <id|both|all>` accepts repeated selections. `both` selects the primary providers; `all` selects the full registry, including providers disabled in config. Defaults remain the enabled providers. Commands requiring a concrete provider omit group aliases from their help.

Usage JSON includes optional `resetCredits` with `available` and `nextExpiresAt`, derived from the shared unexpired, available reset-credit inventory. The compact summary omits credit identifiers.
