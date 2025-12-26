---
summary: "Provider data sources and parsing overview (Codex, Claude, Gemini, Antigravity, Cursor)."
read_when:
  - Adding or modifying provider fetch/parsing
  - Adjusting provider labels, toggles, or metadata
  - Reviewing data sources for providers
---

# Providers

## Codex
- Primary: local `codex app-server` RPC for 5-hour + weekly limits and credits.
- Fallback: PTY scrape of `codex /status` if RPC unavailable.
- Account identity: prefer RPC; fall back to `~/.codex/auth.json`.
- Optional OpenAI web integration for dashboard extras (see `docs/web-integration.md`).
- Status: Statuspage.io (OpenAI).

## Claude
- Primary: OAuth usage API (`https://api.anthropic.com/api/oauth/usage`) using Claude CLI credentials
  (keychain first, then `~/.claude/.credentials.json`).
- Optional: web cookie enrichment for Extra usage spend/limit (see `docs/claude.md`).
- Fallback sources (debug-selectable): Claude web API (cookies) or CLI PTY `/usage` + `/status` parsing.
- Handles Sonnet-only weekly bar when present; legacy Opus label fallback.
- Status: Statuspage.io (Anthropic).

## Gemini
- CLI `/stats` parsing for quota; OAuth-backed API fetch for plan/limits.
- Status: Google Workspace incidents for the Gemini product.

## Antigravity
- Local Antigravity language server probe; internal protocol, conservative parsing.
- Status: Google Workspace incidents for Gemini (same product feed).
- Details in `docs/antigravity.md`.

## Cursor
- Web-based: fetches usage from cursor.com API using browser session cookies.
- Cookie import: Safari (Cookies.binarycookies) → Chrome (encrypted SQLite DB); requires cursor.com + cursor.sh cookies.
- Fallback: stored session from "Add Account" WebKit login flow.
- Shows plan usage percentage, on-demand usage, and billing cycle reset.
- Supports Pro, Enterprise, Team, and Hobby membership types.
- Status: Statuspage.io (Cursor).
- Details in `docs/cursor.md`.

See also: `docs/claude.md`, `docs/antigravity.md`, `docs/cursor.md`.
