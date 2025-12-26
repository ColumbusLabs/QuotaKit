---
summary: "OpenAI web dashboard integration for Codex (cookies, privacy, and scraping)."
read_when:
  - Changing OpenAI web integration or dashboard parsing
  - Updating browser cookie import behavior
  - Debugging OpenAI web access issues
---

# OpenAI web integration (Codex)

## What it adds
- Usage limits (5‑hour + weekly).
- Credits remaining (balance).
- Code review remaining (%).
- Usage breakdown (dashboard chart).
- Credits usage history table (when present).

When enabled, CodexBar uses the web dashboard for Codex usage + credits and only falls back to the Codex CLI when no matching
browser cookies are found.

## Opt-in + privacy
- Toggle: Settings → Providers → “Use Codex via web”.
- Reuses existing browser cookies; no credentials stored.
- Web requests go to `chatgpt.com` (same as your browser session).

## Cookie/session model
- Import order: Safari → Chrome (Safari first to avoid Chrome Keychain prompts when Safari matches).
- WebKit uses per-email `WKWebsiteDataStore` so multiple accounts can coexist.
- Email mismatch: if browser email ≠ Codex CLI email, treat as not logged in for that account (cookies retained for later match).

## Troubleshooting
- Safari cookie access may require Full Disk Access; Settings UI links to the system pane.
- Dashboard layout changes can break scraping; errors surface in Settings with a short body sample.

See also: `docs/providers.md`.
