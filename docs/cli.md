---
summary: "CodexBar CLI for fetching usage from the command line."
read_when:
  - "You want to call CodexBar data from scripts or a terminal."
  - "Adding or modifying Commander-based CLI commands."
  - "Aligning menubar and CLI output/behavior."
---

# CodexBar CLI

A lightweight Commander-based CLI that mirrors the menubar app’s data paths (Codex RPC → PTY fallback; Claude OAuth by default with web/CLI overrides).
Use it when you need usage numbers in scripts, CI, or dashboards without UI.

## Install
- In the app: **Preferences → Advanced → Install CLI**. This symlinks `CodexBarCLI` to `/usr/local/bin/codexbar` and `/opt/homebrew/bin/codexbar`.
- From the repo: `./bin/install-codexbar-cli.sh` (same symlink targets).
- Manual: `ln -sf "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI" /usr/local/bin/codexbar`.

### Linux install
- Download `CodexBarCLI-<tag>-linux-<arch>.tar.gz` from GitHub Releases (x86_64 + aarch64).
- Extract; run `./codexbar` (symlink) or `./CodexBarCLI`.

```
tar -xzf CodexBarCLI-0.14.1-linux-x86_64.tar.gz
./codexbar --version
./codexbar usage --format json --pretty
```

## Build
- `./Scripts/package_app.sh` (or `./Scripts/compile_and_run.sh`) bundles `CodexBarCLI` into `CodexBar.app/Contents/Helpers/CodexBarCLI`.
- Standalone: `swift build -c release --product CodexBarCLI` (binary at `./.build/release/CodexBarCLI`).
- Dependencies: Swift 6.2+, Commander package (`https://github.com/steipete/Commander`).

## Command
- `codexbar` defaults to the `usage` command.
  - `--format text|json` (default: text).
  - `--provider codex|claude|gemini|antigravity|both|all` (default: your in-app toggles; falls back to Codex).
  - `--no-credits` (hide Codex credits in text output).
  - `--pretty` (pretty-print JSON).
  - `--status` (fetch provider status pages and include them in output).
  - `--antigravity-plan-debug` (debug: print Antigravity planInfo fields to stderr).
- `--web` (macOS only): uses browser cookies to fetch web-backed data.
    - Codex: OpenAI web dashboard (code review remaining, usage breakdown, credits usage history when available).
        - `--web-timeout <seconds>` (default: 60)
        - `--web-debug-dump-html` (writes HTML snapshots to `/tmp` when data is missing)
    - Claude: claude.ai API (session + weekly usage, plus account metadata when available) unless overridden.
    - Linux: `--web` is not supported; CLI prints an error and exits non-zero.
- `--claude-source <oauth|web|cli>`: override Claude’s data source (OAuth default).
- Global flags: `-h/--help`, `-V/--version`, `-v/--verbose`, `--log-level <trace|verbose|debug|info|warning|error|critical>`, `--json-output`.

## Example usage
```
codexbar                          # text, respects app toggles
codexbar --provider claude        # force Claude
codexbar --provider all           # query all providers (honors your logins/toggles)
codexbar --format json --pretty   # machine output
codexbar --format json --provider both
codexbar --status                 # include status page indicator/description
codexbar --provider codex --web --format json --pretty
```

### Sample output (text)
```
Codex 0.6.0 (codex-cli)
Session: 72% left
Resets today at 2:15 PM
Weekly: 41% left
Resets Fri at 9:00 AM
Credits: 112.4 left

Claude Code 2.0.58 (claude)
Session: 88% left
Resets tomorrow at 1:00 AM
Weekly: 63% left
Resets Sat at 6:00 AM
Sonnet: 95% left
Account: user@example.com
Plan: Pro
```

### Sample output (JSON, pretty)
```json
{
  "provider": "codex",
  "version": "0.6.0",
  "source": "codex-cli",
  "status": { "indicator": "none", "description": "Operational", "updatedAt": "2025-12-04T17:55:00Z", "url": "https://status.openai.com/" },
  "primary": { "usedPercent": 28, "windowMinutes": 300, "resetsAt": "2025-12-04T19:15:00Z" },
  "secondary": { "usedPercent": 59, "windowMinutes": 10080, "resetsAt": "2025-12-05T17:00:00Z" },
  "tertiary": null,
  "updatedAt": "2025-12-04T18:10:22Z",
  "accountEmail": "user@example.com",
  "accountOrganization": null,
  "loginMethod": "plus",
  "credits": { "remaining": 112.4, "updatedAt": "2025-12-04T18:10:21Z" },
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
- CLI reuses menubar toggles when present (prefers `com.steipete.codexbar{,.debug}` defaults), otherwise defaults to Codex only.
- Prefer Codex RPC first, then PTY fallback; Claude defaults to OAuth unless `--claude-source` overrides (or `--web` is set).
- OpenAI web requires a signed-in `chatgpt.com` session in Safari or Chrome. No passwords are stored; CodexBar reuses cookies.
- Safari cookie import may require granting CodexBar Full Disk Access (System Settings → Privacy & Security → Full Disk Access).
- The `openaiDashboard` JSON field is normally sourced from the app’s cached dashboard snapshot; `--web` refreshes it live via WebKit using a per-account cookie store.
- Future: optional `--from-cache` flag to read the menubar app’s persisted snapshot (if/when that file lands).
