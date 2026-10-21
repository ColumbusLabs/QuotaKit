# Upstream integration — 2026-10-21

Frozen upstream range: `e59282ece537cda5594ebf4bd233d4b9a10cfffd..489aad74fbd55a22db570c025b6d57aac654cd5a`.
QuotaKit base: `6b37316b08155c0874ad35e76cb2236604908517` (`origin/main` at discovery).
Tracking: [issue #256](https://github.com/ColumbusLabs/QuotaKit/issues/256).

All ten reachable commits are linear; there are no merge wrappers or superseded intermediate commits. Four product slices are adapted, six commits are rejected for the specific reasons below, and no applicable slice is deferred. Product-generated files are limited to coherent dependency pins and their acknowledgement; upstream release files are excluded.

| Upstream commit | Decision | Intent and QuotaKit treatment |
| --- | --- | --- |
| `9c16d285ff8f6a4078bbaef35de50585a2b6e92f` | adapted | Stream origin-filtered Devin Local Storage using SweetCookieKit 0.5.9; update both dependency pins and acknowledgement while retaining QuotaKit importer safeguards and fixture-only validation. |
| `a13a0657ebb889b091278657975f23c8d28bd698` | rejected | Link an external CodexBar Linux desktop integration in upstream README. QuotaKit has no Linux desktop integration or `Integrations/` tree; its supported Linux CLI is unaffected. |
| `50dea10862dae32290621e5dc7d66158fe8b2fab` | rejected | Linux/Omarchy desktop installer XDG defaults and QML fixture fixes. Those installer, desktop preference and QML surfaces do not exist in QuotaKit; no corresponding CLI path requires migration. |
| `389d287a28486b6e4927109268527e60ab74dbe8` | adapted | Prefer measured ordinary Gemini quotas using stable Antigravity bucket identities, retaining model-specific rows, reset metadata and fallback behavior. Linux desktop JS subhunks target the absent integration. Preserve fork stable equal-rank ordering and existing shared/mobile projection. |
| `43278dd9465fe6c1b9fd5868f122e8efcc09b520` | adapted | Reuse immutable Claude incremental-cache file records and reserve dictionaries to reduce refresh memory, preserving QuotaKit cache version, source ownership, fragment validation and atomic persistence. |
| `2cac1498be8e5590d3a3e12b7a81e5acb6c3f465` | adapted | Recover verified stale widget extensions after app updates, with QuotaKit bundle/signing identity and fixture-only process seams. Adopt coherent process enumeration and snapshot-copy simplifications while preserving wire fields, App Group and Mac/iPhone contracts. |
| `b49d42eb53bbf79785b344492d594760dd163eac` | rejected | Upstream 0.79.0 release preparation, dates, release notes and version metadata belong to Pete's release lane. QuotaKit product changes receive native wording in the existing unreleased block. |
| `ba799f09dfdea898469c10ac974b9daa93e5958d` | rejected | Published upstream appcast and signed artifact entry. QuotaKit appcast and release ownership remain unchanged. |
| `9093308f0b79645f6794c2f28f020d87fe06386b` | rejected | Upstream 0.79.1 development version, build number and changelog scaffolding. Ordinary integration is version/build neutral. |
| `489aad74fbd55a22db570c025b6d57aac654cd5a` | rejected | Linux desktop autostart preference parsing on reinstall; QuotaKit has no corresponding desktop installer or autostart file. Mac login-item ownership and Linux CLI behavior are separate existing contracts. |

## Fork contracts and verification

Preserve the complete 106-provider registry and generated manifests; QuotaKit/Columbus Labs identity, config and Application Support paths; mobile/shared schema, CloudKit records, App Group, notifications, StoreKit and recovery safeguards. Preserve all marketing/build/mobile versions, `UPSTREAM_VERSION=v0.69.0` and `UPSTREAM_SYNC_DATE=2026-10-05`. Only the reviewed monitor cursor advances with the qualified integration. No appcast, release, entitlement, signing or distribution changes.

Credential import, persistent-cache and process termination changes require independent adversarial source review. Require all applicable hosted lint/build/test checks on the exact final reviewed head, including iOS where the existing shared/widget dependency gate applies. Local work is limited to source review, cheap static/diff checks, documented generation and pinned formatting. No local Swift/Xcode suites, live accounts, credentials, browser cookies, Keychain UI, CloudKit writes, installation, packaging or relaunch.

## Free hosted Actions audit

Live repository visibility was PUBLIC at discovery. All four workflow sources were inspected at the pinned origin base: topic pushes trigger none, PR open/synchronize and the eventual main merge trigger CI only. CI uses standard `macos-26`, `macos-15`, `ubuntu-24.04` and `ubuntu-24.04-arm` runners, with no reusable/self-hosted/larger runner jobs. Cache access is restore-only, with no artifact upload or cache save. Existing cache usage was 2,762,350,951 bytes, below the included 10 GiB. The scheduled/manual monitor and manual/tag/release workflows are not dispatched by this integration. No billing, budget, payment, storage-cap or stop-control settings are changed.

GitHub's current [Actions billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions) confirm standard hosted runner execution is free for public repositories; larger runners remain billable and prohibited. Recheck live eligibility and workflow sources before workflow-triggering mutations.

The primary checkout remains clean but divergent at user commit `9b903981e298d7877437b8ec1ed8e34ae71e2bc1`, ahead one and behind fifty at discovery. Work uses an isolated origin-based checkout; do not reset, rebase or merge the unrelated user commit. Qualification, exact merge/tree readback, cursor/tail and cleanup evidence will be recorded on issue #256 after hosted proof.

## Adaptation details

Widget recovery discovers the single bundled extension by `<app identifier>.widget` rather than importing upstream's hardcoded extension filename. This preserves both QuotaKit release and debug identifiers and the existing `QuotaKitWidget` product. The production signal closure uses the same pure revalidation seam covered by synthetic PID-reuse and changed-signature tests. Tests exercise recovery decisions without launching or terminating an app or accessing signing state.

Claude immutable-record reuse retains the fork's artifact type, schema 3, v18 cache paths, exact-byte identity comparison, content generation observers, fragment stamps and atomic write ownership. The new regression proves unchanged usage and identity-only records retain reference identity while changed files receive new immutable records. Devin's structured origin-scoped reader replaces the broad text fallback; fixtures cover current-session replacement and unrelated origins without reading real browser data.

Antigravity retains stable source ordering for equal-rank groups/buckets. A Mac-to-iPhone projection regression asserts ordinary Gemini usage near 0.04%, the existing family labels, and retained model-specific quotas. No shared schema or mobile projection changes are needed. The existing iOS 1.11.4 release-notes block receives one note translated in all 23 locales; no new release block or build increment.

The architecture catalog updates only exact anchors and line positions: 131 suppressions and 404 allowed constructs remain unique and exact; scanner/enforcement logic is unchanged. Independent source review corrected an NSLock closure signature and a duplicate test attribute before hosted qualification. Root review also removed an unused fixture value and replaced exact floating-point comparisons with bounded numeric assertions.
