# QuotaKit upstream integration — 2026-10-12

Pinned upstream range: `2786ed90e5234bd27b0b856c95a56623d04ed5e0..f66d18fc6fbb85c7df056bdeef56992de0619038`.
QuotaKit base: `ae493e2ec176520ea7d42ed8cdc65685694edd2b`.
All 45 reachable commits (26 nonmerge, 19 merge) are listed below: 21 adapted entries, 10 empty merge wrappers, 8 named supersessions and 6 concrete exclusions. Nonempty merge resolutions were inspected separately. No wholesale upstream merge or upstream push is used. No applicable slice is deferred.

The October 6, 2026 Auto-review pricing cutoff is adopted from upstream policy. Leaf creator metadata proves thread creation context, not a later authentication change; the new rule intentionally follows upstream for API-key resumes of a ChatGPT-created thread. Saved amounts and explicit custom rates remain authoritative.

## Product and fork adaptations

- Integrate the complete Kimi Desktop, browser/dependency, Codex read/pricing/title, and Claude/menu chains as one coherent batch.
- Mac pricing changes alter mobile-consumed cost values through the existing sync envelope. Add iPhone synthetic wire/merge tests for known-zero Auto-review costs, unresolved zero placeholders, custom-priced usage and complete downward correction retaining tokens. This deliberately triggers existing hosted iOS verification without changing schema, app source, build/version or release notes.
- Preserve all 100 provider identifiers, generated catalogs, Mac-to-iPhone and CloudKit/App Group/notification/StoreKit contracts, QuotaKit branding and release ownership.
- Preserve the existing fork's persistent scanner/cache recovery and account ownership safeguards; regenerate parser metadata through the documented tool rather than copying upstream generated hashes. The compact default Mac daily-report projection must use the same waiver/custom-rate/coverage semantics as detailed and hourly reports. Settled compact histories reprocess through the existing bounded queue when pricing fingerprints change. Aggregate-only history with no retained requests uses the existing aggregate estimate and never a request waiver; unmatched retained requests remain unresolved.
- Share the stored-layout projection through `UsageStore`, retaining surface-specific privacy/currency inputs and QuotaKit's filtered named extra windows. Remove only two obsolete architecture allowances for branches eliminated by this extraction; preserve the scanner and gate policy.
- Adapt QuotaKit's Aliyun no-UI fallback to the shared prompt contract: remove obsolete allowance calls and prevent preflight metadata from writing an interactive-denial cooldown. Ambient and selected-account Antigravity probes forward the guarded subprocess environment explicitly.
- Release bookkeeping and temporary superseded candidate scaffolding are excluded deliberately. Package lock changes are limited to the required reader dependency.
- Settings observation and queued settings refresh remain background work; manual coalescing cannot promote automatic work to interactive credential access.

## Commit ledger

| Commit | Subject | Classification and evidence |
| --- | --- | --- |
| `985e603c3` | Add bounded Kimi Desktop current-session candidate | Superseded by `a1c0aff61` final Desktop reader integration; transient candidate package/test/docs scaffolding omitted. |
| `1d059cee2` | Point Kimi verification at published reader proposal | Superseded by `a1c0aff61`; published-reader proposal instructions became obsolete once the dependency shipped. |
| `310eb72d1` | Gate current-record tests on the paired reader | Superseded by `a1c0aff61`; current-record regression runs against the shipped reader without candidate build guards. |
| `6acc6b2da` | Revalidate Desktop sessions before Kimi dispatch | Adapted dispatch-time current-session revalidation through the final `a1c0aff61` design. |
| `c3110630a` | Explain recovery after Kimi Desktop session changes | Adapted session-change recovery hints through final Desktop errors/tests. |
| `4e1d2c87d` | fix(claude): show prepaid usage credits in menu bar Balance layouts | Adapted descriptor-driven Claude prepaid Balance projection; no fabricated percentage quota or alert lane. |
| `84b1652bb` | Omit Codex request ledger from status and activity read views (#4421) | Adapted metadata/status/activity cache projection without request ledgers; scanner writes preserve persisted ledger. |
| `b65a5eb3d` | fix(claude): hide the prepaid menu bar balance with optional credits | Adapted optional-credits visibility through every stored-layout projection and icon signature. |
| `43b2054c0` | Detect Firefox Developer Edition default profiles | Adapted Firefox Developer Edition default-profile detection and synthetic regressions. |
| `77a37e6e1` | fix(codex): keep request ledgers out of warm read views | Adapted independent warm-cache resolution: request ledgers remain omitted on warm read views; regression retains metadata. |
| `8221c9e27` | Merge remote-tracking branch 'origin/main' into HEAD | Adopted empty merge wrapper; both parent slices accounted, no independent remerge resolution. |
| `bff13e93c` | Merge #4424: Omit Codex request ledger from status and activity read views | Adopted empty merge wrapper; both parent slices accounted, no independent remerge resolution. |
| `a9fee2461` | fix(claude): share prepaid balance layout projection | Adapted independent shared UsageStore prepaid/window/render projection to QuotaKit account/privacy/currency/forecast contracts and filtered named extras. |
| `03c7c4104` | feat(cost): show conversation titles in Cost menu (#4434) | Adapted local conversation titles in Cost menu with existing account filtering and identity fallback. |
| `9b0e7ab84` | Merge remote-tracking branch 'origin/main' into HEAD | Adopted empty merge wrapper; both parent slices accounted, no independent remerge resolution. |
| `0dbb74091` | Merge #4422: fix(claude): show prepaid usage credits in menu bar Balance layouts | Adopted empty merge wrapper; both parent slices accounted, no independent remerge resolution. |
| `1d7151bb7` | Merge remote-tracking branch 'origin/main' into HEAD | Adopted empty merge wrapper; both parent slices accounted, no independent remerge resolution. |
| `444821be5` | Merge #4431: Detect Firefox Developer Edition default profiles | Adopted empty merge wrapper; both parent slices accounted, no independent remerge resolution. |
| `79831b475` | chore(release): prepare 0.74.1 | Rejected upstream release-only CHANGELOG heading; QuotaKit owns versions and releases. |
| `7c08c0ae7` | docs: update appcast for 0.74.1 | Rejected upstream appcast release entries; QuotaKit appcast remains unchanged. |
| `e92d0ed0f` | chore: start 0.74.2 development | Rejected upstream development version/release bookkeeping; QuotaKit version/builds unchanged. |
| `1309f21bd` | Antigravity: keep agy usage probes from opening browser sign-in | Superseded by `5114f84fe` final inline noninteractive browser-launch guard. |
| `6ee04fb84` | fix(cost): price free Codex Auto-review requests at $0 | Superseded by `5f2af7566` final report-copy pricing; transient separate included-usage implementation removed upstream and omitted. |
| `a10b9a0df` | docs(changelog): reference #4453 | Rejected upstream release-changelog PR reference only; product intent recorded in native QuotaKit notes. |
| `1d4d5db25` | chore(deps): bump SweetCookieKit to 0.5.6 | Adapted SweetCookieKit 0.5.6 manifest/lock dependency, consolidated by `f497e48c5`. |
| `999978609` | fix(cost): keep uncovered free Auto-review requests off list prices | Superseded by `5f2af7566` final uncovered daily/hourly correction in the shared pricing path. |
| `636af1f1f` | fix(cost): let an explicit custom rate price free Auto-review requests | Superseded by `5f2af7566` final custom-rate precedence without the obsolete included-usage subsystem. |
| `5114f84fe` | fix(antigravity): block browser sign-in during usage probes | Adapted blocker for browser sign-in during Antigravity probes with selected-account and synthetic session coverage. |
| `a1c0aff61` | feat(kimi): enable current Desktop session discovery | Adapted nonempty Kimi merge resolution enabling final current Desktop session discovery with shipped dependency; candidate-only scaffolding omitted. |
| `8996605dc` | fix(codex): simplify free Auto-review request pricing | Adapted independent simplification merge resolution through `5f2af7566`: optional leaf metadata and bounded parser migration; broad transient included-usage subsystem omitted. |
| `5f2af7566` | fix(codex): preserve Auto-review pricing evidence | Adapted independent final pricing merge resolution, persisted zero-price evidence and custom-rate precedence; fork parser compatibility regenerated. |
| `47cf7fc4e` | test(deps): preserve explicit interactive browser coverage | Superseded duplicate by `f497e48c5` final explicit-interactive test/documentation coverage. |
| `7f1ec1f8a` | Merge #4451: Antigravity: keep agy usage probes from opening browser sign-in | Adopted empty merge wrapper; both parent slices accounted, no independent remerge resolution. |
| `5181d6962` | Merge remote-tracking branch 'origin/main' into HEAD | Adopted empty merge wrapper; both parent slices accounted, no independent remerge resolution. |
| `db753e8ef` | Merge #4453: Price free Codex Auto-review requests at $0 | Adopted empty merge wrapper; both parent slices accounted, no independent remerge resolution. |
| `e2a1fcc97` | test(cursor): treat Ego Lite as unmapped for interactive login | Adapted Cursor Ego Lite unmapped interactive-login expectations via final dependency chain. |
| `25ef0d017` | test(deps): preserve explicit interactive browser coverage | Adapted explicit-interactive browser test coverage via final `f497e48c5`. |
| `4cc45e7bf` | chore(deps): preserve concurrent browser coverage follow-up | Adapted nonempty merge resolution preserving concurrent Cursor coverage without duplicate assertions. |
| `17d621a98` | chore(deps): merge current main for changelog integration | Rejected independent upstream CHANGELOG conflict resolution only; dependency behavior accounted separately. |
| `11c313a25` | chore(kimi): integrate reviewed dependency and current main | Adapted nonempty Kimi/dependency merge resolution retaining final concurrent browser coverage; upstream CHANGELOG conflict ignored. |
| `f497e48c5` | chore(deps): bump SweetCookieKit to 0.5.6 (#4459) | Adapted consolidated SweetCookieKit 0.5.6 dependency locks and final explicit-interactive browser tests/docs. |
| `053a018f3` | Merge remote-tracking branch 'origin/main' into HEAD | Rejected independent upstream CHANGELOG conflict resolution only; both product parents accounted separately. |
| `ab8367a63` | Merge #4416: Add bounded Kimi Desktop current-session discovery | Adopted empty merge wrapper; both parent slices accounted, no independent remerge resolution. |
| `e79974386` | fix(keychain): bound browser cookie prompts per refresh (#4464) | Adapted shared atomic manual prompt allowance, no-UI-first reads, denial cooldowns, CLI explicit override and background settings refresh. |
| `f66d18fc6` | fix(menu-bar): redraw meters after leaving a stored layout (#4463) | Adapted stored-layout transition cache invalidation and meter/critter redraw regression. |

## Verification and delivery

Source review and cheap static checks are local. Swift/Xcode tests, lint, compatibility/widget builds, Linux fixtures and affected shared/mobile gates run only in existing hosted CI. Independent adversarial source review covers credential behavior and persistent data/pricing before merge. Exact-head hosted qualification and merge evidence are recorded in the PR and upstream-sync issue #240.

Before workflow-triggering actions, verify live public visibility, every standard runner/matrix, unchanged zero-dollar stop-usage budgets, included artifact storage and the existing 10 GB automatic-eviction cache cap. No larger runners, paid usage/settings/caps, discretionary artifacts or cache namespaces are introduced.

No release, appcast change, build/version bump, packaging/install/relaunch, live credential/account/Keychain/cookie/CloudKit probe or binary distribution occurs. The monitor cursor advances only with the fully accounted merged batch; shipped upstream version remains independent.

Dependency metadata note: both lockfiles retain their QuotaKit origin hashes and change only the required SweetCookieKit exact pin. One SwiftPM resolve occurred with installed Xcode 27 / Swift 6.4 before the worker was stopped from further unpinned generation; it changed no other pins or origin hash and is not verification evidence. Pinned Xcode 26.3 / Swift 6.3.3 is unavailable locally, so builds and dependency verification remain in hosted CI. No local Swift/Xcode build/test or automated lint suite ran.
