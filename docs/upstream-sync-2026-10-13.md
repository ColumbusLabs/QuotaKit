# QuotaKit upstream integration — 2026-10-13

Pinned upstream range: `f66d18fc6fbb85c7df056bdeef56992de0619038..b05a63dcbba612e204862b441a0f67fc04ac9860`.
QuotaKit source base: `1457ca2ea8f3aac179888c44a6e244bbcffc0793`.

All 62 reachable commits (28 nonmerge, 34 merge) are inspected, including independent merge resolutions: 32 adapted entries, 16 empty merge wrappers, 13 concrete exclusions and one named supersession. Product behavior is ported into QuotaKit rather than merging the upstream branch wholesale. Upstream release state, public appcast and distribution inputs remain unchanged.

## Commit ledger

| Commit | Subject | Classification and evidence |
| --- | --- | --- |
| `c4d4dbe58` | feat(fal): add fal credit balance provider | Adapted fal billing-read API key, balance-only descriptor/plugin and append-only Mac/mobile catalog contracts. |
| `7bcf523bf` | feat(flora): add FLORA workspace balance provider | Adapted FLORA explicit workspace/API key billing, month-to-date spend and balance-only presentation; final schema safeguards described below. |
| `28ded89ec` | Read Charm Hyper balance from signed-in dashboard | Adapted Hyper dashboard-session balance extraction while retaining the native Hypercredits mapper contract and API-key endpoint. |
| `15510d555` | Restore manual cookie recovery on expiry | Adapted explicit manual-cookie recovery after session expiry without automatic credential prompting. |
| `12868ddd8` | Merge remote-tracking branch 'origin/main' into feat/fal-provider | Rejected independent upstream release-changelog reconciliation; both product parents accounted separately. |
| `6d890c180` | Merge remote-tracking branch 'origin/main' into feat/flora-provider | Rejected independent upstream release-changelog reconciliation; both product parents accounted separately. |
| `43121f17a` | fix(typesafe): import cookies from all supported browsers | Adapted TypeSafe shared supported-browser traversal with Manual/Off and exact-domain consent boundaries. |
| `1e3302a6c` | docs(changelog): link TypeSafe browser import PR | Rejected upstream-only release-changelog PR-link bookkeeping. |
| `69ef0cb9e` | fix(typesafe): keep the catalog browser order in descriptor metadata | Adapted TypeSafe catalog-derived browser order in descriptor metadata. |
| `4a52de54e` | README: add TokenTV desk clock to integrations | Adapted community TokenTV desk-display documentation through neutral final `b8ea0c0b6` wording. |
| `8770f855c` | Cache OpenCode Go local usage scans and discover auto browser session | Superseded by `976d8a0aa` and final `79b212d35` bounded WAL/session chain. |
| `976d8a0aa` | fix(opencodego): cache local database scans with WAL fingerprinting | Adapted WAL fingerprints through final `79b212d35` bounded reader/cache; inode/device identity also guards atomic replacement. |
| `d3724b213` | Add Codex identified request subtotals over SSH | Adapted opt-in native Codex identified-request export and local/SSH subtotals with QuotaKit executable paths, no price estimates or cache writes. |
| `a72bc83ad` | Cover prior parser hash cache adoption | Adapted predecessor adoption using actual fork producer `7465d609f5f2dcfb`; retain all 55 existing compatibility hashes. |
| `ff5296734` | fix(typesafe): finish shared browser discovery | Adapted final TypeSafe shared-browser importer resolution with fork consent safeguards. |
| `495105b0f` | fix(hyper): keep the session repair focused on balances | Adapted Hyper dashboard balance/error/recovery resolution; API-key endpoint and manual cookie validation preserved. |
| `83d178f9e` | fix(fal): document unavailable balances without guessing the cause | Adapted fal missing-balance guidance without inferring authorization failure; synthetic plugin/screenshot coverage. |
| `6a5c4cc76` | fix(flora): refresh provider integration on top of fal | Adapted FLORA/fal catalog, generated manifests, widget and provider-contract resolution; upstream marketing/release artifacts excluded. |
| `fa2b14e5e` | fix(codex): preserve partial identified-request subtotals | Adapted healthy-file and earlier-source subtotals when files vanish, identities conflict or a later source/union overflows; unknown prices stay unavailable. |
| `b8ea0c0b6` | docs(readme): describe TokenTV integration neutrally | Adapted neutral TokenTV integration wording with explicit upstream/community provenance. |
| `308d04c92` | chore: merge the 0.74.2 development baseline | Rejected independent upstream release-changelog reconciliation; both product parents accounted separately. |
| `d1ef4f0ab` | chore: integrate current main and preserve Codex cache adoption | Adapted Codex predecessor-cache adoption resolution using the fork parser hash and compatibility inventory. |
| `f153cfb50` | test(codex): share predecessor cache adoption inventory | Adapted shared predecessor inventory coverage and synthetic subtotal tests in Mac/Linux targets. |
| `a08c91804` | fix(hyper): keep generated error handling lint clean | Adapted Hyper JavaScript/TypeScript error-handling cleanup without private-body leakage or loss of native units. |
| `c2bec84a4` | chore(typesafe): reconcile release notes with current main | Rejected independent upstream release-changelog reconciliation; both product parents accounted separately. |
| `284a54312` | chore(hyper): reconcile release notes with current main | Rejected independent upstream release-changelog reconciliation; both product parents accounted separately. |
| `a83a6d38e` | chore(fal): reconcile release notes with current main | Rejected independent upstream release-changelog reconciliation; both product parents accounted separately. |
| `6cda80591` | chore(flora): reconcile release notes with current main | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `5a6cd3782` | chore(tokentv): reconcile release notes with current main | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `79b212d35` | fix(opencodego): bound scan caching and discover permitted sessions | Adapted final bounded OpenCode Go WAL cache and consented Auto-session resolution. |
| `348215900` | test(opencodego): isolate required error requests | Adapted isolated OpenCode Go error-request fixtures; preserve required request assertions. |
| `3675a9c00` | chore: integrate reviewed browser dependency update | Rejected independent upstream release-changelog reconciliation; both product parents accounted separately. |
| `53a53800f` | chore: reconcile current main without changing Codex subtotal proof | Rejected independent upstream release-changelog reconciliation; both product parents accounted separately. |
| `082d5578c` | Merge remote-tracking branch 'origin/main' into HEAD | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `5c7bee02e` | Merge remote-tracking branch 'origin/main' into HEAD | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `0421ef377` | Merge #4447: Add Codex identified-request subtotals over SSH | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `b9b45de63` | Merge remote-tracking branch 'origin/main' into HEAD | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `a4591f83c` | Merge #4445: fix(opencodego): cache local database scans and discover auto browser session | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `7c9405761` | Merge remote-tracking branch 'origin/main' into HEAD | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `c27298aab` | Merge #4438: Add fal as a provider | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `4f54544be` | Merge remote-tracking branch 'origin/main' into HEAD | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `c250e1808` | Merge #4439: Add FLORA as a provider | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `3dcab0389` | Merge remote-tracking branch 'origin/main' into HEAD | Rejected independent upstream release-changelog reconciliation; both product parents accounted separately. |
| `d03c93954` | Merge remote-tracking branch 'origin/main' into HEAD | Rejected independent upstream release-changelog reconciliation; both product parents accounted separately. |
| `9477f5e36` | Merge remote-tracking branch 'origin/main' into HEAD | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `791c9e913` | Merge #4444: README: add TokenTV desk clock to integrations | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `f19f87e22` | refactor(cost): remove dead code from cost and usage fetchers (#4473) | Adapted behavior-preserving scanner options/model sorting/JSON-RPC forwarding cleanup while retaining fork scope, timeout, pricing and ownership. |
| `30ee1cf07` | Merge remote-tracking branch 'origin/main' into HEAD | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `d34d1bac2` | Merge #4435: Fix Charm Hyper sessions | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `a011ea03a` | Merge remote-tracking branch 'origin/main' into HEAD | Rejected independent upstream release-changelog reconciliation; both product parents accounted separately. |
| `8835eabf6` | Merge #4442: fix(typesafe): import cookies from all supported browsers | Adopted empty merge wrapper; both parent chains accounted, no independent resolution. |
| `590f42ae9` | refactor(store): remove dead code and duplication from UsageStore (#4468) | Adapted UsageStore identical timeout constants and redundant forwarding/state cleanup; fork account, no-UI, publication and recovery checks remain. |
| `c4acdac74` | refactor(minimax): remove dead code and duplication (#4476) | Adapted MiniMax region/parser/helper cleanup with existing authentication headers, request and logging semantics. |
| `6dda5346e` | test: measure two timing budgets without runner stalls (#4477) | Adapted renderer work timing to thread CPU and WorkBuddy deadline to its existing 30-second provider timeout; CI/test harness limits remain unchanged. |
| `6f45c0d32` | feat(menu): name the cost token after the history window (#4448) | Adapted Cost menu-layout token wording to the configured history window with translated Mac resources. |
| `b41a66b95` | fix(cookies): stop browser imports after a working session (#4478) | Adapted lazy native/browser header/jar candidates; validate sessions before advancing, retain selected-profile isolation and fork consent/cache contracts. |
| `447a5efce` | chore(deps): bump SweetCookieKit to 0.5.7 (#4485) | Adapted SweetCookieKit 0.5.7 exact `95ee9806fefd502fe7b69f1660b438c35f1048ce` in both locks; fork origin hashes and other pins unchanged. |
| `3a45dc7cf` | feat(settings): filter, search, and reversibly reorder providers (#4440) | Adapted provider word/alias search, enabled-only filter, reversible order/UndoManager and restoration that retains unknown/hidden configuration payloads. |
| `d554d4493` | test: let the real-cache catch-up test own its sleep release (#4488) | Rejected as redundant: the fork catch-up continuation harness has no release watchdog; the upstream real-cache fixture is absent. |
| `1321fe2d7` | fix(menubar): let a provider icon span two text rows (#4454) | Adapted full-height leading icon for ordinary single-provider two-row layouts; high-contrast, inline, warning and provider-tinted behavior retained. |
| `d1639ce82` | feat(menubar): add graphical progress bar layouts (#4436) | Adapted graphical quota bars and V5/V4/V3/V2 fallback persistence; corrected projection composition, balance/reset duplication and added downgrade/upgrade fixtures. |
| `b05a63dcb` | fix(menu): separate provider errors from stale-usage notices (#4496) | Adapted separate provider errors/stale rows and inline command rendering while retaining Settings combined preview and account/Codex publication-hold semantics. |

## Product slices and fork contracts

- Add fal account credit balances and FLORA workspace balance/spend. Retain all existing provider IDs and treat balance-only providers as billing sources rather than quota-transition subscriptions.
- Adopt TypeSafe shared-browser discovery, Hyper dashboard balance recovery, bounded OpenCode Go WAL scan caching and lazy browser traversal that stops after a validated session. Preserve manual/off policy, selected-profile isolation, consent coalescing, no-UI background access, denial cooldown and account ownership.
- Adopt opt-in local/SSH identified Codex request subtotals, strong-identity deduplication and explicit partial/unknown pricing. Retain native pricing and persistent cache compatibility; export observers do not change saved request rows or checkpoints.
- Adopt provider search/filter/reversible ordering, graphical bar layouts with old-version fallback persistence, full-height two-row provider icons, history-window cost token naming and distinct stale/error subtitles.
- Apply behavior-preserving cost/store/MiniMax cleanup only where the fork has the same caller contract. Timing tests use CPU budgets where measuring work and preserve test-owned gates; no assertion or CI gate is weakened.
- Regenerate repository-owned metadata with documented scripts. Preserve all 100 existing IDs and add fal/FLORA (102 total). New native credits and billing rows use existing shared wire fields; fal/FLORA remain outside quota-alert eligibility. iPhone icons/colors, billing allowlists, synthetic projection tests, the existing 1.11.4 note block and 23 translated locales are updated without schema/build/version changes.

## Verification and delivery

Local work is limited to source review, documented generation and cheap static checks. All Swift/Xcode automated tests, lint, compatibility/widget builds, Linux checks and shared/mobile verification run in existing GitHub CI. Independent adversarial review is required before merging the exact qualified head.

Live public visibility and every runner/matrix/trigger, current official billing rules, cache cap and artifact/budget storage eligibility are checked before workflow-triggering actions. No paid settings, larger runners, additional cache namespaces or discretionary artifacts are introduced.

The primary checkout and its local-only user commit are preserved. Only the automation-owned isolated checkout/branch may be modified or cleaned. No packaging, app install/relaunch, real credentials/accounts/cookies/Keychain/CloudKit access, release, appcast write or binary distribution occurs. UPSTREAM_VERSION and build/version metadata remain unchanged.

## Independent review corrections

Source review corrected V5 older projections discarding bars, duplicated reset text for balance fallback, a missing return, missing test import, cookie-broker tuple typing/MiMo return, Hyper native `hyperBalance` loss, and atomic OpenCode Go cache replacement identity. Scoped source checks and regression fixtures accompany each correction.

FLORA adaptations follow its [official API schema](https://developer.flora.ai/reference/operations/getworkspaceusage/): opaque non-whitespace `ws_` IDs are encoded as one path segment; missing or unknown required spend status fails explicitly rather than silently declaring an exact complete result. No real account probe is used.

## Current qualification blocker — 2026-10-13

Source checkpoint only: no PR, hosted CI, merge or cursor advancement. No automated Swift/Xcode tests, build or lint suite ran locally. All applicable hosted Mac/Linux/iOS/widget/architecture/golden gates remain required on the eventual exact head. Source review does not substitute for compilation or runtime qualification.

The live repository is public and every runner/matrix is standard/free-eligible, but future artifact storage eligibility is unresolved. At 09:14 UTC, 27 unexpired artifacts totalled 1,533,439,838 bytes (1.43 GiB), while GitHub Free reports 0.2/0.5 GB metered storage and 697.9 GB-hours with $0 billed. The $0 Actions budget has Stop usage enabled; this establishes current zero charges, not proof that the next failure-only iOS artifact upload fits free storage. Caches total 9,839,485,195 bytes (9.16 GiB), under the default 10 GiB cap.

Per the automation's strict storage rule, workflow-triggering actions stop pending confirmed free eligibility. No payment, budget, cache/storage cap or artifact deletion changes are made, and no local test substitute is used. UPSTREAM_MONITOR_BASE stays at f66d18fc; all applicable integration work remains unmerged and tracked under issue #242.

All three independent source reviews report no unresolved validated findings after corrections. Production source contracts are reviewed; all hosted compilation/runtime/lint gates are still pending. Ninety-five existing architecture line anchors were relocated using unchanged source matching blocks; their reasons and occurrence fingerprints remain unchanged except the deliberate new-provider catalog additions.
