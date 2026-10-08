# Codex weekly boundary recovery

Status: done - published Mac repair verified

## Incident and evidence

On 2026-10-07, the installed Mac app held a same-account exact OAuth weekly reading at 1%, captured at 11:58:26Z, with a reset at 2026-10-14 11:06:24Z. The installed OAuth helper and Codex desktop both returned 11%, resetting at 2026-10-14 03:38:58Z. An automatic app refresh logged `preservePrevious` and `noCandidateChange` for that successful fresh fetch. The provider fetch worked; weekly publication rejected a boundary that moved earlier by 26,846 seconds.

The existing delayed reset path only accepts high-to-low reset observations. It could never recover this rising-usage correction. The generic backward-boundary guard protects real stale pre-reset responses and must remain intact.

## Decision

Add a separate, account-owned weekly boundary correction admission around the existing reset policy. It requires a known matching account and normalized plan, exact OAuth confidence/source, valid future boundaries, nondecreasing weekly usage, and two newer observations with equivalent corrected boundaries, separated by at least 60 seconds and at most 30 minutes. The first observation retains the accepted snapshot and its original capture time. Conflicting, malformed, expired, changed-owner/plan/source, and canceled observations cannot publish the candidate.

Persist the correction candidate and retired future boundaries with the existing account snapshot file. The file already requires matching normalized email and workspace identity. Keep the cache format backward compatible with optional fields, and preserve the evidence in credit refresh, network-error, reconciliation, and single/multi-account paths. Retire the replaced future boundary on accepted corrections and ordinary confirmed cycle advances. Reject known retired boundaries before ordinary admission, including a later retired boundary replayed after a backward correction. Prune retired boundaries after they expire.

A correction adopts the corrected boundary in the reset detector without emitting a reset or notification. Preserve notification receipts, clear pending reset observations, and allow the next genuine reset to be detected exactly once. Existing early rolling-window suppression remains a separate mechanism.

Commit a pending detector-normalization snapshot with the accepted correction. Consume it for the matching owner after publication and before further fetches, including inactive accounts and ordinary restart. Detector preferences use the existing best-effort UserDefaults persistence; the separate marker clear has no durable-write acknowledgement, so an absolute abrupt-crash or power-loss guarantee is outside this repair's verified contract.

Show a scoped publication-hold message while retaining the last accepted reading and capture time. Preserve real transport/authentication errors separately; successful connectivity does not imply quota publication.

## Limits

OAuth `updatedAt` is a local receipt time. The upstream response contains no cycle identifier, generation, or server freshness marker. Delayed stable observations are a guarded recovery heuristic, not proof of server freshness. Existing caches cannot reconstruct all previously accepted cycles. Known retired-cycle replay is rejected deterministically; an unknown historical response with a still-future boundary cannot be distinguished conclusively from a real correction with the current provider contract. Do not invent a server timestamp, clear credentials, or weaken the generic reset policy to conceal that limitation.

## Verification gate

- Pure policy: exact incident, time/identity/plan/source/confidence/usage guards, fixed candidate lifetime, boundary conflicts and retired earlier/later replay.
- Publication integration: persisted candidate across relaunch, corrected/rising usage publication, repeated retired-cycle replay, multi-account and credit preservation.
- Reset detector: correction emits nothing; next genuine reset emits once with receipt deduplication intact.
- Existing focused reset, account ownership, missing-window and persistence tests; repository lint; signed release app build.
- Installed app: corrected quota/boundary, restart, continued automatic refreshes and widget/account cache readback. Verify native UI when the Mac is unlocked.

No iOS build-number change, mobile archive, public tag, appcast, or release publication is part of this local repair endpoint.

## Verified result (2026-10-07)

- Final focused Swift test run: 210 tests across five suites passed, using `Scripts/test_environment.sh`. Full local package/iOS test suites were intentionally omitted; the changed provider, persistence, account refresh and reset detector paths were covered.
- Repository lint passed with zero violations. Independent review: MERGE WITH NITS; accepted atomic-publication, threshold, plan-scope, inactive-account and exact-tolerance findings were fixed and verified. The best-effort detector durability caveat above remains.
- Signed local Mac build 0.32.4.34 / 79.34.1.11.4 passed deep/strict signature and isolated Helpers/resource/app launch checks. Installed binary matches the packaged binary. App group, team and CloudKit container match the prior signed installation.
- A stale Xcode SweetCookieKit checkout initially blocked widget packaging. Preserved that project-local cache, resolved the existing exact dependency pins into a fresh project-local checkout, and successfully rebuilt; no dependency versions changed.
- Installed app saved the correction candidate at 22:14:49Z. Restarted it after the confirmation delay. It published 12% at 22:16:13Z, matching the live Codex account and corrected reset at 2026-10-14 03:38:58Z. The previous 11:06:24Z boundary is retired. Candidate, hold and detector-normalization marker cleared; saved credits remained present.
- Subsequent automatic account/widget updates advanced to 22:18:14Z and 22:20:14Z, retaining the corrected boundary and fresh 12% reading. No live reset events appeared during correction.
- Native UI inspection was unavailable because the Mac remained locked. Widget and account cache readback establish the published data, not a visual screenshot.
- At the end of the local repair phase, changes remained on `agent/codex-quota-boundary-recovery`; no public release, commit, push, appcast change or iOS upload had been performed. The signed prior installation is retained locally in `.build/codex-boundary-rollback/QuotaKit.app`.

## Public delivery follow-up (2026-10-07 local)

- Shipped [QuotaKit Mac 0.32.4.34](https://github.com/ColumbusLabs/QuotaKit/releases/tag/v0.32.4.34), build 79.34.1.11.4, from source `a9487df576d62832e62eccd4256b4c27600d2af2`. The functional repair is in `6e1f573f7`; the following commit updates exact provider-architecture audit anchors and scoped fingerprints without changing runtime source. All 38 focused architecture tests passed, with independent review verdict MERGE.
- [Exact-source CI](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37703477224) passed all required jobs, including four Mac test shards, both Linux CLI builds and Xcode 26.3 compatibility. The initial functional commit also passed the iOS gate; the fixture-only follow-up correctly skipped it.
- Universal app and DMG notarizations were accepted with zero issues and stapled. All three uploaded asset SHA-256 digests match the local release artifacts; Intel and Apple Silicon debug-symbol UUIDs match their binaries. Public ZIP signing and the downloaded DMG's signature, ticket, Gatekeeper assessment, version and binary were verified.
- [Published-artifact CI](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37709301742) downloaded the public ZIP, checked its embedded profile, passed Gatekeeper and stapler validation, and launched it successfully on a clean runner.
- The canonical public Sparkle feed advertises stable 0.32.4.34 without phased rollout. A signed 0.32.4.33 workspace copy downloaded, validated and installed the exact 0.32.4.34 release through Sparkle. The resulting bundle passes strict signing, stapler and Gatekeeper checks and matches the installed public binary.
- [The production Mac page](https://columbus-labs.com/quotakit/mac) shows 0.32.4.34 and the exact public DMG and release-notes links; all URLs return HTTP 200. The site deployment is READY for site commit `ab4fc67d0e76764e11a262861e5812cfd62c29be`. The repository's fallback download page also points to this release.
- `/Applications/QuotaKit.app` runs the notarized public build. Fresh account and widget snapshots continued through 2026-10-08 00:45:24Z at 13%, retaining the corrected boundary, retired old boundary and saved credits, with no pending correction or publication hold. This is published-data and process verification; the locked Mac still prevented visual UI inspection.
- The fix and site task branches were deleted after main integration. Release artifacts and rollback state remain in ignored project-local evidence directories. Mac metadata advances to 0.32.4.35 / 79.35 Unreleased for the next development cycle; the shipped app remains 0.32.4.34. No mobile build numbers or distribution state changed in this Mac delivery.
