---
summary: "Data sources and behavior for QuotaKit's four supported providers."
read_when:
  - Troubleshooting Codex, Claude, Cursor, or Grok usage
  - Changing provider fetch order, labels, or capabilities
  - Reviewing Mac, CLI, widget, or CloudKit provider behavior
---

# Providers

QuotaKit supports exactly four provider IDs: `codex`, `claude`, `cursor`, and `grok`.

The Mac app and bundled CLI share the same descriptors, fetch strategies, normalized snapshots, and config. The iPhone app consumes snapshots synced from the Mac through the user's private CloudKit database. Widgets and notifications use the same four-provider catalog.

Existing config entries for retired provider IDs are tolerated as inert migration data. They are not enabled, fetched, displayed, synced, or exposed by the CLI. QuotaKit does not delete their credentials automatically.

## Data Sources

| Provider | Automatic source order | Other supported sources | Local cost/history |
| --- | --- | --- | --- |
| Codex | App: OAuth API, then Codex CLI. CLI: configured ChatGPT web data when available, then Codex CLI. | Explicit OAuth, CLI, and optional web-dashboard enrichment. | Scans Codex session and archived-session JSONL files. |
| Claude | Admin API when configured; otherwise OAuth, Claude CLI, and claude.ai session data according to runtime policy. | Explicit API, OAuth, CLI, or web selection. Optional claude-swap account inventory. | Scans Claude session logs. |
| Cursor | Cursor web/session API using the configured session source, with local Cursor authentication fallback where supported. | Explicit web source. | Usage/cost data supplied by Cursor's authenticated dashboard API. |
| Grok | `grok agent stdio` billing RPC, then grok.com billing data from the configured Chrome session. | Explicit CLI or web source. | Not currently supported. |

`auto` chooses only from a provider's declared sources. An explicit `web`, `cli`, `oauth`, or `api` selection does not silently switch to an unrelated source kind.

## Codex

- Provider ID: `codex`.
- Primary quota data comes from the Codex OAuth API or `codex app-server` JSON-RPC.
- The optional ChatGPT usage dashboard can enrich credits, code-review quota, and usage breakdowns.
- Multiple visible Codex accounts retain separate account and quota ownership.
- Local cost history scans `CODEX_HOME` or `~/.codex`, including `sessions` and `archived_sessions`.
- Status data comes from OpenAI's status service.
- Details: [codex.md](codex.md).

Codex has special reset-boundary protection for depletion/restore notifications and widgets. A stale positive sample must not announce a restore before the trusted depleted window resets.

## Claude

- Provider ID: `claude`.
- Supported sources include OAuth usage, an Anthropic Admin API key, Claude CLI usage, and claude.ai session data.
- Claude CLI status-line text is not parsed by default because users can customize it. Any structured status-line feed remains explicitly opt-in and fails soft.
- Claude can expose session, weekly, scoped weekly, extra-usage, and Daily Routines data when those fields are available.
- Local cost history scans Claude session logs.
- Optional claude-swap integration can surface multiple local Claude accounts without merging their identity.
- Details: [claude.md](claude.md).

Widgets preserve the last compatible Claude quota windows during a token-only refresh only when the quota-owner key still matches. Synthetic placeholder windows are not preserved as real quota.

## Cursor

- Provider ID: `cursor`.
- Cursor usage is fetched through its authenticated account/dashboard API using configured browser/manual session data or supported local app authentication.
- Snapshot layouts may expose Requests, Plan, Auto, API, or legacy Total/Auto/API lanes.
- Cursor cost summaries are provider-supplied rather than reconstructed from unrelated local logs.
- Details: [cursor.md](cursor.md).

## Grok

- Provider ID: `grok`.
- The preferred source is the Grok CLI billing RPC.
- The fallback reads grok.com billing data using a Chrome session or Grok auth state where supported.
- Billing cadence is retained so weekly and monthly quota labels and pace calculations do not depend on a guessed reset distance.
- Grok is available in the Mac widget provider picker.
- Details: [grok.md](grok.md).

## Configuration And Credentials

New installs resolve provider configuration from `~/.config/quotakit/config.json`. Existing installations may continue using `~/.quotakit/config.json` when no XDG config exists. `CODEXBAR_CONFIG` can point at an explicit file for compatibility.

The config stores provider enablement, ordering, source selection, token accounts, and non-Keychain settings. Sensitive material should remain in the established config or Keychain path for its provider. Never copy credentials into documentation, fixtures, CloudKit records, or logs.

Cookie imports and real credential reads can display macOS permission prompts. Automated verification must use parser fixtures, stub environments, test stores, and `KeychainNoUIQuery` rather than live account probes.

## Shared Presentation And Sync

- Provider identity remains siloed; an account label from one provider must never appear on another provider's snapshot.
- Generic quota rows preserve provider-supplied window/reset data.
- Codex and Claude retain their deliberate provider-specific quota/account presentation.
- Cursor retains its semantic lane layouts.
- Grok retains billing-cadence labels.
- CloudKit stores stable string provider IDs, so older records can be decoded and filtered without renaming the production schema.
- Mac and iPhone readers display only the four supported IDs and clean up stale notification subscriptions or records through the existing compatibility paths.
