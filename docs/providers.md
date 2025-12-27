---
summary: "Provider data sources and parsing overview (Codex, Claude, Gemini, Antigravity, Cursor, Droid/Factory, z.ai, Copilot)."
read_when:
  - Adding or modifying provider fetch/parsing
  - Adjusting provider labels, toggles, or metadata
  - Reviewing data sources for providers
---

# Providers

## Codex
- Web dashboard (when enabled): `https://chatgpt.com/codex/settings/usage` via WebView + browser cookies.
- CLI RPC default: `codex ... app-server` JSON-RPC (`account/read`, `account/rateLimits/read`).
- CLI PTY fallback: `/status` scrape.
- Local cost usage: scans `~/.codex/sessions/**/*.jsonl` (last 30 days).
- Status: Statuspage.io (OpenAI).
- Details: `docs/codex.md`.

## Claude
- OAuth API (preferred when CLI credentials exist).
- Web API (browser cookies) fallback when OAuth missing.
- CLI PTY fallback when OAuth + web are unavailable.
- Optional web extras when CLI forced (Extra usage spend/limit).
- Local cost usage: scans `~/.config/claude/projects/**/*.jsonl` (last 30 days).
- Status: Statuspage.io (Anthropic).
- Details: `docs/claude.md`.

## z.ai
- API token from Keychain or `Z_AI_API_KEY` env var.
- `GET https://api.z.ai/api/monitor/usage/quota/limit`.
- Status: none yet.
- Details: `docs/zai.md`.

## Gemini
- OAuth-backed quota API (`retrieveUserQuota`) using Gemini CLI credentials.
- Token refresh via Google OAuth if expired.
- Tier detection via `loadCodeAssist`.
- Status: Google Workspace incidents (Gemini product).
- Details: `docs/gemini.md`.

## Antigravity
- Local Antigravity language server (internal protocol, HTTPS on localhost).
- `GetUserStatus` primary; `GetCommandModelConfigs` fallback.
- Status: Google Workspace incidents (Gemini product).
- Details: `docs/antigravity.md`.

## Cursor
- Web API via browser cookies (`cursor.com` + `cursor.sh`).
- Fallback: stored WebKit session.
- Status: Statuspage.io (Cursor).
- Details: `docs/cursor.md`.

## Droid (Factory)
- Web API via Factory cookies, bearer tokens, and WorkOS refresh tokens.
- Multiple fallback strategies (cookies → stored tokens → local storage → WorkOS cookies).
- Status: `https://status.factory.ai`.
- Details: `docs/factory.md`.

## Copilot
- GitHub device flow OAuth token + `api.github.com/copilot_internal/user`.
- Status: Statuspage.io (GitHub).
- Details: `docs/copilot.md`.

See also: `docs/provider.md` for architecture notes.
