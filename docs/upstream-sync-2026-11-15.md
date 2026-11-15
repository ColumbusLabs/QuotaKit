# CodexBar upstream integration for November 15, 2026

Tracking issue [#278](https://github.com/ColumbusLabs/QuotaKit/issues/278). The pinned range is
`71c557860d7d4ca1e7f7f769a3f3cda2f7367476..1f6da9bec44455288ddee5ef6f3617a803d8eb2a`.
It contains 21 linear commits and no merge wrappers.

| Upstream commit | Disposition | QuotaKit result |
| --- | --- | --- |
| `447846ac0` | Adapted | Keep two-row icons spanning custom layouts in high contrast and preserve style-appropriate rendering. |
| `e9df0eaf1` | Adapted | Pi/OMP session and project grouping uses QuotaKit's incomplete-scan reporting. Retain stale v9 totals during interrupted same-scope migrations and write complete v10 detail after a full scan. |
| `4d88d9584` | Adapted | Append Google Developer Program to the 113 existing provider IDs. Use request-scoped, nonpersistent browser sessions. Sync numeric grant usage and the fixed unapplied status in existing fields. Keep billing ID and dates on Mac. |
| `677f9437f` | Adapted | Show provider-reported credits, weights, and billing period. Preserve the independent Helmcode Cloud monetary wallet and tenant-specific legacy quota fallback. |
| `621082f02` | Adapted | Require a trusted partition before Muse credential payload reads. Preserve bounded explicit permission and denial cooldown. |
| `3a03789c2` | Adapted | Apply partition preflight to the exact Claude OAuth Keychain item, with separate memoization by persistent reference and profile isolation. |
| `5107b45a5` | Adapted | Preserve the color and span of leading brand icons in two-row layouts. Builds on `447846ac0`. |
| `c198bfbf8` | Adapted | Resolve Claude Overview through the same presented swap account as the card while preserving account source labels and optional card filtering. |
| `35e76eb7d` | Adapted | Build only the requested settings section with lazy account state and fork-specific route coverage. |
| `232905585` | Adapted | Add Terra and Luna Fast rates. Regenerate the parser hash with QuotaKit's tooling and invalidate stale reports while preserving native rows and checkpoints. |
| `22f731375` | Adapted | Group deduplicated Claude costs by project and session. Preserve fork scanner semantics and verified iPhone cost payloads. Filter session activity dates to the reporting range. |
| `b8071013e` | Adapted | Display DeepSeek's available UTC month-to-date spend with source coverage. Keep unverified account spend local. |
| `37d10a808` | Adapted | Use an explicit China browser source and preserve API-only Auto and regional origin validation. Reuse the existing mobile balance envelope. |
| `3712faee9` | Excluded | Upstream 0.84.1 changelog bookkeeping. Product changes have QuotaKit release notes. |
| `27f448df5` | Adapted | Stop candidate retry traversal when a task is cancelled. The upstream Replicate retry-strategy file is absent in QuotaKit's provider implementation. |
| `0e48b8bcc` | Adapted | Share a title view between native and community plugin usage cards. |
| `1a026e11f` | Excluded | Upstream changelog entries for changes integrated above. |
| `31d8b7552` | Superseded | Preview changelog entry removed by `e31db1492`, then recorded after the feature landed by `1f6da9bec`. |
| `e31db1492` | Excluded | Upstream changelog-only removal of the preview entry. |
| `7b4897e83` | Adapted | Include approved community plugin usage in Mac-local Statistics. Keep plugin IDs, model labels and spend out of share payloads and existing iPhone spend contracts. |
| `1f6da9bec` | Excluded | Upstream changelog entry for the integrated community plugin Statistics feature. |

The provider generator owns both manifests, aliases, and the provider ID inventory. The application catalog grows to
114. The release configuration, build numbering, appcast, signing, entitlements, and CloudKit record schema retain
QuotaKit ownership. Google monthly grants use existing billing fields without quota subscriptions or reset alerts.
