# QuotaKit upstream integration — 2026-10-06

Pinned upstream range: `14567f0b6711ef38741cadd7ff20ef76a2053af2..6a26b2e9b1b60471970deb6fe663f9e5f284e2ce` (20 DAG commits: 7 nonmerge, 13 merge). This branch begins at origin/main `42ad9e9e5df9ee430530e48f9142de0277fbf06a`.

All commits, parent dependencies, final net source changes and merge remerge diffs inspected. Classification totals: 6 adapted, 10 rejected, 1 superseded, 3 empty merge wrappers. No applicable deferrals. Upstream release notes and historical screenshots are excluded; native QuotaKit behavior and fixtures are included.

## Product and fork contracts

- CLI `config set-source` validates provider aliases and supported modes before config access; saves through the existing QuotaKit configuration store, preserves enablement, credentials and opaque provider fields, and clears overrides for `auto`. Complete provider descriptors remain authoritative.
- Usage & Spend exposes the existing pinned reporting time zone, including stored aliases/fixed offsets and a current-Mac-zone action. Existing settings revision, cache rebucketing, persistence and reporting semantics remain authoritative. Localization and state/model regressions accompany the view.
- The ownership test releases success/failure/timeout/cancellation only after its detached child is observable. Existing QuotaKit process-identity and unmarked-process regressions remain intact; production teardown source is unchanged.
- No provider IDs/manifests, shared wire formats, CloudKit records, widgets, entitlements, bundles, signing, updater/appcast or release/build inputs change. Only the reviewed monitor cursor advances; shipping `UPSTREAM_VERSION=v0.69.0` remains unchanged.

## Verification and CI cost boundary

Source/diff inspection and `git diff --check` locally. No local Swift/Xcode execution, live credentials, Keychain reads, browser cookie imports, accounts, CloudKit writes, app installation or distribution. Hosted CI verifies lint/builds/tests on the final reviewed head; Independent GPT-6.1 adversarial source review found an upstream-only Commander options type and grouped-option parser mismatch; both were adapted to the existing direct QuotaKit option declarations before CI. Final source review verdict: MERGE pending exact-head hosted CI, no unresolved findings. Existing regressions include SyncDayEvidenceReconciliationTests new-calendar scope and Mac publication/retry revision guards. First hosted cycle 37440699083 found two fixture compilation mismatches: upstream-only TestBuildProducts and different testSettingsStore argument order. The tests now use QuotaKit’s existing executable path convention and helper signature; assertions and production behavior remain unchanged. A new final reviewed head requires fresh hosted qualification.

Live repository visibility is PUBLIC. All workflow definitions and resolved runner matrices must be audited before triggering CI; standard public runners are free under [GitHub billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions), larger runners are prohibited. Live cost audit: public visibility; standard runners only; GitHub Free billing shows Actions storage 0.1/0.5 GB, $0 billable Actions, and account Actions/Packages budgets $0 with Stop usage Yes. Caches total 8,224,895,390 bytes and live repository UI caps them at 10 GB with LRU eviction. Historical artifacts are left intact. Unchanged dependency keys avoid new cache churn; iOS path gate skips because no mobile/shared contract source changes, so this batch triggers no artifact uploads. No paid settings or limits are changed. Applicable hosted gates are lint, four macOS shards, Xcode compatibility, Linux x86/ARM and the aggregate. Existing Mac shared scope regressions cover changed reporting calendars; no new mobile wire/identifier behavior is introduced.

## Complete range ledger

| Commit | Classification | Subject | Evidence |
| --- | --- | --- | --- |
| `91f8bf54f09d78f16a4098f149f0f0d992fd03b1` | Adapted | Add statistics time zone controls to Usage & Spend | Final statistics time-zone controls, pinned alias labels, fixtures and 23 Mac language catalogs. |
| `0ce3e0caa16d115b18636e0b808e97df0565d743` | Adapted | Preserve saved time zone labels in picker | Final statistics time-zone controls, pinned alias labels, fixtures and 23 Mac language catalogs. |
| `7916c6e7d9eb1ca82971af64bab8f92cb089f692` | Superseded | Support isolated native statistics time zone proof | Temporary debug native-proof app hook deliberately removed by 2dd0a363d; no final product delta. |
| `40646dda7a6a6407a8e77adf8c0c6235d00f2f8b` | Rejected | Record native statistics time zone interaction proof | Upstream historical native screenshots/logs and validation receipts removed by 2dd0a363d; not QuotaKit verification or product source. |
| `620f3a0860db05c739aed44777c82ef0916fbbad` | Rejected | Record rebased full suite validation | Upstream historical native screenshots/logs and validation receipts removed by 2dd0a363d; not QuotaKit verification or product source. |
| `e916f6930eab207cae8194118577940c6df6610d` | Adapted | Add CLI command to persist provider source | Persistent source selection using QuotaKit config paths, branding, pinned Commander direct common option declarations and complete provider descriptors. |
| `2dd0a363dcf6dac33726877d18cdac90433c49f8` | Adapted | feat(spend): expose pinned statistics time zones | Substantive merge finalization: localization coverage and saved labels; removes debug proof hook and historical artifacts. |
| `d698f230c484b7fb9834abb50e6cd79675f45c3a` | Adapted | feat(cli): persist provider source overrides | Substantive merge finalization: final CLI round-trip, invalid-argument and secret-safe fixture coverage; release note omitted. |
| `c0e334ecc6b1b6f9dd76107998ea23170baf7278` | Rejected | chore: merge main and reconcile changelog | Remerge diff only reconciles upstream CHANGELOG release bookkeeping; QuotaKit-native notes recorded separately. |
| `1133d6f316d2111c21dd4aa2a167003022034b8b` | Rejected | Merge remote-tracking branch 'origin/main' into pr-4185 | Remerge diff only reconciles upstream CHANGELOG release bookkeeping; QuotaKit-native notes recorded separately. |
| `959f8551e2700860b610765b0021b3efa6c96dc5` | Rejected | Merge remote-tracking branch 'origin/main' into pr-4185 | Remerge diff only reconciles upstream CHANGELOG release bookkeeping; QuotaKit-native notes recorded separately. |
| `bbe18fe257b3827ee1e35180f971b7a1b62c78af` | Rejected | Merge remote-tracking branch 'origin/main' into pr-4197 | Remerge diff only reconciles upstream CHANGELOG release bookkeeping; QuotaKit-native notes recorded separately. |
| `0836fed92b12f4dba142df5ce694c3ec9eaa0999` | Merge wrapper | Merge remote-tracking branch 'origin/main' into pr-4185 | Empty remerge delta; constituent source commits and finalizations accounted separately. |
| `3190aeff6ad788ecd7fda4027ff4d84c17c405ed` | Rejected | Merge main and retain CLI source release note | Remerge diff only reconciles upstream CHANGELOG release bookkeeping; QuotaKit-native notes recorded separately. |
| `74720491b22331e7ab6c4c336cac46189dba1bd0` | Rejected | Merge main and retain both CLI and Langdock release notes | Remerge diff only reconciles upstream CHANGELOG release bookkeeping; QuotaKit-native notes recorded separately. |
| `c967d07817362c3ceb1c55fc2185ed2ef5494f5c` | Adapted | test: make the process-ownership reaper probe deterministic (#4272) | Completion barriers and bounded joins in existing ownership fixture; fork-specific unmarked-group tests retained. |
| `9d8b05dd5a18fbf8178580c455bda83e83d9b1e3` | Rejected | Merge remote-tracking branch 'origin/main' into HEAD | Remerge diff only reconciles upstream CHANGELOG release bookkeeping; QuotaKit-native notes recorded separately. |
| `81b904ade183a1c992c4f376e641567b975be5fa` | Merge wrapper | Merge #4185: Add statistics time zone controls to Usage & Spend | Empty remerge delta; constituent source commits and finalizations accounted separately. |
| `d92ddd34907a011905c5b47310f347985413b61f` | Rejected | Merge remote-tracking branch 'origin/main' into HEAD | Remerge diff only reconciles upstream CHANGELOG release bookkeeping; QuotaKit-native notes recorded separately. |
| `6a26b2e9b1b60471970deb6fe663f9e5f284e2ce` | Merge wrapper | Merge #4197: Add CLI config set-source command | Empty remerge delta; constituent source commits and finalizations accounted separately. |
