---
summary: "QuotaKit CLI configuration commands for the four supported providers and isolated config files."
read_when:
  - Using quotakit config from scripts or CI
  - Enabling or disabling providers without opening Settings
  - Storing provider API keys from the command line
---

# CLI configuration

`quotakit config` edits the same resolved config file used by the app's Settings → Providers pane.
New installs use `~/.quotakit/config.json`; absolute `XDG_CONFIG_HOME` paths resolve to
`$XDG_CONFIG_HOME/quotakit/config.json`; `QUOTAKIT_CONFIG` overrides the path, and `CODEXBAR_CONFIG` remains supported
for migrated installs.
The CLI writes the file with `0600` permissions.

## Providers

QuotaKit supports Codex, Claude, Cursor, and Grok. Their CLI names are `codex`, `claude`, `cursor`, and `grok`.

List persistent provider toggles:

```bash
quotakit config providers
quotakit config providers --json --pretty
```

Enable or disable a provider:

```bash
quotakit config enable --provider grok
quotakit config disable --provider cursor
```

These are persistent app/CLI settings. They are different from `quotakit usage --provider grok`, which is a one-shot
command override and does not edit config.

If every provider is disabled, `quotakit usage` with no `--provider` prints no text output, and
`quotakit usage --json` prints `[]`. Passing `--provider <name>` still fetches that provider for the one command.

## API keys

Of the four supported providers, only Claude accepts a config-backed API key. This is an Anthropic Admin API key used
for organization usage data:

```bash
printf '%s' "$ANTHROPIC_ADMIN_KEY" | quotakit config set-api-key --provider claude --stdin
```

`set-api-key` enables the provider by default. Add `--no-enable` when you only want to save the key:

```bash
printf '%s' "$ANTHROPIC_ADMIN_KEY" | quotakit config set-api-key --provider claude --stdin --no-enable
```

Codex uses OAuth or the Codex CLI. Cursor and Grok use their existing session/browser or CLI authentication. Passing
any of those three providers to `set-api-key` returns an unsupported-provider error.

## Isolated config files

For tests, demos, and CI, point QuotaKit at a temporary config file:

```bash
export QUOTAKIT_CONFIG=/tmp/quotakit-config.json
quotakit config enable --provider grok
quotakit config providers --json --pretty
```

The override applies to both reads and writes for the current process environment.

## Cost history window

The app setting controls the menu's local cost-history window. For one-off CLI reports, pass `--days`:

```bash
quotakit cost --provider codex --days 90
quotakit cost --provider claude --days 180 --format json --pretty
```

The accepted range is 1...365 days.

## Validation

After hand-editing config:

```bash
quotakit config validate
quotakit config dump --pretty
```

`dump` prints normalized config, including supported providers omitted from a hand-written file. Unknown entries from
an older config remain decodable for migration compatibility, but the CLI does not treat them as supported providers.
