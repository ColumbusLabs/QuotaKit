# QuotaKit Security Model

QuotaKit is a private, local-first tool for Codex, Claude, Cursor, and Grok. The Mac app reads only sources the user enables. The iPhone companion displays sanitized usage synced through the user's private iCloud account and never authenticates directly to a provider.

## Product Boundary

- Supported usage providers: Codex, Claude, Cursor, and Grok.
- No monetization, analytics service, hosted user-data backend, or remotely controlled feature configuration.
- Provider credentials are not part of Mac-to-iPhone usage sync.

## Allowed Data Flows

| Surface | May read | Must not read |
| --- | --- | --- |
| Mac app | Enabled provider sources, local settings, explicitly required Keychain/config values, sanitized usage history | Disabled providers, unrelated browser profiles, iPhone-only state |
| CloudKit usage sync | Sanitized quota, cost, history, account labels, device metadata, and notification records | Provider credentials, cookies, authorization headers, and raw provider responses |
| iPhone app and widgets | Sanitized CloudKit snapshots and local display caches derived from them | Provider endpoints, provider credentials, Mac Keychain/config files, and browser storage |
| Optional Mac fleet sync | Portable settings and, only when separately enabled, secret fields stored in CloudKit `encryptedValues` | Hooks, machine-local paths, and unencrypted secret fields |

## Credential Rules

- Credentials include API keys, OAuth access and refresh tokens, cookies, browser sessions, client secrets, and raw authorization headers.
- Credentials must never enter `SyncedUsageSnapshot`, `ProviderUsageEnvelope`, `WidgetSnapshot`, share cards, diagnostic exports, notification payloads, or ordinary CloudKit record fields.
- Mac fleet secret sync is off by default and must remain an explicit user choice. Secret fields use CloudKit end-to-end-encrypted values.
- Browser-cookie integrations remain explicit and provider-scoped. QuotaKit must not search unrelated profiles.
- The iPhone app must not contain provider login flows or provider fetchers.

## Local Storage Rules

- QuotaKit-owned config lives under `~/.quotakit` unless an explicit config override is set.
- Legacy `~/.codexbar` paths are compatibility inputs only; do not upload or broaden them without a reviewed migration.
- Release secrets belong in ignored local or CI secret storage. Never commit signing keys, provider credentials, browser caches, or local credential exports.

## Sync Contract

- CloudKit container: `iCloud.com.columbuslabs.quotakit`.
- App group: `group.com.columbuslabs.quotakit`.
- KVS suffix: `com.columbuslabs.quotakit.shared`.
- Shared sync JSON must use `CloudSyncConstants.makeJSONEncoder()` and `makeJSONDecoder()`.
- Classify new synced fields in `docs/data-inventory.md` before implementation.

## Attribution

- Preserve MIT notices and upstream attribution.
- Provider names and icons identify data sources only and must not imply affiliation, sponsorship, or endorsement.
