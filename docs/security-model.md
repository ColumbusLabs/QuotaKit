# QuotaKit Security Model

Generated: 2026-06-07

QuotaKit is privacy-first software with a local Mac collector and an iOS companion. The Mac app may read local provider data only after the user explicitly enables a provider/source. The iOS app must not read, receive, store, or infer provider credentials.

## Product Boundary

- Product name: QuotaKit.
- Mac collector app: free and open source.
- iOS companion app: free install with optional Pro lifetime unlock.
- Pro product ID: `com.columbuslabs.quotakit.pro.lifetime`.
- No subscription logic in v1.
- No hosted backend for user data in v1. QuotaKit may read public Columbus Labs static config for non-secret OTA guardrails.
- No analytics by default.
- No credential sync ever.

## Allowed Data Flows

| Surface | May read | Must not read |
| --- | --- | --- |
| Mac app | User-enabled local provider sources, local settings, local keychain/config where explicitly required by that provider, sanitized local usage history, StoreKit-independent app settings | Disabled providers, unrelated browser profiles, iOS-only state |
| CloudKit private database | Sanitized usage snapshots, provider/account labels, quota/cost/history summaries, device metadata needed for sync, quota transition notification records | Provider credentials, access tokens, refresh tokens, API keys, cookies, browser sessions, raw provider responses |
| iOS app | Sanitized CloudKit snapshots, local demo data, StoreKit entitlements, local SwiftData/cache derived from sanitized snapshots | Provider endpoints, provider credentials, Mac keychain/config files, browser storage |
| iOS widgets/NSE | Sanitized iOS-side cache or CloudKit notification records | Provider credentials, Mac app group files, browser storage |
| Columbus Labs remote config | Public setup URLs, feature kill-switch IDs, app announcements, build recommendations | User data, provider credentials, StoreKit entitlement grants, executable code |

## Credential Rules

- Provider credentials are local-only Mac data.
- Credentials include access tokens, refresh tokens, API keys, OAuth client secrets, cookies, browser sessions, raw authorization headers, and raw provider responses.
- Credential values must never be encoded into `SyncedUsageSnapshot`, `ProviderUsageEnvelope`, `WidgetSnapshot`, SwiftData cache models, share cards, diagnostic exports, notification payloads, or CloudKit records.
- Browser-cookie integrations are advanced/high-risk and must stay off by default.
- iOS must not contain provider login flows or provider endpoint fetchers in v1.
- StoreKit entitlement state must never grant access to credentials; it only gates iOS features that consume sanitized snapshots.

## Local Storage Rules

- QuotaKit-owned local config should live under QuotaKit names such as `~/.quotakit`.
- Legacy `~/.codexbar` data must not be migrated, uploaded, or reused without explicit user action and a reviewed migration plan.
- Release secrets belong outside the repo under ignored QuotaKit-specific paths such as `~/.quotakit-secrets`.
- Real App Store Connect keys, P8 contents, Sparkle private keys, provider credentials, and local credential caches must never be committed.

## Sync Contract

- CloudKit container: `iCloud.com.columbuslabs.quotakit`.
- App group: `group.com.columbuslabs.quotakit`.
- KVS suffix: `com.columbuslabs.quotakit.shared`.
- The shared sync JSON encoder/decoder must remain centralized in `CloudSyncConstants.makeJSONEncoder()` and `makeJSONDecoder()`.
- Any new synced field must be classified in `docs/data-inventory.md` before implementation.

## Attribution And Branding

- Preserve MIT license notices and upstream attribution.
- QuotaKit must not use OpenAI, ChatGPT, Codex, Claude, Cursor, Anthropic, or provider logos as primary app branding.
- Provider names/icons may identify supported sources only when legally safe and must not imply affiliation, sponsorship, or endorsement.
