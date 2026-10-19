# Upstream integration — 2026-10-19

## Frozen range and accounting

- QuotaKit source base: `8ba362f97568f1deff2e941fdf0c7df673cc59ec` (`origin/main`).
- Reviewed upstream base: `6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e`.
- Frozen upstream head: `59a7d46ac61338786e5d32d8324a3e414525e601`.
- 16 linear commits: all 16 product/test/documentation intents adapted. No merge wrappers, release-only commits, rejections, supersessions, or applicable deferrals.
- [Issue #252](https://github.com/ColumbusLabs/QuotaKit/issues/252) is the authoritative qualification and merge receipt.

| Commit | Decision | Subject | Evidence and QuotaKit adaptation |
| --- | --- | --- | --- |
| `0624aad8cb4fff6ae0dadeefd166c9b770790d1e` | adapted | fix(claude): include Claude Desktop Cowork sessions in cost history (#4622) | Desktop Cowork direct JSONL discovery, scoped Claude paths, deduplicated local history and fixtures. |
| `7f7977b988146413f1b4fd667eb5e121df92e5d6` | adapted | fix(claude): prefer OAuth before the CLI PTY in Linux Auto mode (#4615) | Retained Linux CLI Auto tries readable noninteractive OAuth before PTY; Mac app source policy remains distinct. |
| `7e31e74ea66257db7967a5748111854dcaf5b56b` | adapted | fix(codex): open the usage dashboard on its overview tab (#4607) | Codex usage dashboard targets its overview tab; fork descriptor identity remains unchanged. |
| `5077ed7b4b868befa5b2686eddfa0eac15f02896` | adapted | feat(settings): edit and reorder saved token accounts (#4625) | Edit/reorder token accounts in place; preserve UUID/metadata, active UUID, blank-secret behavior and dormant-source selection. |
| `096c957f9c5c2012c2fa4676d07dd0f7cf835401` | adapted | feat(menu): optionally show every account in Overview (#4626) | Optional cached all-account Overview; preserve provider cap, privacy, per-account ownership and existing plugin rows. |
| `25ecff11e5e8ca8ca59d242a0a2e9fc1394f8679` | adapted | fix(claude): keep cost history when source roots are unreadable (#4617) | Throw on unreadable existing source inventories before replacing persisted Claude cost history; tolerate missing-file churn. |
| `317bbe351c2e2c756fa7ed5ff0cc0d078edc724c` | adapted | fix(pi): make the session roots fingerprint independent of discovery order (#4618) | Sort and deduplicate Pi session roots before fingerprinting to avoid discovery-order invalidation. |
| `0373cd6122562bf235bf0c8fd3984f835fbf6152` | adapted | fix(opencodego): honor the configured app source and show the actual source (#4616) | Honor OpenCode Go configured Auto/Web source; report the actual selected source without bypassing cookie policy. |
| `6b4765df984f7473bfaf4cbbecd1cf07c19d2a4b` | adapted | feat(pi): retain token history for unsupported backends (#4628) | Retain unsupported backend/model token history as unpriced Pi data; preserve malformed/incomplete state and no cross-provider projection. |
| `9766555845287ca97ce0c1b213fc621a21bde6d8` | adapted | feat(opencodego): expose local history in the cost command (#4629) | Reuse bounded OpenCode Go local reader for cost CLI daily/model history and time-zone/unknown-token semantics. Preserve QuotaKit’s 365-day Available year period; explicit reader requests may span longer history. |
| `c286d3428cd8cb64b4b3eb827dc0484aa1e7693e` | adapted | fix(plugins): retain selected quotas and support row severity (#4627) | Retain user-plugin quota instance selection and refresh observation; additive validated severity for plugin detail rows. |
| `ac30c447f9d2eff4a55859e6c217d2425dff3349` | adapted | feat(plugins): allow user plugins to declare a monochrome SVG icon (#4608) | Optional strict monochrome SVG manifest icon, bounded validation before native decode, fixed bitmap and monogram fallback. |
| `d82bddb55ef6c00b720c9f77b59ae9367d816137` | adapted | fix(grok): use the _x.ai/billing ACP method for CLI billing (#4595) | Use ACP _x.ai/billing with existing Grok CLI parsing/error transport and synthetic billing fixtures. |
| `e1325bfd66433232004a77ece6ff407483a4228e` | adapted | fix(claude): share the per-entry limits parser between OAuth and Web (#4614) | One per-entry limits parser shared by Claude OAuth/Web, preserving valid entries beside malformed ones. |
| `348ad23ff72d2ba94566af141a79ae1e7f2a93f5` | adapted | fix(settings): disable provider order restore when already at default (#4592) | Default-order restore enablement compares the effective provider order to default; existing unknown configuration preserved. |
| `59a7d46ac61338786e5d32d8324a3e414525e601` | adapted | fix(cli): follow the active claude-swap account in Claude usage (#4631) | Auto Claude usage follows the active swap slot with one payload; explicit selections bypass, failures use labeled fallback retaining actual identity. |

## Dependencies and fork contracts

Cowork discovery and unreadable-inventory handling form one Claude history slice; integrate both before qualification. Pi root fingerprinting precedes unsupported-backend retention. OpenCode Go source selection and local cost CLI share the existing bounded reader. Plugin quota selection and generic rendering must retain full provider-instance identity through Overview/current selection. Native SVG decoding is reached only after strict allowlist and canvas validation.

Preserve all 106 first-party provider IDs/order and repository-owned manifests. No provider additions/removals or identifier migrations. Preserve token-account UUIDs and metadata, selected account identity, device-local Claude directory mappings and sync stripping/restoration, quota/unknown-token/unknown-price distinctions, and no-UI credential safeguards. Optional Overview preference defaults off. Older clients ignore optional presentation fields; missing severity retains existing appearance.

QuotaKit’s [cost reporting policy](cost-reporting-periods.md) deliberately bounds Available year to 365 days to protect the 30-day background/365-day visible-demand scan policy. The upstream fixture that assumes an unbounded All period is adapted to this documented contract; a separate explicit 400-day request verifies the new OpenCode Go reader path without widening app demand.

User plugins remain Mac-local: sync enumerates enabled first-party providers through `firstPartyProvider`, so plugin-only SVG/severity does not add an unsupported iPhone provider or change a wire schema. Shared/CloudKit/App Group/notification/widget identifiers, StoreKit, entitlements, signing, appcast/release inputs and every version/build number stay unchanged. Review actual shared call sites and hosted iOS compatibility before merge.

Do not wholesale import upstream CHANGELOG or documentation branding. Product notes use QuotaKit wording. Preserve QuotaKit/Columbus Labs identity, config/Application Support paths, helper names, support links, GitHub origin, and release ownership. Upstream docs/version references are adapted to current behavior without claiming QuotaKit shipped an upstream release number.

## Verification and CI eligibility

Use source inspection, `git diff --check`, documented generation and pinned write-formatting locally. All automated lint/build/tests run in existing GitHub CI. No real accounts, credentials, browser cookies, Keychain UI, live CloudKit, packaging, installation, relaunch or distribution. Independent adversarial source review covers account/config persistence, source history/cache error handling, CLI authentication ownership, and plugin input/native decode boundaries.

Before topic push/PR/merge, confirm live PUBLIC visibility and unchanged workflow sources. Topic push triggers no workflow; PR and main merge trigger only existing CI. Applicable runners: standard `macos-26`, `macos-15`, `ubuntu-24.04`, `ubuntu-24.04-arm`; no larger, self-hosted or reusable jobs. CI only restores existing caches and produces no artifact uploads/cache saves. Four existing caches total 7,053,015,615 bytes, below included 10 GiB; this batch creates no added cache/artifact storage. Manual/tag/release-only workflows are not triggered. No billing/payment/spending/storage-limit changes. [GitHub current billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions) and [standard runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) were checked live.

Final exact-head checks and independent review must pass before merge; earlier heads do not qualify changed source. Qualification, any repairs, merge tree/readback, cursor/tail and cleanup are recorded on the linked issue. Local user `main` remains divergent and must not be reset, rebased or mixed into this integration.

## Independent source-review adaptations

- New one-shot Claude swap usage must use QuotaKit’s explicit CLI opaque-operation context, matching the existing cards path; unscoped calls would always fall back. Tests inject adapter snapshots rather than reading accounts.
- Cost-only Desktop discovery propagates existing unreadable parent/directory errors into the scan before cache pruning, preserving previously admitted Cowork history. Normal missing-file churn remains removable.
- Shared Claude scoped-limit parsing retains QuotaKit’s existing all-models weekly fallback, rather than copying upstream assumptions about the surrounding parser.

## Fork seam and test fidelity

- Account-specific stacked/compact and Overview cards share the new UsageStore helpers, preserving QuotaKit Codex health and weekly publication-hold evidence. The generic live controller remains for QuotaKit-specific live-card behavior; the upstream CodexAccountCard file has no fork counterpart. Existing isolation tests use the store seam rather than constructing AppKit status bars.
- Plugin current selection retains ProviderInstanceID without replacing QuotaKit’s existing first-party layout/spend/cache/animation renderer. Plugin percent, errors and source changes invalidate icon observation; countdowns remain first-party only. Existing first-party typed resolver tests remain applicable, with a separate registered-plugin-before-first-snapshot regression.
- Generic detail-row redaction lives in MenuCardView.swift in this fork; severity is preserved there and in localization. Grok ACP round trips use the existing bounded subprocess fixture. Period-end parsing and authentication fallback remain covered at their existing shared parser/account-context seams.
- Cost-only Desktop discovery and budgeted live-session discovery share one walker; cost error reporting preserves cached history while finite metadata budgets remain enforced. Existing symlink-backed projects stay admitted, with fixtures for link targets and unreadable dynamic roots.

The Claude cache generation advances from 17 to 18 for changed history discovery. QuotaKit retains its existing internal core cache-report helper overloads used by Mac/Linux fixtures, so upstream test-only wrapper relocation is unnecessary; the unreadable-root behavior and its regression coverage are integrated.

## Hosted qualification repairs

Initial exact head `903d3a9d9` in run `39230743161` exposed a Swift strict-concurrency capture error in the ordinary usage account-fetch closure. Capture the final command context by immutable value after resolving the adapter fallback suffix; existing parallel-account and active-slot fixtures retain their behavior. This is a source repair, so a complete fresh exact-head hosted cycle is required; earlier head results do not qualify the repaired source.

The initial hosted lint also identified an obsolete Pi function-length suppression, explicit optional nil initialization, a multi-closure fixture call, and two test types just above the unchanged 800-line limit. Remove the obsolete annotation/initialization, label fixture closures, and move the added related tests into same-file extensions while retaining discovery names, assertions, actor/serialization semantics and all original lint thresholds.

Run `39231795860` compiled both Linux architectures and exposed stale Auto fallback traces in existing fixtures: update those expectations to Web/OAuth/CLI with unavailable OAuth, preserving explicit-source and noninteractive assertions. A named `@Sendable` availability closure avoids a SwiftFormat/SwiftLint layout conflict without changing the fixture. Hosted Mac compilation identified an upstream-only account-label helper; use QuotaKit's existing stable privacy ordinals and account-label redactor, preserving public workspace discriminators and ownership matching. Both independent reviewers cleared these repairs. A fresh complete exact-head hosted cycle remains required.

Run `39233834148` completed lint, both Linux architectures (571 portable tests each) and iOS (174 XCTest, 649 Swift Testing and four UI tests). Mac test compilation then exposed two fixture API mismatches: replace the absent upstream Overview settings helper with QuotaKit's isolated test settings/config store seam, and order the three account-editing fixture arguments according to the fork's `testSettingsStore` signature. Preserve all original persistence, selection, privacy and account-isolation assertions. These fixture repairs require another complete final-head hosted cycle; the earlier passing lanes are historical evidence only.
