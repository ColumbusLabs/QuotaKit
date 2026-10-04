# Upstream integration — 2026-10-04

## Pinned scope

QuotaKit origin/main `3782f3269f678d9fdff5c35338a9b55040699d13`. Reviewed upstream `917ae1465d984710817f8010a824612f74b1a6f9..da94819933302a44f501e84fb74f81dfa737bef4`: 32 DAG commits (23 non-merges, 9 merges). Every commit and merge resolution inspected; 22 product commits/resolutions adopted or adapted, 6 bookkeeping commits/resolutions rejected, 4 empty wrappers accounted. No applicable slice deferred. Intermediate generated parser hashes superseded by QuotaKit regeneration.

Work starts in an isolated worktree. Preserve all 89 existing provider IDs, quota subset 72, QuotaKit/Columbus Labs identity, iCloud/App Group/notification/widget contracts, production environment, release configuration, public appcast, signing inputs and all versions/build numbers. Only reviewed upstream cursor/date advance; shipping UPSTREAM_VERSION remains v0.69.0. No real accounts, credential reads, Keychain UI, cookie imports, CloudKit writes, app launches/packages or distribution.

## Fork-native adaptations

- Codex typed response accounting ports into QuotaKit replacement-scan staging, lazy hydration, daily-spend proof, fork/source-row recovery and saved pricing. Native parser revision 7→8; predecessor fingerprints retained, generated hash derived from QuotaKit source; optional ledger metadata does not change SQL tables or synced payloads.
- Automatic discovery shares bounded 2s/eight-pass bursts, with stable validated-window publication, pause/cancellation guards and minimum post-burst sleep preserved.
- Claude promotional cloud dollars use existing generic detail rows separately from quotas, prepaid usage, pacing and spend. Narrow Claude iCloud allowlist carries only the cloud-dollar row; live reset-credit inventory and credential rows stay local. iPhone overview/detail presentation reevaluates cached expiration. Existing optional providerDetails schema stays compatible.
- Antigravity additional profile homes use native QuotaKit settings/config and all cost entry points; OAuth discovery keeps client ID and secret paired by source.
- Muse membership validation preserves selected team and CLI-email binding, cookie role-limit retention and shared five-request budget. SweetCookieKit 0.5.5 uses existing pinned dependency machinery; root/widget pins align. Shared cookie retries and native LithosAI balance stay outside quota budgets.

## Verification and cost boundary

Hosted CI owns lint, Mac/Linux builds/tests, plugin goldens, compatibility and iOS simulator verification. Local work is source review and cheap static checks only; no local build/test/lint. Independent range audit and adversarial ledger/auth/sync reviews precede merge.

Live repository visibility PUBLIC. Only CI triggers for PRs/main pushes; standard ubuntu-24.04, ubuntu-24.04-arm, macos-26, macos-15 runners, no reusable or larger runners. Release workflows require tags/release/manual events and monitor requires schedule/manual; none requested. Official free-public-standard-runner rules: https://docs.github.com/en/billing/concepts/product-billing/github-actions.

Live ColumbusLabs account billing: GitHub Free, Actions $0 spent/$0 budget/Stop usage Yes; $0 billable after included public-use discounts; Actions storage 0.1GB/0.5GB included. Cache storage was 6,645,800,910 bytes below 10GiB; dependency bump requires ordinary new cache keys, so only audited obsolete main caches may be removed for free headroom. No budget/payment/limit settings changed or new artifact uploads introduced. Existing iOS failure-result upload remains under current free stop controls.

Baseline main CI 37166222224 had a repeatable timeout in SyncCoordinatorMultiAccountTests, “Two Enterprise Macs with hostless IDs and the same label stay distinct,” during its second synthetic fixture construction. Grouped and individual attempts both timed out after 120s; other jobs passed. Read-only inspection confirmed injected stores/pusher and testing startup, but did not prove the blocking call. This is pre-integration evidence, not a waiver; exact integration head must pass applicable gates.

## Complete commit ledger

| Commit | Disposition | Representation or reason |
| --- | --- | --- |
| `745bf89a3fc37bee53c644cfac11a435349552c3` | Adopted/adapted | Claude cloud-dollar parsing and generic detail publication; final presentation a701a0de. |
| `ffdcee31b9088499bf475b26cd1d54b723d51abd` | Adopted/adapted | CLI credit labeling represented by final provider-independent renderer in a701a0de. |
| `f087262d9221d162fe7796fb9463e96675415b6d` | Adopted/adapted | Separate balance visibility, cached expiry and shared menu presentation; final a701a0de. |
| `f1f77baf7d34ba0b9f6f5f6a0762157da7c37ad7` | Adopted/adapted | Typed request identities and durable per-file ledger state; adapted through 8ecdd31c. |
| `b66c10cc1ce0b80d60c77f53343dc73ed41e988f` | Adopted/adapted | Swift 6.2/Linux compatibility in final request-ledger implementation. |
| `9e48be06431b73a2bb7e4c4db193841287f4ed98` | Adopted/adapted | Request ownership, replay boundaries and migration fixtures in final ledger chain. |
| `8faab770f03340f1d8cf378733609972dda7c778` | Rejected | Rejected: upstream changelog ordering only; QuotaKit release notes have independent ownership. |
| `e7e325e23d9d9fe7dc1b5f901a489783bea5ae9d` | Adopted/adapted | Execution identity preserved across metadata-only incremental boundaries. |
| `18ccd38ee7d87b656cdc26207ca5d26d6412a78f` | Adopted/adapted | Saved pricing preserved when typed response rows replace legacy mirrors. |
| `c04fc93f91f17984d9dff93a556e553e750f2c1c` | Rejected | Rejected: upstream public appcast 0.71.1; QuotaKit appcast/distribution excluded. |
| `3bbf6bc48c20d8e507b30ed93dbdce19ed928bb6` | Rejected | Rejected: upstream 0.71.2 version and release bookkeeping. |
| `bfe5a58029e26ff54fac3da2ff6885ffbaa3938d` | Adopted/adapted | Blank-email Muse browser sessions bound through verified team membership; final 05bd2a44. |
| `263858dfc3529aec7a7491b06cbcdc9bacf77d39` | Adopted/adapted | Muse searches later sessions after unbound team-list errors; final 05bd2a44. |
| `20b1c4b4d8fd0529e5c26a872ad62ce08cfad299` | Adopted/adapted | Muse unbound session and invisible-selected-team regressions; final 05bd2a44. |
| `1aa809cc357abd77795c18acfc98add9aba62642` | Rejected | Rejected: upstream-only changelog issue-link bookkeeping. |
| `d2cb59866ec07bc1068c91722cfe70de4ac7d0cd` | Adopted/adapted | Email-matched Muse sessions prioritized within shared request budget; final 05bd2a44. |
| `05a6a4344631b633813ffefc3732dd5ac1c83974` | Adopted/adapted | Display-safe live OAuth reset inventory; bounded retries and uncached transport via final 4bd90c43. |
| `a701a0de44f284f7c80af8f484548ff2f70e685f` | Adopted/adapted | Meaningful merge resolution: shared credit row constructor, provider-independent CLI, publication fixtures. |
| `d295276e5d9897b50356b69496eebcf138b9e64b` | Accounted merge | Accounted merge: empty remerge delta; Claude parent chain represented by a701a0de. |
| `c8e53a31853423d5fbb2481e3d17fe826e364689` | Adopted/adapted | Additional Gemini profile homes in settings/config/local scans and CLI/dashboard cost paths. |
| `bc7e2011d5dbde7487414c8afb6aec0df0918207` | Adopted/adapted | SweetCookieKit 0.5.5 root/widget pin; expanded MuseAI/Cursor browser import and plugin errors. |
| `8ecdd31c54dada9f77f2de97236ed96e64ffcc12` | Adopted/adapted | Meaningful merge resolution: shared request decoding, narrow aliases, canonical dates, partial snapshots. QuotaKit process fixture already waits parent/child readiness and observed reaping; upstream fixture hunk is inapplicable. |
| `c0915b587ed5152ac57085807dc13c35a97126e8` | Adopted/adapted | Bounded automatic discovery 2s/8 passes without initial sleep; preserved QuotaKit stable-window and mode/cancellation safeguards. |
| `ed0f8700266658485e22472779e92c9e201f3120` | Rejected | Rejected: merge resolution only removes duplicate upstream changelog notes; parent product work accounted separately. |
| `a555a82bad569e801e1628a43ceb507b0764b337` | Accounted merge | Accounted merge: empty remerge delta; final ledger chain includes 8ecdd31c. |
| `05bd2a44fd2f4eac0c7066ed27525ea0aa11ea05` | Adopted/adapted | Meaningful merge resolution: shared Muse browser reader, membership identity validation, role-limit cookie retention, five-request budget. |
| `5e99cf4b68373df3ad53858caaaa65e57c29297f` | Rejected | Rejected: upstream changelog insertion/order bookkeeping only. |
| `423b7280d415c8ced488bff0ffb113f220863007` | Accounted merge | Accounted merge: empty remerge delta; Muse chain represented through 05bd2a44. |
| `6dca28df4a543ee445fd12717057c1dd7b1f572d` | Adopted/adapted | OAuth client ID/secret paired within same discovery source; cancellable onboarding and injected fixtures. |
| `7180cf777e04b27c78394e5c914cbe442a0f794a` | Adopted/adapted | Shared cookie permission retries/cache eviction and native LithosAI menu-bar prepaid balance. Upstream LongCat test deletion is inapplicable: QuotaKit still supports its parser/cookie/snapshot behavior, so native coverage is retained. |
| `4bd90c43b924670896ca7c5c7a8080ac8dd04654` | Adopted/adapted | Meaningful merge resolution: one fallback for optional inventory query, uncached redirect-guarded ephemeral transport, shared quota/spend-only constructor. |
| `da94819933302a44f501e84fb74f81dfa737bef4` | Accounted merge | Accounted merge: empty remerge delta; Claude reset chain represented through 4bd90c43. |

Storage audit: with no active QuotaKit workflow and no open PR, removed only obsolete generated main caches 8334618481, 8334308289, 8194857359 (old dependency fingerprints from completed integrations). Retained current main caches 8430830705/8430563994; authoritative cache list now 2 caches/2,693,664,871 bytes, with room for necessary 0.5.5 PR/main caches below 10GiB. No cache/storage cap changed.

Independent sync review found latestNonNil could resurrect a missing, nonexpiring cloud balance across Macs. Fresh Claude snapshots now send an empty detail-array tombstone when cloud credits are absent; unavailable snapshot remains nil. Added Mac three-phase publication and mobile multi-device clearing/legacy-nil fixtures. Supplemental source-provided balance/expiration sentences retain existing generic-detail English wire copy; status/title tokens are localized on phone.

Independent ledger review found cross-page dedup missed settled unhydrated siblings in production working sets. Repair uses manifest-visible bounded same-thread traversal with the existing four-path hydration cap, persists reconciliation progress, holds completion/day proof until reconciliation, seeds canonical owned responses and rewrites duplicate aggregates atomically. Working-set regressions cover seven siblings, both orders, reopen, append, midnight pricing and bounded migration. Native parser hash e276c3013494692f; revision 8 retains predecessor af117122edc4c286. Independent scheduler review cleared burst/context/mode/publishing seams. Auth review caught and repaired duplicate CLI request User-Agent while retaining single legacy fallback; exact headers now asserted.

Final independent ledger review cleared bounded sibling reconciliation, durable aliases, earliest canonical timestamps, saved pricing, immediate-scan hydration and atomic aggregate rewrites at native hash a768c7abccb6e7ab. Auth/cookie/Muse, scheduler and mobile clearing/expiry source reviews have no unresolved actionable findings; exact-head hosted runtime checks remain mandatory.

Muse TS/JS regeneration used documented bundled Sucrase 3.35.1 and upstream-pinned Oxfmt 0.67.0/config (verified binary SHA-256 2c0a483844922828a8b9b78684cb01e9283242250cad5d7303eb2cce0e027175). Reviewed output preserves QuotaKit headers and native snapshot limits; root/widget dependency originHash values remain fork-owned. LongCat source/tests remain supported and unchanged.

First hosted CI identified an upstream cookie-policy API assumption that did not compile against QuotaKit and reported formatting. Adapted the nonpersistent success marker to the native usesCookieJar discriminator (manifest parsing restricts those policies to nonpersistent request-url jars), retaining post-success/cancellation ordering. Applied only reported formatting edits with pinned SwiftFormat 0.63.0; native parser hash regenerated to dbdf016da4c53269. Validation remains hosted.

Hosted CI 37193430933 passed Linux x86/ARM CLI builds and portable tests and iOS simulator tests. Logs explicitly confirm the new cached-expiry and clearing/legacy-nil cases. Remaining feedback: restore upstream generic refresh-helper dependency, resolve strict SwiftLint layout/length with semantic-preserving helper/test splits. Independent review cleared those changes; final native parser hash e276c3013494692f. Earlier-head results are not substituted for final-head gates.
