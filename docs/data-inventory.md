# QuotaKit Data Inventory

Generated: 2026-06-07

This inventory classifies data that QuotaKit may read, store, sync, or display. The core rule is simple: credentials stay local to the Mac and never enter CloudKit or iOS.

## Classification

| Class | Meaning | Examples |
| --- | --- | --- |
| Public | Product metadata safe to publish. | App name, version, open-source license text, support URLs. |
| Local private | User data stored only on the local device. | Enabled provider settings, local usage cache, local history, diagnostic state. |
| Credential | Secrets or session material that can authenticate to a provider. | API keys, OAuth access/refresh tokens, cookies, bearer headers, browser sessions, client secrets. |
| Sanitized sync | Non-secret usage/account metadata allowed in the user's private CloudKit database. | Provider ID/name, account label/email, quota windows, cost summaries, token counts, history points. |
| Derived display | Local iOS/widget/share-card data derived from sanitized sync. | Cards, charts, locked feature state, notification copy. |

## Product Identifiers

| Field | Value | Class |
| --- | --- | --- |
| App name | `QuotaKit` | Public |
| macOS bundle ID | `com.columbuslabs.quotakit.mac` | Public |
| iOS bundle ID | `com.columbuslabs.quotakit.ios` | Public |
| iOS push extension ID | `com.columbuslabs.quotakit.ios.pushextension` | Public |
| Sync framework ID | `com.columbuslabs.quotakit.sync` | Public |
| App group | `group.com.columbuslabs.quotakit` | Public identifier, private container contents |
| CloudKit container | `iCloud.com.columbuslabs.quotakit` | Public identifier, private user database contents |
| KVS suffix | `com.columbuslabs.quotakit.shared` | Public identifier, private KVS contents |
| StoreKit product | `com.columbuslabs.quotakit.pro.lifetime` | Public identifier |

## Mac Local Inputs

| Data | Class | Notes |
| --- | --- | --- |
| Enabled provider list/source mode | Local private | User must explicitly enable each provider/source. |
| API keys/token accounts/OAuth tokens/cookies | Credential | Store/read locally only; never sync. |
| Browser cookie/profile discovery | Credential-adjacent | Advanced/high-risk; off by default. |
| Provider raw responses | Local private/credential-adjacent | Do not persist or sync raw responses unless separately reviewed and redacted. |
| Local usage logs/cost scans | Local private | May contain paths, prompts/project names, spend, token counts, timestamps. |
| Local debug logs | Local private | Must redact emails/tokens/cookies/headers where possible. |

## CloudKit And KVS

| Record/key | Fields | Class | Allowed? |
| --- | --- | --- | --- |
| `DeviceSnapshot` | `deviceName`, `deviceID`, `appVersion`, `syncTimestamp`, JSON `payload` | Sanitized sync | Yes, legacy compatibility only. |
| `DeviceProviderSnapshot` | `deviceID`, `deviceName`, `providerID`, `providerName`, `accountEmail`, `lastUpdated`, `encodingVersion`, compressed JSON `payload` | Sanitized sync | Yes. |
| `ProviderAccountLinkage` | `providerID`, `linkedIdentifiers`, `confirmedAt`, `confirmedFromDeviceID`, `unmerge` | Sanitized sync | Yes, user-confirmed account merge state. |
| `QuotaTransition` | `providerName`, `providerID`, `state`, `transitionAt`, `deviceID`, optional `accountEmail` | Sanitized sync / notification | Yes. |
| `com.columbuslabs.quotakit.usage.snapshot` | JSON `SyncedUsageSnapshot` | Sanitized sync | Yes, legacy KVS compatibility. |

Forbidden in all CloudKit/KVS fields: provider credentials, access tokens, refresh tokens, API keys, cookies, browser sessions, authorization headers, OAuth client secrets, and raw provider responses.

## iOS Local Data

| Data | Class | Notes |
| --- | --- | --- |
| SwiftData cost ledger/cache | Derived display | Derived from sanitized snapshots. |
| Snapshot cache | Derived display | May contain account labels/emails, cost, quota, token counts, history, and device names. |
| Demo data | Derived display | Must not look like real provider credentials. |
| StoreKit entitlement cache | Local private | Caches Pro display state only; not credential-bearing. |
| Share cards | Derived display | Must omit credentials and avoid provider affiliation claims. |
| Widgets/notifications | Derived display | Must read sanitized iOS-side data only. |

## Release And Signing Data

| Data | Class | Rule |
| --- | --- | --- |
| App Store Connect key ID/issuer ID | Credential metadata | Keep in ignored local env or CI secrets only. |
| App Store Connect P8/private key | Credential | Never commit. |
| Sparkle private key | Credential | Never commit. |
| Apple team ID/signing identity | Release metadata | Must be QuotaKit/Columbus Labs-owned before release. No upstream defaults. |
