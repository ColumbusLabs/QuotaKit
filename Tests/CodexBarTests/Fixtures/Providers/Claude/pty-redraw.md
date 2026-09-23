# Synthetic PTY redraw fixtures

These fixtures encode control characters as `\\e`, `\\n`, and `\\r` so they remain reviewable in diffs. The usage stream rewrites the prior `xye` cells as `us` plus a cursor-positioned `d`, leaving the prior `e` visible; stripping ANSI alone produces `51%usd`. The status stream replaces stale synthetic account identity fields with cursor jumps and erase-line operations. No real Claude CLI, account, credential, or Keychain data is used.
