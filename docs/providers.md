---
summary: "Provider data sources and parsing overview (Codex, Claude, Gemini, Antigravity)."
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
- Long-lived PTY session runs `/usage` + `/status` and parses CLI output.
- Handles Sonnet-only weekly bar when present; legacy Opus label fallback.
- Status: Statuspage.io (Anthropic).

## Gemini
- CLI `/stats` parsing for quota; OAuth-backed API fetch for plan/limits.
- Status: Google Workspace incidents for the Gemini product.

## Antigravity
- Local Antigravity language server probe; internal protocol, conservative parsing.
- Status: Google Workspace incidents for Gemini (same product feed).
- Details in `docs/antigravity.md`.

See also: `docs/claude.md`, `docs/antigravity.md`.
