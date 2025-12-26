---
summary: "Claude Code support in CodexBar: PTY probing, parsing, and UX."
read_when:
  - Debugging Claude usage/status parsing
  - Adjusting Claude provider UI/menu behavior
  - Updating Claude CLI detection paths or prompts
---

# Claude Code support (CodexBar)

Claude Code support is implemented: CodexBar can show Claude alongside Codex (one status item per provider) and keeps provider identity fields siloed (no Claude org/plan leaking into Codex, and vice versa).

## UX
- On launch we detect CLIs:
  - Codex: `codex --version`
  - Claude Code: `claude --version`
- Settings → General: toggles for “Show Codex usage” and “Show Claude Code usage” (Claude defaults on when detected).
- Menu: each enabled provider gets its own status item/menu card.

### Claude menu-bar icon (crab notch homage)
- Same two-bar metaphor; template switches to the Claude “crab” style while keeping the same bar mapping.

## Data path (Claude)

### OAuth API (default)
- Uses Claude CLI OAuth credentials (Keychain `Claude Code-credentials` first, then `~/.claude/.credentials.json`).
- Calls `GET https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20`.
- Maps `five_hour` → session, `seven_day` → weekly, `seven_day_sonnet`/`seven_day_opus` → model-specific weekly.
- Extra usage credits (if present) surface as `ProviderCostSnapshot` in the menu.
- If the OAuth token is expired/missing, we surface a direct “run `claude` to refresh” error.

### Web cookie enrichment (optional)
- When “Augment Claude via web” is enabled, we attempt to read Safari/Chrome cookies and fetch
  Claude web extras (Extra usage spend/limit). This is best-effort and does not override identity fields.

### CLI PTY fallback (debug)
- We launch a single Claude CLI session inside a pseudo-TTY and keep it alive between refreshes to avoid warm-up churn.
- Driver steps:
  1) Boot loop waits for the TUI header and handles first-run prompts:
     - “Do you trust the files in this folder” → send `1` + Enter
     - “Select a workspace” → send Enter
     - Telemetry `(y/n)` → send `n` + Enter
     - Login prompts → abort with a nice error (“claude login”).
  2) Send the `/usage` slash command directly (type `/usage`, press Enter once) so we land on the Usage tab.
  3) Re-press Enter every ~1.5s (Claude sometimes drops the first one under load).
  4) If still no usage after a few seconds, re-send `/usage` + Enter up to 3 times.
  5) Stop as soon as the buffer contains both “Current session” and “Current week (all models)”.
  6) Keep reading ~2s more so percent lines are captured cleanly, then exit.
- Parsing:
  - We strip ANSI codes, then look for percent lines within 4 lines of these headers:
    - `Current session`
    - `Current week (all models)`
    - `Current week (Sonnet only)` (optional)
  - `X% used` is converted to `% left = 100 - X`; `X% left` is used as-is.
  - If the CLI surfaces `Failed to load usage data` with a JSON blob (e.g. `authentication_error` + `token_expired`),
    we surface that message directly ("Claude CLI token expired. Run `claude login`"), rather than the generic
    "Missing Current session" parse failure.
  - We also extract `Account:` and `Org:` lines when present.
- Strictness: if Session or Weekly blocks are missing, parsing fails loudly (no silent “100% left” defaults).
- Resilience: `ClaudeStatusProbe` retries once with a slightly longer timeout (20s + 6s) to ride out slow redraws or ignored Enter presses.

### What we display
- Session and weekly usage bars; Sonnet-only weekly limit if present.
- Account line uses Claude CLI data (email + org + login method). Provider identity fields stay siloed.

## Notes
- Reset parsing: Claude reset lines can be ambiguous; the parser keys off known “Current session / Current week …” section headers so “Resets …” cannot be attributed to the wrong window.
- Debug: the Debug tab can copy the latest raw CLI scrape to help diagnose upstream CLI formatting changes.

## Open items / decisions
- Which template asset to use for the Claude icon (color vs monochrome template); default to a monochrome template PDF sized 20×18.
- Whether to auto-enable Claude when detected the first time; proposal: keep default off, show “Detected Claude 2.0.44 (enable in Settings)”.
- Weekly vs session reset text: display the string parsed from the CLI; do not attempt to compute it locally.

## Debugging tips
- Quick live probe: `LIVE_CLAUDE_FETCH=1 swift test --filter liveClaudeFetchPTY` (prints raw PTY output on failure).
- Manually drive the runner: `swift run claude-probe` (if you add a temporary target) or reuse the TTYCommandRunner from a Swift REPL.
- Check the raw text: log the buffer before ANSI stripping if parsing fails—look for stuck autocomplete lists instead of the Usage pane.
- Debug data source selector: Preferences → Debug → “Claude data source” (OAuth/Web/CLI).
- Things that commonly break:
  - Claude CLI not logged in (`claude login` needed).
  - CLI auth token expired: the Usage pane shows `Error: Failed to load usage data: {"error_code":"token_expired", …}`;
    rerun `claude login` to refresh tokens. CodexBar now surfaces this message directly.
  - Enter ignored because the CLI is “Thinking” or busy; rerun with longer timeout or more Enter retries.
  - Running inside tmux/screen: our PTY driver is standalone, so disable tmux for this path.
  - Settings > General now shows the last Claude fetch error inline under the toggle to make it clear why usage is stale.
- Codex parity: when credits are missing because the Codex CLI shows an update prompt, our PTY driver now auto-sends Down+Enter, re-runs `/status`, and retries once with a longer timeout; if it still fails, run `LIVE_CODEX_STATUS=1 swift test --filter liveCodexStatus` to dump the raw screen.
- To rebuild and reload the menubar app after code changes: `./scripts/compile_and_run.sh`. Ensure the packaged app is restarted so the new PTY driver is in use.
