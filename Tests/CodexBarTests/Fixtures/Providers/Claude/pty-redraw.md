# Synthetic PTY redraw fixtures

These fixtures encode control characters as `\\e`, `\\n`, and `\\r` so they remain reviewable in diffs. The usage stream rewrites the prior `xye` cells as `us` plus a cursor-positioned `d`, leaving the prior `e` visible; stripping ANSI alone produces `51%usd`. The status stream replaces stale synthetic account identity fields with cursor jumps and erase-line operations. No real Claude CLI, account, credential, or Keychain data is used.

`usage-pty-2.1.294-tall-panel.ansi` is an anonymized Claude Code 2.1.294 `/usage` PTY capture with synthetic replacements for personal names and identifiers. Its default inline renderer uses more than 50 rows, so the bounded 160-column, 200-row QuotaKit PTY preserves session, weekly, and model-specific quotas alongside cost statistics and usage insights. The fixture never invokes Claude CLI or accesses an account.
