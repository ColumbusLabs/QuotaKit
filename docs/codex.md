---
summary: "Codex provider data sources: OpenAI web dashboard, Codex CLI RPC/PTY, credits, and local cost usage."
read_when:
  - Debugging Codex usage/credits parsing
  - Updating OpenAI dashboard scraping or cookie import
  - Changing Codex CLI RPC/PTY behavior
  - Reviewing local cost usage scanning
---

# Codex provider

Codex has three usage data paths (web, CLI RPC, CLI PTY) plus a local cost-usage scanner.
The web dashboard, when enabled and authenticated, replaces CLI usage + credits in the UI.

## Data sources + fallback order

### 1) OpenAI web dashboard (preferred when enabled)
- URL: `https://chatgpt.com/codex/settings/usage`.
- Uses an off-screen `WKWebView` with a per-account `WKWebsiteDataStore`.
  - Store key: deterministic UUID from the normalized email.
  - WebKit store can hold multiple accounts concurrently.
- Cookie import (when WebKit store has no matching session or login required):
  1) Safari: `~/Library/Cookies/Cookies.binarycookies`
  2) Chrome/Chromium forks: `~/Library/Application Support/Google/Chrome/*/Cookies`
  3) Firefox: `~/Library/Application Support/Firefox/Profiles/*/cookies.sqlite`
  - Domains loaded: `chatgpt.com`, `openai.com`.
  - No cookie-name filter; we import all matching domain cookies.
- Account match:
  - Signed-in email extracted from `client-bootstrap` JSON in HTML (or `__NEXT_DATA__`).
  - If Codex email is known and does not match, the web path is rejected.
- Web scrape payload (via `OpenAIDashboardScrapeScript` + `OpenAIDashboardParser`):
  - Rate limits (5h + weekly) parsed from body text.
  - Credits remaining parsed from body text.
  - Code review remaining (%).
  - Usage breakdown chart (Recharts bar data + legend colors).
  - Credits usage history table rows.
  - Credits purchase URL (best-effort).
- Errors surfaced:
  - Login required or Cloudflare interstitial.

### 2) Codex CLI RPC (default CLI path)
- Launches local RPC server: `codex -s read-only -a untrusted app-server`.
- JSON-RPC over stdin/stdout:
  - `initialize` (client name/version)
  - `account/read`
  - `account/rateLimits/read`
- Provides:
  - Usage windows (primary + secondary) with reset timestamps.
  - Credits snapshot (balance, hasCredits, unlimited).
  - Account identity (email + plan type) when available.

### 3) Codex CLI PTY fallback (`/status`)
- Runs `codex` in a PTY via `TTYCommandRunner`.
- Sends `/status`, parses the rendered screen:
  - `Credits:` line
  - `5h limit` line → percent + reset text
  - `Weekly limit` line → percent + reset text
- Retry once with a larger terminal size on parse failure.
- Detects update prompts and surfaces a "CLI update needed" error.

## Account identity resolution (for web matching)
1) Latest Codex usage snapshot (from RPC, if available).
2) `~/.codex/auth.json` (JWT claims: email + plan).
3) OpenAI dashboard signed-in email (cached).
4) Last imported browser cookie email (cached).

## Credits
- Web dashboard (if available) replaces CLI credits.
- CLI RPC: `account/rateLimits/read` → credits balance.
- CLI PTY fallback: parse `Credits:` from `/status`.

## Cost usage (local log scan)
- Source files:
  - `~/.codex/sessions/YYYY/MM/DD/*.jsonl`
  - Or `$CODEX_HOME/sessions/...` if `CODEX_HOME` is set.
- Scanner:
  - Parses `event_msg` token_count entries and `turn_context` model markers.
  - Computes input/cached/output token deltas and per-model cost.
- Cache:
  - `~/Library/Caches/CodexBar/cost-usage/codex-v1.json`
  - Legacy fallback: `~/Library/Caches/CodexBar/ccusage-min/codex-v1.json`
- Window: last 30 days (rolling), with a 60s minimum refresh interval.

## Key files
- Web: `Sources/CodexBarCore/OpenAIWeb/*`
- CLI RPC + PTY: `Sources/CodexBarCore/UsageFetcher.swift`,
  `Sources/CodexBarCore/Providers/Codex/CodexStatusProbe.swift`
- Cost usage: `Sources/CodexBarCore/CCUsageFetcher.swift`,
  `Sources/CodexBarCore/Vendored/CostUsage/*`
