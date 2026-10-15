# QuotaKit upstream integration — 2026-10-15

Frozen reviewed range: `052ded4136dd3e2daa39edb59d33236fcb9c6be6..a49c61c30bb829c89460a95294fc09c5dab22221`.
QuotaKit source base: `60323daa2ef439ec1e8efd80afd2736d19747370`.
Tracking issue: [#246](https://github.com/ColumbusLabs/QuotaKit/issues/246).

All nine commits are linear, with no merge wrappers or independent merge resolutions. All nine product intents are adopted or adapted; no applicable work is deferred. Selected source patches and native adaptations are used, with no wholesale upstream merge.

| Commit | Classification | Product intent and fork adaptation |
| --- | --- | --- |
| `46fc250d0` | Adapted with `21dc8b664` | Preserve requested OAuth-profile email through verified-account and snapshot paths. The later display-profile cache completes ordinary refresh behavior; retain strict account ownership for history. |
| `278e9056e` | Adopted/adapted | Release plugin worker temporaries within autorelease pools and drain retired QuickJS runtimes; preserve bounded cancellation and worker ownership. |
| `cf828de7a` | Adapted | Fetch CLI providers concurrently while preserving selected-provider order, coherent output, token-account selection and QuotaKit CLI naming. |
| `9d3480006` | Adapted | Add default-disabled Claude Platform prepaid API credits across the Mac catalog, CLI, widgets and compatible mobile billing projection. Existing provider IDs remain intact; real API/purchased credit-grant lanes retain upstream usage behavior and widget selection, with actual snapshot data gating eligibility, while the zero-limit wallet never becomes an artificial budget or quota window. |
| `02834172b` | Adapted | Add Settings → About acknowledgements, pinned dependency notices, offline lint checks and plaintext CLI archive notices with QuotaKit branding. QuotaKit dependency revisions exactly match the upstream notice inventory. |
| `9ebd90017` | Adapted | Import Factory sessions across supported Firefox release channels while preserving scoped browser traversal and consent policies. |
| `02e909685` | Adapted | Add optional large menu text and monospaced digits, preserving QuotaKit graphical-bar layouts and backward-compatible persistence. |
| `21dc8b664` | Adapted, completes `46fc250d0` | Display the OAuth account email on ordinary refreshes through a bounded display-profile lookup/cache; preserve history/organization verification and no-UI credential paths. |
| `a49c61c30` | Adapted | Earn Muse credential access during an explicit manual refresh with the correct provider-specific prompt; background probes remain noninteractive. |

## Hunk exclusions and dependency accounting

- Upstream CHANGELOG release entries and release/site marketing are replaced by QuotaKit-native unreleased notes; no upstream version, build number, release date, tag, appcast, signing, entitlement, bundle or distribution ownership is imported.
- `Integrations/Linux/package.py` and its tests are absent from QuotaKit. Their Linux desktop packaging hunks in `02834172b` are inapplicable; the retained QuotaKit CLI archive receives the same notices.
- `Scripts/test_packaged_app_launch.py` is absent from QuotaKit. Its menu-label assertion changes in `02e909685` are inapplicable to that absent upstream harness; existing Swift state/renderer tests cover the adopted behavior.
- Upstream docs site/social generated assets are not imported wholesale. Product and provider documentation uses QuotaKit ownership, existing generators and native provider counts.
- Generated manifests follow `Scripts/regenerate-provider-manifests.sh`; aliases and provider documents remain repository-owned. Mac translations merge only changed keys across all 23 supported locales. License texts remain verbatim third-party notices.
- There are no new dependency versions, cache schemas, release numbers, permission identities, CloudKit schemas or persisted-provider renames. Existing `UPSTREAM_VERSION=v0.69.0` and `UPSTREAM_SYNC_DATE=2026-10-05` remain release provenance.

## Verification plan and authority boundary

Use source inspection, `git diff --check`, repository-owned generation, independent adversarial reviews and exact-head hosted CI. No local Swift/Xcode automated builds/tests/lint suites, simulator/device tests, app packaging, installation, relaunch, real credentials, live account/cookie probes, Keychain UI or CloudKit writes are required or permitted for this batch.

CI cost audit: repository PUBLIC; all four tracked workflows inspected, with standard GitHub-hosted macOS/Ubuntu runners and explicit standard matrix labels, no larger/self-hosted/reusable runners. Ordinary PR/main CI uses restore-only pinned caches with no cache saves or artifact uploads. Existing cache inventory is 9,839,485,195 bytes, below the included 10 GiB allowance; no storage settings are changed. Release workflows are not dispatched. GitHub also lists a historical bounded-diagnostic workflow absent from current main; its pinned historical source triggers only `agent/upstream-bounded-diagnostic`, not this integration branch or main, and uses a standard runner with restore-only caches. [Current GitHub billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions) confirm public standard-runner execution is free and larger runners are billable. Recheck before workflow-triggering actions.

Status: all nine product intents implemented and source-reviewed; exact-head hosted qualification pending. All 103 prior provider IDs and their order are retained, with Claude Platform appended as provider 104. Independent GPT-6 source reviews cleared acknowledgements, menu/CLI/runtime/browser and credential/shared-mobile paths after correcting the fork status-link argument, exhaustive provider switches, and signed/non-USD wallet projection. The wallet preserves zero, signed and validated currency amounts through the existing status wire, with no artificial budget.

Architecture snapshots preserve all existing fingerprints except the explicitly extended provider constructs. Sixteen unchanged source anchors were mechanically reanchored with exact old/new source equality; new literal catalog/identity/cost/wallet references are explicitly fingerprinted and justified. The static generator diffs add exactly one provider/alias/CLI icon. Site cards now cover all 104 registered IDs, filling the prior fal/FLORA/Parallel documentation gap alongside the new Claude Platform card; translated mobile release notes cover all 23 locales. Exact-head CI and merge receipts belong in the tracking issue to avoid embedding mutable workflow state in source.

The candidate monitor cursor advances to `a49c61c30` only with this integration PR; its effective main-branch advancement is contingent on exact-head hosted qualification and merge. No eligible work is hidden behind a cursor-only change.


Initial hosted qualification identified and repaired three fixture/formatting defects: one redundant `throws`, the Linux assumption that ordinary refreshes never fetch display profiles, and a mobile catalog-tail offset after appending Claude Platform. The Linux fixture now isolates its cache, gates only the synthetic profile timer, keeps independent real watchdogs, and asserts exact display-only versus verified identity behavior; production timeouts and suite deadlines are unchanged. Independent follow-up source review cleared timing and cleanup. A separate initial iOS UI test failed at app launch while XCUITest acquired a background assertion, before any UI assertion. Its cause is unproven; it must pass fresh hosted verification on the repaired head and is not waived or classified healthy.

The next hosted lint pass cleared formatting and exposed the expanded sync test type's existing 800-line limit. The Claude Platform sync test moves unchanged into its own discovered, main-actor serialized suite; no assertion, lint limit or test gate is weakened.

Hosted macOS test compilation then identified one unique access-control error in the CLI writeback regression fixture. Its Core import is now `@testable`, matching the internal credential-writer test hook without changing production visibility or credential behavior. This was a compile failure before discovery, not a timeout or an inventory pass; fresh exact-head qualification is required.

The full Mac run identified four additional fixture expectations: both provider-order snapshots need the append-only 104th ID; the color registry needs an explicit Claude/Claude Platform shared-brand pair, with positive equality and the global separation threshold retained; the Mac-side quota catalog contract must match iOS's 77 providers and 231 stable zones; and the new plugin fixture must supply scoped cookie records for the request-URL cookie jar. Independent adversarial review verified that production manual headers synthesize these records, browser imports preserve their scope metadata, and guarded requests/redirects select cookies from the same origin-validated jar. Only fixtures change; production cookie isolation remains intact. Plugin paths, minor-unit amounts, UTC expiries, organization fallback, retry and cancellation expectations also received a source walkthrough before fresh hosted qualification.

One combined menu-test group exhausted its shared 120-second budget without an assertion or crash. All four isolated selections passed (11.914s, 2.940s, 4.141s and 97.900s); the Swift helper had only 113.135s remaining after XCTest overhead. Independent source/timing review favors a combined budget overrun, while isolated passes cannot rule out ordering interactions. The affected test sources and default regular/non-monospaced typography are unchanged. Keep deadlines and gates intact and require fresh final-head qualification.

The subsequent hosted run passed both plugin engines (147 tests each), the full affected menu group together, Linux, iOS and compatibility gates. It exposed an unordered JSON-byte comparison in the reset-visibility migration fixture; a sorted-key encoder now preserves the complete identity equality assertion without depending on dictionary serialization order. A separate sync-group timeout recovered in isolation, but independent source review found a concrete lost-wakeup/publication race in its pre-existing mock. The mock handshake is repaired atomically with regression coverage for both arrival orders; production sync behavior and the original four-suite group/deadline stay intact. Fresh hosted qualification must cover the combined schedule.

One strict cached-title benchmark also measured 61.182ms thread CPU against its unchanged 50ms limit. The same renderer and test passed on the preceding head (88ms total across three batches), establishing variability without proving a specific cause. Object-identity caching assertions passed. No threshold, retry policy or production renderer changes are made; the final source head must pass the original performance gate.
