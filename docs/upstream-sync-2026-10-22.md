# Upstream integration — 2026-10-22

Frozen trusted upstream range: `489aad74fbd55a22db570c025b6d57aac654cd5a..8de11fffdf1a5db45f4d26197f947e2b4a37b6a7`. QuotaKit origin base: `a9dec697fd843ba5febf655bbbbf6cfc3193944c`. Tracking and authoritative final qualification: [issue #258](https://github.com/ColumbusLabs/QuotaKit/issues/258).

All 19 reachable commits are linear: 19 adopted/adapted product or relevant documentation intents, no merge wrappers, superseded commits, rejected whole commits, or applicable deferrals. Targeted adaptations retain fork behavior; no wholesale upstream merge. Every commit's source and dependencies were inspected; upstream release/changelog bookkeeping hunks are excluded throughout.

| Upstream commit | Decision | Intent and QuotaKit treatment |
| --- | --- | --- |
| `3509772d02a3fdfc7857e459609d22aa095dee28` | adapted | Highest usage compares quota windows, with QuotaKit-native settings explanation and docs. |
| `eb3c5dc36c822dc331a90bd329d28a7c7264c163` | adapted | Linux CLI 8 MiB stack reservation and synthetic cost smoke in both existing Linux CI runners; absent upstream musl-only lane/helper hunks omitted. Direct musl execution remains outside existing hosted lanes. |
| `ad0c5679b73c407db63871f6febe2d9b9dfb319f` | adapted | Grok wallet-only ACP fallback enriches weekly usage; port missing active-period validated implicit-zero provenance dependency, retaining unknown-usage safeguards. |
| `54164d4c30006581b5156b164b5528ebea8b59d6` | adapted | All-provider calendar slots distinguish measured zero from unknown; descriptors and charts preserve incomplete coverage. |
| `2e9c6246984450805a0d7f9b605be5d68bef1bf2` | adapted | Pinned unavailable widgets name the provider; QuotaKit setup copy, generated widget catalogs and state tests. |
| `3eda0841d85f1a5bbb7f2028bfb4094c1e21d74c` | adapted | Explain disabled layout editor and name the required Icon & percent style. |
| `7d12e43250cade8a539433214d127d65fb6dfb1e` | adapted | Monthly daily allowance targets with optional Codable quota metadata, plugin/native mapping and monetary/request/credit units; preserve fork card paths and sync contracts. |
| `f169240ad3cdf76eb2432865587aa304ed79ff18` | adapted | Align leading window-label columns using current QuotaKit renderer; explicit spacing and inline icons retain natural layout. |
| `724b2d023b7b2a1630e56f4aed2467893722ed7b` | adapted | About/Acknowledgements join Settings history while preserving pane-only launch restoration and QuotaKit update/About behavior. |
| `0be5da90533d3c39abd69d016fe6a933e53846a7` | adapted | Document ccx explicitly as a separately maintained upstream CodexBar CLI consumer, without claiming QuotaKit command compatibility. |
| `591e6008c86a36c06946b1ecda2759e8fbd143fc` | adapted | Pi official blue Mac/iOS palette, provider documentation/link, mobile current-version notes and all23 translated locales. |
| `8cb4d9345f15cfd7da365ecaa617e26f702aeb8b` | adapted | Localized complete relative countdowns and bare durations; retain fork numeric-overflow guards, Ukrainian/Asian grammar corrections and formatter regression coverage. |
| `540880f8c3d13e8196ff6c34dcc4305677161cbf` | adapted | Claude v7 report semantics retain priced subtotal/lower-bound coverage when days are unpriced, preserving legacy row-less metadata. |
| `b590039320d79b4c5b34622695722b8101c2f7a9` | adapted | Read OpenCode Go v2 session_message/compaction history; only usable legacy copies suppress v2 rows; idle immutable fallback remains read-only. |
| `932673aa68878faeee2847d5bf5767ca561fd8f0` | adapted | Codex sidecar-less WAL immutable fallback and post-read stability guards; preserve QuotaKit cursor/report architecture, validated metadata and compatible parser-cache predecessor. |
| `0a0eb15be8ad4a34beb13cc7ae16c8484d9752c7` | adapted | Per-request ephemeral plugin HTTP sessions and task-identity accounting, preserving redirects/cookies/credential/size controls. |
| `3e7c4d6a54fb89feba7675b893c3ee41364f6f29` | adapted | Localized QuotaKit Claude Keychain recovery guidance without credential probes or changed credential ownership. |
| `7f077ba0604931132af4ea374e100e3a4419839c` | adapted | Retain explicit versioned Antigravity model group names with parser/CLI regression coverage. |
| `8de11fffdf1a5db45f4d26197f947e2b4a37b6a7` | adapted | Presentation-only iCloud fleet menu-bar fallback through existing gated projection, local authority, highest-use ranking and remote-only derived-data suppression; no live login/sync mutation. |

## Fork boundaries and verification

Preserve all 106 provider identifiers/order and generated manifests, QuotaKit/Columbus Labs branding, bundle/App Group/CloudKit/notification and mobile compatibility, credentials and recovery safeguards. RateWindow allowance metadata is optional/backward decoded and Mac-local; fleet data remains presentation-only. Pi’s mobile palette change uses the current 1.11.4 notes block. Only UPSTREAM_MONITOR_BASE changes; upstream release provenance, product/build numbers, appcast, release artifacts/signing/entitlements remain unchanged.

No local Swift/Xcode tests/builds/lint suites, app packaging/install/relaunch, live provider accounts/cookies/credentials/Keychain/CloudKit data, release workflow, or binary distribution are authorized by this source integration. Cheap static/source checks and documented resource generators run locally; existing hosted CI qualifies final exact source. Independent GPT-6.1 adversarial review covers persistence/migration/auth/fleet contracts; final findings and CI repairs are resolved before merge and recorded on issue #258.

CI cost gate: live public repository; standard GitHub-hosted Ubuntu/macOS runners only for PR/main triggers, all matrix entries audited, no reusable workflows. CI restores existing caches only; no cache save or artifact upload. Existing cache footprint is 2,762,350,951 bytes, below the 10 GiB free repository allowance. No paid settings, caps or budgets changed. Reconfirm eligibility/workflows before workflow-triggering mutation. Official rules: https://docs.github.com/en/billing/concepts/product-billing/github-actions.

Primary local main has an unrelated unpublished commit and diverges from origin; it is preserved without reset/rebase/mixing. Integration uses isolated origin-based worktree. Hosted qualification/merge tree, postmerge cursor/tail and owned cleanup receipts belong on issue #258; this document makes no preemptive claim of passing tests or a merge.
