---
summary: "QuotaKit configuration for Codex, Claude, Cursor, and Grok."
read_when:
  - Editing the QuotaKit config file
  - Explaining provider settings or local credential handling
---

# Configuration

QuotaKit uses one JSON file for Mac app and bundled CLI settings. The only supported provider IDs are `codex`, `claude`, `cursor`, and `grok`.

## Location

Resolution order:

1. `QUOTAKIT_CONFIG=/absolute/path/config.json`
2. `CODEXBAR_CONFIG=/absolute/path/config.json` for migrated installs
3. `~/.config/quotakit/config.json` when that file already exists
4. `~/.quotakit/config.json` by default

QuotaKit creates the directory when necessary and writes the file with `0600` permissions.

## Root Shape

```json
{
  "version": 1,
  "hooks": null,
  "providers": [
    { "id": "codex", "enabled": true, "source": "auto" },
    { "id": "claude", "enabled": true, "source": "auto" },
    { "id": "cursor", "enabled": true, "source": "auto" },
    { "id": "grok", "enabled": true, "source": "auto" }
  ]
}
```

Unknown provider IDs are ignored. Missing supported providers are restored with defaults during normalization. Array order controls provider order in the app and CLI.

## Provider Fields

All fields except `id` are optional.

- `id`: `codex`, `claude`, `cursor`, or `grok`.
- `enabled`: enables or disables the provider.
- `source`: provider source preference. Valid modes are provider-dependent combinations of `auto`, `oauth`, `cli`, `web`, and `api`.
- `cookieSource`: `auto`, `manual`, or `off` for providers with a web source.
- `cookieHeader`: manual HTTP `Cookie` request-header value. This is a credential.
- `apiKey`: Claude Admin API key when the Claude API source is used. This is a credential.
- `tokenAccounts`: labeled provider credentials for supported multi-account flows.

Fields that do not apply to a provider are ignored or rejected by config validation.

## Source Notes

- Codex supports automatic, OAuth, CLI, and web-dashboard sources.
- Claude supports automatic, OAuth, CLI, web, and Admin API sources.
- Cursor supports automatic, local Cursor-app, and web-cookie sources.
- Grok supports automatic, CLI, and web-cookie sources.

Use Settings for ordinary changes. For scripted edits:

```sh
quotakit config providers
quotakit config enable --provider grok
quotakit config disable --provider cursor
quotakit config validate
```

For a Claude Admin API key, prefer stdin so the value is not placed in shell history:

```sh
printf '%s' "$ANTHROPIC_ADMIN_API_KEY" | quotakit config set-api-key --provider claude --stdin
```

## Manual Cookies

Paste the `Cookie:` request header from the relevant provider request, not a Netscape cookie export. Either of these forms is accepted:

```text
Cookie: name=value; other=value
name=value; other=value
```

Manual cookies are secrets. Keep the config private, never commit it, and never include real values or readable browser screenshots in issues.

## External Event Hooks

Hooks are local, explicit opt-in automation. Neither iCloud usage sync nor any network response can create or enable hook rules. Commands run as direct executable invocations, never through a shell, and do not inherit provider credentials.

```json
{
  "hooks": {
    "enabled": true,
    "events": [
      {
        "id": "quota-alert",
        "enabled": true,
        "event": "quota_low",
        "provider": "codex",
        "threshold": 0.9,
        "executable": "/usr/local/bin/quota-alert",
        "arguments": ["--provider", "codex"],
        "timeoutSeconds": 10
      }
    ]
  }
}
```

Supported events are `quota_low`, `quota_reached`, `quota_reset`, `provider_unavailable`, `provider_recovered`, and `refresh_failed`. Hook payloads use `QUOTAKIT_*` environment variables and JSON on stdin. Hide Personal Info omits account fields.

## iCloud Sync

QuotaKit has two private CloudKit paths:

- Mac-to-iPhone sync sends sanitized usage snapshots and never includes provider credentials.
- Mac fleet sync is separately opt-in. Portable settings and last-known snapshots can sync between Macs. API keys, cookies, and tokens sync only when the separate secret-sync toggle is enabled and are stored in CloudKit `encryptedValues`.

Hooks, machine-local executable paths, local source paths, menu geometry, debug settings, usage history, and cost ledgers do not sync through Mac fleet configuration.

## Validation

```sh
quotakit config validate
quotakit usage --provider codex
```

Keep the file private and use the app's provider settings whenever possible.
