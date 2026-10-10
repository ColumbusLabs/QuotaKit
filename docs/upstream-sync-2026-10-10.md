# CodexBar upstream integration — 2026-10-10

Reviewed upstream: `steipete/CodexBar`, base
`81438267f` through `6e118bdb5782707bfb0dfd0453d3483e3b216cd0`.
The exact DAG contains **66 commits: 39 non-merge commits and 27 merge commits**.
The ledger includes side-branch commits and maintainer merge resolutions, not only
the first-parent log. Integration uses the final coherent behavior of each slice
and QuotaKit adaptations rather than merging the upstream branch wholesale.

Source classifications below account for the reviewed range. They do not assert
that hosted checks have passed or the PR has merged. Exact-head verification and
closeout evidence must be recorded separately before advancing the reviewed cursor.
`UPSTREAM_VERSION` is release/provenance metadata and remains separate from
`UPSTREAM_MONITOR_BASE`.

## Integration decisions

All useful provider and Mac product behavior is eligible. This range does not add
or remove provider identifiers. Langdock browser selection, Ollama balance data,
Claude external-login freshness, Cursor Linux authentication, menu behavior,
history caching, and account widgets are integrated in coherent slices. Existing
QuotaKit identity, release ownership, storage paths, provider manifests, shared
Mac/iPhone models, and signing/CloudKit/notification contracts remain the fork's
requirements.

Linux changes are eligible: this fork defines `CodexBarLinuxTests` in
`Package.swift`, builds the CLI and Linux tests on Ubuntu amd64 and arm64 in
`.github/workflows/ci.yml`, and documents standalone Linux CLI packages in
`docs/cli.md`. Linux-only behavior cannot be rejected as an unsupported platform.
The final heap change returns freed glibc pages only while `serve` runs; the early
global arena-setting experiment is deliberately superseded. Synthetic procfs and
serve-memory fixtures are retained with QuotaKit paths and configuration keys.
No live provider credentials, cookie imports, Keychain reads, or account probes
are needed to verify these changes.

The first hosted Linux run exposed two fixture assumptions. QuotaKit presents
Cursor's fixture as Auto 10% and API 20%, rather than using the 30% total plan
usage as its primary lane. Its process-local scan-store registry also retains
Codex scan state, so a cold-to-post-scan RSS threshold does not isolate freed
allocator pages. The repaired regression directly exercises the actual trim
callback against a controlled fragmented glibc heap. The real `serve` fixture
checks cost responses and health for 40 seconds across the unchanged 30-second
timer with 5-second leeway, recording RSS diagnostically. Source inspection
establishes retained cache objects; it does not quantify their contribution to
the original RSS failure. Both architectures must qualify the repaired head.

The CI cache chain is adapted to the fork's current cache lifecycle. The final
schema-3 helper verifies content, permissions, path inventories, and symlink
targets before restoring input timestamps; unverifiable inputs clean build
products. `Shared/` is added to package-input prefixes because QuotaKit's
`CodexBarSync` target has `path: "Shared"`. The existing dependency-keyed caches
remain; this integration creates no compiled-cache namespace, per-main-commit
cache saves, cache-pruning job, or additional cache uploads. Upstream's new
save-before-prune lifecycle would temporarily retain old and new compiled builds
alongside existing dependency caches. That extra storage is unnecessary for this
integration and is outside its zero-paid-usage and no-extra-cache-churn boundary.
The namespace-specific prune helper consequently has no applicable namespace to
manage here.
Because `Package.swift` and `Package.resolved` are unchanged, existing exact-key
cache hits should require no new saves. Old snapshots without schema-3 metadata
take the safe cold-product-clean path on each restore until a dependency key
naturally changes; dependency checkouts remain available. This is an intentional
safety/performance tradeoff, not evidence of compiled-cache reuse on this run.

QuotaKit's four required path-gated shards, complete discovered inventory,
120-second suite deadlines, zero retries for ordinary failures, group size four,
keep-going policy, and focused-path gates are retained. Each broad shard uses
two required direct workers; the redundant nonblocking smoke step is removed.
Upstream's three documented complete-inventory validations concern its Xcode
26.6 lane; QuotaKit currently selects Xcode 26.3/26.2 and has a larger suite.
They do not qualify this fork's full inventory. A bounded direct probe succeeded
on the last exact-main run `37949731571`; that confirms the capability seam, not
complete coverage. The final integration's exact-head hosted full shard union
must establish full compatibility, with helper failures and unrecovered timeouts
remaining gating. This adopts direct execution while preserving the fork's
suite-size and path-gate architecture rather than borrowing upstream test proof.

Langdock's profile registration also supplies CLI refresh capabilities and the
selected browser order. Static metadata no longer defines its browser support;
Chrome and Edge still require explicit prompt acknowledgement, Safari remains
prompt-free, and invalid selections fail closed. Regression fixtures cover
refresh discovery, selected/default browser order, and wrapped permission hints.

Direct-worker cleanup treats a denied signal-zero process-group probe as
inconclusive, retains the existing bounded grace and actual termination signals,
and preserves timeout exit 124 for isolated recovery. A real termination-signal
denial still fails the job. Synthetic regressions cover timeout accounting,
isolated recovery, zero assertion retries, and keep-going without weakening the
120-second deadline or inventory gates.

Ollama plugin JavaScript was generated from the upstream TypeScript with the
repository-bundled Sucrase 3.35.1; its generated diff was reviewed. Ordinary integration does not change
build numbers, upstream release version metadata, appcast entries, release
artifacts, signing inputs, or distribution state.

## Every non-merge commit

“Adapted” means its useful final intent is rebased into QuotaKit's architecture,
identity, documentation, or verification contract. “Superseded” names the later
upstream change that replaces an intermediate result. Product slices use final
upstream trees, including the resolutions listed below.

| Commit | Upstream intent | Classification and evidence |
| --- | --- | --- |
| `13ac539fa` | Clear stale sleeping Codex catch-up | Adapted with `1cb13dc14`; preserve stops, account coverage, and refresh races in `UsageStore` with cache/completion tests. |
| `691b79f50` | Cap glibc malloc arenas globally | Superseded by `407b528d8`, which removes global arena tuning and its entry-point call. |
| `2dc8acb96` | Idle heap return through arena helper | Superseded by `407b528d8`'s smaller serve-only timer; no global allocator policy remains. |
| `cb41b4424` | Linux heap changelog | Superseded by `407b528d8`'s corrected serve-only description; useful product intent gets QuotaKit wording. |
| `407b528d8` | Restrict heap maintenance to serve | Adapted final `CLIServeHeapTrimmer`, serve lifecycle, equivalent response-cache simplification, synthetic Linux memory fixture, and QuotaKit identity. |
| `71cf05049` | Avoid Foundation empty-procfs read leak | Adapted with `f62ccafdd`; plain `read(2)`, close on every exit, EINTR handling, UTF-8 failure behavior, and Linux regression coverage. |
| `5f0a69859` | Procfs changelog | Adapted as QuotaKit product documentation; maintainer wording finalized in `f62ccafdd`. |
| `b90560bf5` | Reuse hourly dates per spend group | Adapted final intent through `2a16d5c57`; eager indexing is superseded by synchronized on-demand memoization. |
| `0dfac40f8` | Prototype hourly performance receipts | Superseded by `2a16d5c57`, which replaces historical launcher/patch/receipt/measurement scaffolding with a current-checkout test-backed verifier. Historical upstream provenance is retained, not represented as QuotaKit runtime evidence. |
| `818f15017` | Avoid overlapping changelog insertion | Superseded by the final `1cb13dc14` catch-up entry and QuotaKit-native changelog placement; no standalone product behavior. |
| `e8c51e374` | Verify cached input timestamps | Adapted final schema-3 helper and fixture tests through `91052d34b`; no earlier unsafe timestamp-only state is imported. |
| `2e37d0633` | Reuse verified builds across checkouts | Adapted helper, tests, portable lint hook, and existing dependency-cache lifecycle. New compiled namespace/save/prune mechanics are inapplicable to the retained lifecycle and omitted to avoid extra cache churn. |
| `2f3448205` | Clean cached products on changed input graph | Adapted final helper clean-fallback behavior and regression tests. |
| `bc2b3dad6` | Cover all package target paths | Adapted final helper, including QuotaKit-specific `Shared/` target coverage. |
| `8b2db6e09` | Two direct workers on one runner | Adapted to two gating direct workers within each of QuotaKit's four path-gated shards, preserving full inventory union and fork deadlines/group size; redundant smoke removed. Exact-head fork CI must qualify compatibility. |
| `36278a21e` | Invalidate changed package symlinks | Adapted final schema-3 payload/type/target validation and tests, completed by `91052d34b`. |
| `3c02274fd` | Chrome/Safari Langdock profiles | Adapted browser/profile shared host behavior, settings compatibility, tests, and QuotaKit documentation; upstream-branded screenshot receipts are provenance, not fork UI proof. |
| `0ca134822` | Tall Claude CLI usage panel | Adapted final 160-column/200-row replay viewport with captured synthetic panel fixture; completed by `96bfd9a91`. |
| `d82f195bd` | Explain Claude renderer overflow | Adapted code comments and fixture documentation with final `96bfd9a91` behavior. |
| `f5d00aff8` | Browser refresh source compatibility | Adapted legacy registration adapters and CLI/browser compatibility tests; preserves existing selected-browser settings. |
| `60d850811` | Alternate lazy hourly date cache | Superseded by `175c385ac`, which explicitly keeps the smaller verified memo from `2a16d5c57` and removes duplicate cache/proof machinery. |
| `1cb13dc14` | Refresh during history completion check | Adapted final catch-up state/coverage/recheck behavior, cancellation/recovery tests, and source-backed architecture fingerprint. |
| `acddb8265` | Safari profile access denial | Adapted explicit denied-access classification and tests; no fallback to another profile or credential source. |
| `8103f13b6` | Direct test timeout recovery docs | Adapted accurate isolated timeout retry/deadline description; upstream and bounded probe results do not replace exact-head full fork qualification. |
| `28d165f9a` | Isolate menu dashboard caches in tests | Adopted final explicit isolated fixture seams; prevents tests from reading ambient dashboard state. |
| `29e735798` | Require dashboard cache fixtures | Adopted explicit test cache contract in `OpenAIDashboardModels` and CLI cache tests. |
| `fff36b31f` | Copy-on-write Claude artifact blocks | Adapted final writer/cache behavior through `d1ced8a49`; existing JSON schema, filenames, scope, atomic replacement, and full-write fallback retained. |
| `22372da3b` | Pace sign preference | Adapted persisted Mac setting, renderer/animation/historical pace wiring, localized UI, and tests with original default/color/rule behavior preserved. |
| `b91a4efd4` | glibc buffer unwrap and CLI proof | Adapted portable final writer buffer handling and synthetic proof support through `d1ced8a49`; no real account evidence is imported. |
| `b58d3b985` | Cursor-agent Linux login | Adapted final read-only agent store/fallback chain through `0b0652ad1`; Linux CLI is a supported fork surface. |
| `6def3621b` | Native wheel routing for overflow | Adapted final overflow/native-wheel logic through `238985d21` and stable menu state tests. |
| `0b0652ad1` | Complete Cursor Linux fallback | Adapted ordered desktop-then-agent auth, corrupt/missing/rejected-session fallback, cancellation/network error preservation, and fixture tests. Mac auth source ordering remains unchanged. |
| `238985d21` | Settle overflow before wheel routing | Adapted final menu geometry/scroll routing and regressions; finishes `6def3621b`. |
| `08f42ab06` | Ollama API-key credit balance | Adapted native provider setup and plugin/parser tests for monthly allowance/reset and purchased credit balance; manifests and mobile-consumed balance semantics preserved. |
| `44702dc72` | Claude external-login Refresh guidance | Adapted freshness observation and stale missing-credential presentation with passive no-secret/no-UI timing queries and regression tests. |
| `2b58ada62` | Multi-account quota overview widget | Adapted Mac snapshot/widget behavior with QuotaKit identity and shared/mobile compatibility coverage; snapshot cap/overflow and optional field compatibility preserved. |
| `68ee4fc45` | Prepare upstream 0.74.0 release | Rejected: changes only upstream `CHANGELOG.md` release headings/highlights and `version.env`; QuotaKit owns versions/build numbers and release bookkeeping. Useful product changes are already accounted for separately. |
| `c2f22ccf8` | Publish upstream 0.74.0 appcast | Rejected: changes only upstream `appcast.xml` release entries/artifact metadata; importing it would violate QuotaKit updater/release ownership. |
| `6e118bdb5` | Start upstream 0.74.1 | Rejected: changes only upstream development release heading and `version.env`; no source behavior to adopt. |

## Merge commits and resolutions

Every merge was inspected with `git show --remerge-diff`/the range's remerge log.
Ten merges contain content beyond the automatic parent merge. Those changes must
be accounted for explicitly; choosing only non-merge cherry-picks would miss
several final upstream fixes and test contracts.

| Merge | Classification and content beyond automatic merge |
| --- | --- |
| `f62ccafdd` | Adapted procfs completion: adds `Scripts/test_linux_procfs_reads.py` and Linux CI invocation, stronger chunk-boundary/invalid-UTF8/read-error/exited-process tests, and registry `current` call-site simplification. Changelog conflict resolves to final upstream product wording, rewritten for QuotaKit. |
| `96bfd9a91` | Adapted tall-panel completion: keeps credential/environment scrubbing equivalent while inlining its single caller; adds horizontal bounds/erases/plain-report coverage, preserves profile selection, and documents the shared viewport. |
| `2a16d5c57` | Adapted authoritative hourly redesign: lazy synchronized per-group memo, removes unused hourly-chart-domain/cache wrapper, covers actual chart domain, and replaces historical proof scaffolding with committed current-production tests and verifier. |
| `175c385ac` | Supersedes `60d850811`; explicitly retains the smaller already verified `2a16d5c57` memo and current verifier. Merge tree is unchanged from its first parent; duplicate helper/tests/headless proof are not part of final upstream. |
| `91052d34b` | Adapted critical cache finalization: schema 3; only tracked regular targets in both snapshots can permit symlink reuse; rejects external/untracked/chained/directory/noncanonical targets and tests clean-fallback errors. |
| `edfbedd1c` | Adapted documentation resolution only: chooses final hourly-navigation changelog wording and combines concurrent changelog additions; no extra runtime behavior. |
| `cf0e977b1` | Adapted Langdock final docs: keeps legacy `selectedProfileBrowser` source compatibility, uses new multi-browser registration, and finalizes attribution/changelog; upstream v0.73.0 release claim is provenance, not a QuotaKit version claim. |
| `de4aed2d4` | Superseded conflict-marker cleanup in upstream changelog only; final tall-panel intent is already represented by `96bfd9a91` and QuotaKit-native documentation. |
| `844b94376` | Superseded conflict-marker cleanup in upstream changelog only; final Langdock intent is represented by its source slice and QuotaKit-native documentation. |
| `d1ced8a49` | Adapted artifact finalization: writer byte-observation hook, symlink/occupied-temp regression, test-only recorder/isolation/eviction support moved into test target, synthetic clone-error/partial-write recovery proofs, atomic-not-power-loss-durable contract. |

The remaining **17 merges have empty remerge diffs**. They combine already
classified parents without distinct conflict-resolution behavior. Each is
accounted for by adoption/adaptation of its final coherent parent slice:

| Merge | Accounted parent slice |
| --- | --- |
| `9279dde84` | Linux heap/process cleanup ancestry; final serve-only `407b528d8` behavior. |
| `e772b9f3c` | Linux heap slice rebased onto pinned main. |
| `94fd089e0` | Linux serve heap PR #4374. |
| `83f0ca80b` | Procfs PR #4377 including `f62ccafdd` finalization. |
| `26673babf` | Tall Claude panel PR #4392 including `96bfd9a91`. |
| `1843f6152` | Catch-up slice rebased onto concurrent tall-panel/procfs main. |
| `c9c3e5541` | Codex history catch-up PR #4379. |
| `150c40451` | CI cache slice rebased onto current catch-up main. |
| `a4f65b4e4` | CI cache/direct-worker PR #4385, adapted to existing cache lifecycle and four required direct-worker shards. |
| `18aac8b34` | Hourly memo slice rebased onto concurrent CI main. |
| `d41e10296` | Hourly navigation PR #4380 including final memo/proof resolutions. |
| `e8013e28f` | Langdock browser profile PR #4390. |
| `418f0dcdd` | Cursor Linux agent auth PR #4397. |
| `7f7ade4b3` | Claude artifact slice rebased onto Cursor main. |
| `b8c6a1eb8` | Claude artifact copy-on-write PR #4396 including `d1ced8a49`. |
| `a36976224` | Overview wheel slice rebased onto artifact/Cursor main. |
| `cd24c380e` | Overview native wheel PR #4398 including final overflow settlement. |

## Verification and closeout requirements

Review the final fork diff against current `origin/main` and each final upstream
slice. Use cheap static checks locally; run applicable Mac, Linux amd64/arm64,
plugin, and shared/iOS verification in existing GitHub CI. Account/widget shared
contracts, credentials, and atomic artifact writes require independent adversarial
source review before merge. The hosted workflow must use only verified free
standard runners in the currently public repository, preserve existing storage
limits, and pass on the exact reviewed PR head.

No release publication, appcast mutation, signing/notarization, packaging,
installation, app relaunch, TestFlight upload, App Review submission, live account
probe, or CloudKit data mutation is authorized by source integration.

Merge/cursor/issue/cleanup evidence is pending until the integration is qualified
and merged. Do not interpret this ledger as a successful CI or distribution
receipt.

## Independent CI/cache source review

An independent read-only review checked every SwiftPM target path against the
helper prefixes, metadata/content/permission/symlink fallback handling, exact
inventory admission, worker home and credential isolation, deadlines, required
workflow gates, and cache/upload namespace changes. No new cache-save namespace,
cache-pruning permission, larger runner, or artifact upload is introduced.

The review found one integration regression: `CODEXBAR_TEST_KEEP_GOING=1` reached
the suite harness but was absent from its direct-worker manifest, so a failed
direct group stopped queued groups. The root fixed the manifest to carry
`args.keep_going` and made `run_pool` stop queued work only when that setting is
false. Source re-review confirms that failures still return nonzero while
keep-going executes remaining groups. The regression fixtures cover ordinary
failure `42` and timeout `124`, assert all three queued groups execute without
ordinary retries, and verify the ordered serial/direct shard manifests carry the
setting. This is independent source-review evidence; hosted exact-head CI remains
pending and is still required before merge.
