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
- From the repo, after installing `QuotaKit.app` in `/Applications`: `./bin/install-quotakit-cli.sh` (same symlink targets).
- Manual: `ln -sf "/Applications/QuotaKit.app/Contents/Helpers/QuotaKitCLI" /usr/local/bin/quotakit`.

Standalone CLI tarballs are not part of the Columbus Labs public release lane yet.

## Build
- `./Scripts/package_app.sh` (or `./Scripts/compile_and_run.sh`) bundles the SwiftPM CLI product into `QuotaKit.app/Contents/Helpers/QuotaKitCLI`.
- Standalone: `swift build -c release --product CodexBarCLI` (binary at `./.build/release/CodexBarCLI`).
- Dependencies: Swift 6.2+, Commander package (`https://github.com/steipete/Commander`).

## Configuration
QuotaKit reads the resolved config file for provider settings, secrets, and ordering. New installs use
`~/.quotakit/config.json`; absolute `XDG_CONFIG_HOME` paths resolve to
`$XDG_CONFIG_HOME/quotakit/config.json`; `QUOTAKIT_CONFIG` overrides the path,
and `CODEXBAR_CONFIG` remains supported for compatibility with migrated installs.
See `docs/configuration.md` for the schema.

## Command
- `quotakit` defaults to the `usage` command.
  - `--format text|json` (default: text).
- `quotakit cost` prints local token cost usage for Claude + Codex without web/CLI access.
  - `--format text|json` (default: text).
  - `--refresh` ignores cached scans.
- `quotakit serve` starts a foreground localhost-only HTTP server for usage and cost JSON.
  - `--port <port>` defaults to `8080`.
  - `--refresh-interval <seconds>` defaults to `60` and controls the in-memory response cache TTL.
  - `--request-timeout <seconds>` defaults to `30` and bounds each request before returning `504 Gateway Timeout`; use `0` to keep waiting indefinitely.
  - Provider config is reloaded for each usage/cost request; cache entries are keyed by the loaded config so provider toggles and source changes do not require restarting `serve`.
  - Transient refresh failures fall back to the last good response for up to ten refresh intervals (minimum five minutes) so polling clients do not flicker between data and errors; disabled when `--refresh-interval 0`.
  - v1 binds to `127.0.0.1` only and rejects non-loopback `Host` headers. It does not expose remote bind, auth, CORS, TLS, or daemon mode.
  - Endpoints: `GET /health`, `GET /usage`, `GET /usage?provider=<id|both|all>`, `GET /cost`, `GET /cost?provider=<id|both|all>`.
  - Codex usage responses include every visible Codex account, matching the menu bar switcher.
- `quotakit cache clear` clears local QuotaKit caches.
  - `--cookies` removes cached browser-cookie headers from the QuotaKit Keychain cache.
  - `--cookies --provider <id>` removes browser-cookie cache entries for that provider, including managed Codex account scopes.
  - `--cost` removes local cost-usage scan caches.
  - `--all` clears both cookies and cost caches. `--provider` is cookie-only and cannot be combined with `--cost` or `--all`.
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
    - `auto`: provider-specific fallback order from `docs/providers.md`.
    - `web`: web-only where that provider exposes an explicit web source; no CLI/API fallback. Browser import is macOS-only, while supported providers can use configured manual cookies on Linux.
    - `cli`: CLI/local-helper source where the provider exposes one (for example Codex RPC/PTy, Claude PTY, Kilo CLI fallback, Kiro CLI, local probes).
    - `oauth`: OAuth-backed source where supported (Codex, Claude, Vertex AI).
    - `api`: API-key/token flow when the provider supports it (OpenAI, Claude Admin API, z.ai, Gemini, Alibaba, Copilot, Kilo, Kimi, Kimi K2, MiniMax, Ollama, Warp, OpenRouter, ElevenLabs, Deepgram, Synthetic, DeepSeek, Moonshot, Doubao, Codebuff, Crof, Venice, AWS Bedrock).
    - Output `source` reflects the strategy actually used (`openai-web`, `web`, `oauth`, `api`, `local`, `cli`, or provider CLI label).
    - Codex web: OpenAI web dashboard (usage limits, credits remaining, code review remaining, usage breakdown).
        - `--web-timeout <seconds>` (default: 60)
        - `--web-debug-dump-html` (writes HTML snapshots to `/tmp` when data is missing)
    - Claude web: claude.ai API (session + weekly usage, plus account metadata when available).
    - Command Code web: commandcode.ai browser session cookies on macOS, or a configured manual cookie on Linux, for monthly credit usage.
    - OpenCode Go auto: local SQLite usage on macOS and Linux, with optional manual-cookie web enrichment.
    - Kilo auto: app.kilo.ai API first, then CLI auth fallback (`~/.local/share/kilo/auth.json`) on missing/unauthorized API credentials.
    - Linux: browser-backed `auto`/`web` modes are not supported; local sources and configured manual-cookie paths remain available where documented.
- Global flags: `-h/--help`, `-V/--version`, `-v/--verbose`, `--no-color`, `--log-level <trace|verbose|debug|info|warning|error|critical>`, `--json-output`, `--json-only`.
  - `--json-output`: JSONL logs on stderr (machine-readable).
  - `--json-only`: suppress non-JSON output; errors become JSON payloads.
- `quotakit config validate` checks the resolved config file for invalid fields.
  - `--format text|json`, `--pretty`, and `--json-only` are supported.
  - Warnings keep exit code 0; errors exit non-zero.
- `quotakit config dump` prints the normalized config JSON.

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
- `provider`, `source`, `updatedAt`
- `sessionTokens`, `sessionCostUSD`
- `last30DaysTokens`, `last30DaysCostUSD`
- `daily[]`: `date`, `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheCreationTokens`, `totalTokens`, `totalCost`, `modelsUsed`, `modelBreakdowns[]` (`modelName`, `cost`)
- `totals`: `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheCreationTokens`, `totalTokens`, `totalCost`

## Example usage
```
quotakit                          # text, respects app toggles
quotakit --provider claude        # force Claude
quotakit --provider all           # query all registered providers
quotakit --format json --pretty   # machine output
quotakit --format json --provider both
quotakit cost                     # local cost usage (default 30-day window + today)
quotakit cost --days 90           # choose a 1...365 day cost window
quotakit cost --provider claude --format json --pretty
quotakit serve --port 8080        # localhost HTTP JSON server
quotakit serve --request-timeout 0 # disable serve request deadlines
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
quotakit cache clear --cookies
quotakit cache clear --cookies --provider claude
quotakit cache clear --all --format json --pretty
```

### Sample output (text)
```
== Codex 0.6.0 (codex-cli) ==
Session: 72% left [========----]
Resets today at 2:15 PM
Weekly: 41% left [====--------]
Pace: 6% in reserve | Expected 47% used | Lasts until reset
Resets Fri at 9:00 AM
Credits: 112.4 left

== Claude Code 2.0.58 (web) ==
Session: 88% left [==========--]
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
