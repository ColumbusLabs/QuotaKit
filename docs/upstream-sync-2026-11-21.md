# QuotaKit upstream integration — 2026-11-21

Pinned upstream range: `1f6da9bec44455288ddee5ef6f3617a803d8eb2a..c94b855f308370c503c9f4caad9f1ca4e2151444` (23 linear commits; no merge wrappers).
Base QuotaKit: `2645b241ac40e2adb76fa59476f92a5954bedcfc`.

Preserve QuotaKit identity, release ownership, signing, entitlements, appcast,
Mac/iPhone wire compatibility and all existing provider IDs/order. This is source
integration only; build numbers and shipped upstream provenance do not advance.

## Commit accounting

| Upstream commit | Classification | Intent and adaptation |
| --- | --- | --- |
| `2331f1149ea9f7079a172d1d6f63b63d2e5ef62d` | Adapted | fix(museai): discover immutable subscription chunks |
| `8c0541ec4989d431710b256c80945013544b91c5` | Adapted | fix(providers): scope OpenAI balances and discover bundled agy |
| `9207c1c1450f6d8f9cda83c6b5caca10910a735d` | Adapted | fix(claude): keep account tabs in numeric slot order |
| `130fe9e93f069ea728f0fab43fefa2fcbbe156b3` | Adapted | fix(claude): chart Plan Usage from the presented account |
| `cfc3f60196546340806f33bbc622f7b5d17bf9f9` | Adapted | fix(claude): show shared local cost below swap accounts |
| `3b1983cc762169ec0d9bdfcd4c48db75eeba740c` | Adapted | fix(claudeplatform): cap optional credit grant details |
| `e6edfb87d5bcdcd942de8b11d111d6c132ee392e` | Adapted | fix(cli): reduce cost decode work and allow quota-only dashboards |
| `94cc400e1b190f444e2a4d1910c2d63cfbb47e9f` | Adapted | feat(providers): add MiMo API quota and Grok prepaid balance |
| `0ee3237a2757f82737255ecded13261a0efb14f5` | Adapted | test(l10n): share catalog loading in language tests |
| `a4897aef50b8d97e304aa44d6d73485f66afecb5` | Adapted | fix(openai): export remaining API credit balance |
| `bbc5e711bf292a451e3bc0d6a5f5b2b70723e1f6` | Adapted | feat(trustedrouter): add API key limit tracking |
| `2c3defa05ae0b013ceee5856954448691925fabd` | Adapted | fix(notion): support personal allowance pools and workspace credits |
| `311c5045b225ea32ecf5853418345e535c031251` | Adapted | fix(amp): recognize enterprise-paid workspaces |
| `bd8a12b34941cc0cf3ae3e41a2a3a5d1e32f82ff` | Adapted | fix(codex): preserve and price native Ultrafast usage |
| `74ba8a4122bf35814eff101ea85f1b281b4df867` | Adapted | fix(codex): limit retained cost reports to the requested period |
| `43f3c2805937dce65d5a37eff13ce4b3d13fccda` | Adapted | fix(cursor): read Tokscale JSON caches for local spend fallback |
| `0d9698e8c2571e36714b6a5436908766a5933156` | Adapted | fix(menu): align the cost history model scrollbar |
| `cc50e67c4eb856d001373c99149f8e34f50d3b4c` | Adapted | feat(plugins): show hover details on bar charts |
| `3c1d00de9df54371fb4fa58a14d952eed8b180a0` | Rejected | Upstream README generated-provider section and generator are absent from the QuotaKit-native README; existing README already introduces its linked catalog. Provider worker updates QuotaKit catalog directly. |
| `b1ec929e4eada4ccbb7cc1db0d019e59b8c58874` | Adopted | Correct status-setting documentation location to General → Refreshing, confirmed against QuotaKit preferences. |
| `ecb3498e67837ca34bca7ceddaeeb29191566697` | Rejected | Linux desktop compact Quick View targets unsupported Linux product UI; portable CLI remains supported. |
| `51219fac3b2635cc899ee6ff1f84f0da4f133472` | Adapted | Refresh compatible Swift dependency pins, acknowledgements and Chrome Dev mapping/tests; exclude absent Linux desktop and upstream release workflow changes. |
| `c94b855f308370c503c9f4caad9f1ca4e2151444` | Rejected | Upstream release 0.85.0 version and release changelog bookkeeping; QuotaKit owns release metadata. |

## Fork-specific adaptations

- TrustedRouter appends provider 115; all 114 prior identifiers and order remain.
  Mac-to-iPhone details allow only validated numeric display rows; secrets and account IDs stay local.
- Notion remains native. Personal Standard/Select credit pools use exact periods,
  omit unmeasurable buckets, and sync their actual labels. Optional workspace credits
  have a cancellable wall deadline of at most three seconds, fail soft, and remain separate from quota.
- Keep Claude’s existing lock path: changing it would allow old and new processes
  to bypass each other’s locks. Codex detail decode and range/proof-aware retained
  report projection already exist in the fork; regression coverage preserves those paths.
- Cursor canonical Tokscale JSON keeps QuotaKit’s unowned-local attribution and
  manual-account isolation. Raw CLI usage has separate all-account cache dimensions;
  quota-only dashboards retain the existing account projection.
- Upstream changelog hunks adjacent to product work are excluded throughout.
  The shipped provenance, build numbers, appcast, signing and entitlements stay unchanged.

- Ultrafast uses an additive schema 8 migration across file/day/verified aggregates.
  Existing schema 7 producer hashes remain compatible. Per-tier pricing, unknown-price
  proof and verified zero amounts survive reopening and aggregate-only restoration.
  Populated schema migration and native/cache/compact report regressions cover these paths.

## Validation

Final exact-head hosted CI and independent risk reviews recorded on the integration PR.
