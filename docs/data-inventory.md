# QuotaKit Data Inventory

This inventory covers the private four-provider product: Codex, Claude, Cursor, and Grok.

## Classification

| Class | Meaning | Examples |
| --- | --- | --- |
| Product metadata | Non-secret identifiers and version information | App name, bundle IDs, support URLs |
| Local private | User data stored on one device | Enabled providers, settings, usage cache, local history, diagnostics |
| Credential | Material that can authenticate to a provider | API keys, OAuth tokens, cookies, bearer headers, browser sessions |
| Sanitized sync | Non-secret usage/account data in the user's private CloudKit database | Provider ID, account label, quota windows, spend, token totals, history |
| Derived display | iPhone/widget/share-card data derived from sanitized sync | Cards, charts, notifications, local display cache |

## Product Identifiers

| Field | Value |
| --- | --- |
| App name | `QuotaKit` |
| macOS bundle ID | `com.columbuslabs.quotakit.mac` |
| iPhone bundle ID | `com.columbuslabs.quotakit.ios` |
| Push extension ID | `com.columbuslabs.quotakit.ios.pushextension` |
| Sync framework ID | `com.columbuslabs.quotakit.sync` |
| App group | `group.com.columbuslabs.quotakit` |
| CloudKit container | `iCloud.com.columbuslabs.quotakit` |
| KVS suffix | `com.columbuslabs.quotakit.shared` |

## Mac Local Inputs

| Data | Class | Rule |
| --- | --- | --- |
| Enabled provider and source mode | Local private | Only Codex, Claude, Cursor, and Grok are valid provider IDs |
| API keys, OAuth tokens, cookies, token accounts | Credential | Keep local unless the user explicitly enables Mac fleet secret sync |
| Browser profile discovery | Credential-adjacent | Restrict to the chosen provider and browser source |
| Raw provider responses | Local private / credential-adjacent | Do not persist or sync without separate review and redaction |
| Local session logs and cost scans | Local private | May include paths, project names, spend, token counts, and timestamps |
| Debug logs | Local private | Redact emails, tokens, cookies, and headers where possible |

## CloudKit And KVS

| Record/key | Contents | Class |
| --- | --- | --- |
| `DeviceSnapshot` | Legacy sanitized snapshot payload | Sanitized sync |
| `DeviceProviderSnapshot` | Per-device/provider/account sanitized envelope | Sanitized sync |
| `ProviderAccountLinkage` | User-confirmed account merge state | Sanitized sync |
| `QuotaTransition` | Provider quota state and notification metadata | Sanitized sync |
| `com.columbuslabs.quotakit.usage.snapshot` | Legacy KVS snapshot | Sanitized sync |
| Mac fleet records | Portable settings and optional `encryptedValues` secret fields | Local-private sync / credential when explicitly enabled |

Provider credentials, cookies, authorization headers, and raw provider responses are forbidden in Mac-to-iPhone payloads and ordinary CloudKit fields.

## iPhone Local Data

| Data | Class | Rule |
| --- | --- | --- |
| SwiftData cost ledger and snapshot cache | Derived display | Derived only from sanitized snapshots |
| Demo data | Derived display | Must not resemble real credentials |
| Share cards | Derived display | Omit credentials and avoid affiliation claims |
| Widgets and notifications | Derived display | Read sanitized iPhone-side data only |

## Release Secrets

Signing and notarization credentials belong in ignored local configuration or CI secrets. Never commit private keys, signing passwords, or provider credentials.
