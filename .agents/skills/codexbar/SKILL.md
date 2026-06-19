---
name: codexbar
description: "QuotaKit read. Provider usage, limits, credits, config health. JSON. No writes."
---

# QuotaKit

Read QuotaKit. Never mutate config/auth.

## Run

```bash
skill="${CODEX_HOME:-$HOME/.codex}/skills/codexbar"
"$skill/scripts/codexbar" doctor
"$skill/scripts/codexbar" providers
"$skill/scripts/codexbar" usage
"$skill/scripts/codexbar" usage --provider codex
"$skill/scripts/codexbar" usage --all
```

All stdout: JSON. Upstream provider JSON shape kept. Less drift, fewer tokens.

## Rules

- Start `doctor` when install/config unknown.
- `usage` reads enabled providers. Prefer this.
- `usage --provider ID` reads one provider.
- `usage --all` expensive; use only when needed.
- Identities hidden by default. `--include-identities` only when user explicitly needs them.
- Secrets always hidden.
- Helper read-only: fixed allowlist only. No config writes, auth repair, enable/disable, key storage.
- Timeout means provider fetch is stuck. Narrow provider or raise `QUOTAKIT_TIMEOUT` (default 120 seconds).

## Binary

Auto-find: `QUOTAKIT_BIN`, PATH, app bundle, Homebrew cask. Legacy `CODEXBAR_BIN` is accepted for migrated installs. If missing: open QuotaKit, Preferences > Advanced > Install CLI; or set `QUOTAKIT_BIN`.

Each stdout/stderr stream capped at 1 MiB while fully drained. Timeout kills process group.
