# Upstream backlog reconciliation — 2026-09-28

## Current status: complete locally verified candidate

[PR #216](https://github.com/ColumbusLabs/QuotaKit/pull/216) is verified merged as `7b6935bfdfd109fe4bfb49e7c1e1402f2ae303b2`. Its exact tested head passed [CI36701444039](https://github.com/ColumbusLabs/QuotaKit/actions/runs/36701444039), and the squash tree matches. **Actual merged accounting remains 860 accounted, 60 known gaps, 1 unresolved / 921 reviewed** until the next covering merge.

[PR #217](https://github.com/ColumbusLabs/QuotaKit/pull/217) combines Recovery20, all remaining 41 original-cut contracts, the nine-object fresh tail and the CI-discovered hydration/performance repairs. Locally verified source is `57c46c3d6dbe7e534169e592bd95fdf601b5d941` at tree `d62f426ecf5727b47d9617b7ac845df6950b8cd0`; it exactly matches the original tested source tree. **Candidate accounting is 930 accounted, zero missing applicable implementations and zero unresolved / 930 objects**. Required exact-head hosted CI and merge remain pending; candidate implementation evidence is not merged credit.

The original 875 rows retain their exact SHAs and first 12 historical fields. Existing tail rows 876–921 also retain those fields. Fresh rows 922–930 are appended to the same 16-column tail ledger. The 20 recovery and 41 final contracts update existing rows rather than adding rows. Explicit merge/release/exclusion decisions count as reviewed dispositions without inventing runtime implementations.

### Local verification

All 83 planned focused filters have latest passing completed evidence across affected-only runs. Additional account/plan reset-credit, native hooks, enabled OpenRouter widget and final optional-request fixtures pass. The last optional-request batch passed 37 tests in four suites with both JavaScriptCore and QuickJS parameter cases. The repaired history worker passes source recovery, physical-row read semantics and executor isolation; catch-up status stays within 512 identity visits and warm scans reuse the alias snapshot. All local product and test targets compile. Hosted Linux initially exposed an obsolete Crof fixture, replaced with two passing Core-only portable retirement compatibility tests; production source was unchanged. Both hosted Linux architectures now pass. Hosted iOS then exposed stale Crof/provider-count expectations in its push-subscription fixture; the test now asserts 71 active providers and 213 zones while retaining legacy Crof zone parsing. All 33 repaired provider-list tests pass in a private macOS SwiftPM harness using byte-identical shared sources; only the unused app-module import is removed. No production source changed for either fixture repair; hosted iOS and the complete repaired-head gate remain required.

Full lint gates pass: zero strict violations across 2,670 Swift files, formatting, 22 Mac localization catalogs, all 287 iOS localized source keys, generated parser/provider registries, package/release helpers, shell/docs/CI gates, customer branding and 87-provider palette. Independent static reviews cover cost data integrity, account/reset authority, cookie/session mutation and shared UI; final review deltas retain earlier resolved findings. See [Research057](../CodexBarMobile/Research/057-upstream-final-runtime-clearance.md).

The full local package suite was omitted; required hosted CI supplies the broader gate. No live provider/browser/Keychain/SSH probe, app installation/relaunch or product release ran. Hooks native proof verifies editable empty AX fields, prompts and unchanged bindings; offscreen SwiftUI hosting does not prove onscreen VoiceOver names. Product build numbers and shipped-upstream metadata remain unchanged.

### Hosted fixture repair checkpoint

The combined hosted matrix passed lint, both Linux architectures and the Xcode 26.3 compatibility build. All four Mac shards exposed stale retirement/provider-count, Grok decoration, account-label, source-anchor, revision-tombstone and enabled-widget fixture expectations; the run is terminal with no timeouts. These bounded repairs preserve production contracts rather than relaxing the assertions. The old Claude URLProtocol fixture also missed the new uncached client: placeholder-cookie requests escaped to a real endpoint in failed hosted tests, without real account credentials. The repaired TaskLocal transport intercepts both clients for the entire fixture operation. All 20 affected suites now have latest passing focused evidence: the initial 233-test/20-suite batch exposed one remaining Mimo capability expectation, and the affected 20-test/3-suite rerun passes after repair. Counts overlap and are not summed. Formatting/strict lint pass for all 18 changed Swift test files, with 219 valid documentation links. Production source remains byte-identical to the independently reviewed code source. The complete repaired-head hosted matrix and verified merge remain required.

### Upstream and cleanup

A fresh fetch still reports upstream `5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f`, with no additions beyond 930. The active main monitor cursor remains `cf79d1310493f2d028af62cc21e422b5f33c70a5` until complete covering delivery. This candidate prepares `5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f` in `version.env` so the active cursor changes atomically with the verified PR217 merge. `UPSTREAM_VERSION` and `UPSTREAM_SYNC_DATE` track shipped alignment and do not advance at merge.

Cleanup has retired 118 local and 19 remote refs and reduced 12 worktrees to one primary checkout. Fifteen local branches remain: main, unrelated battery work, the two active candidate branches and 11 old audited heads. The 11 old heads have a verified 116,352,382-byte recovery bundle (SHA-256 `86758e9dfdfbff3c9658fb698039f3bbeba4b5efb1f8f923ff73a7cfb2aa8be5`); unique changes are source-mapped or explicitly archived, and retirement follows the covering merge. Earlier private worktree patches and recovery bundles remain preserved.

**Next:** pass PR217 exact-head CI, verify its merge/tree on main, retire the covered refs with expected-OID checks, refresh upstream once more, advance the fully reconciled cursor and close issue #149 and the persistent goal. Preserve unrelated battery work and the primary checkout.

---

## Previous candidate record: grouped quota, process, pricing and provider clearance

Verified merged main is `80dac739a375b3dd6ca54ce2f8e192b3ca2175cd`
([PR #214](https://github.com/ColumbusLabs/QuotaKit/pull/214)): **693 accounted,
59 known gap rows and 169 unresolved rows**. All required checks passed at
`45a196240bc90a4fc777e209241b359b20d41a12` in CI run `36656402072`; its
exact tree matches the squash merge. The redundant identical-tree post-merge
run was cancelled and cancellation was verified.

The next reviewed code/doc candidate is `773099859e5beed780f3b6b8bb401496a5efeb3c`.
Its ledger proposal is **808 accounted + 73 known gap rows + 40 unresolved rows
= 921 total**, pending exact-head hosted CI and merge. These are commit-row
counts; source audits can discover gaps while implemented slices close them.
No cursor, product version, build number or release metadata advances.

| Candidate evidence tier | Rows |
| --- | ---: |
| Documented merged or observed in reviewed source | 481 |
| Source-audited justified exclusions | 86 |
| Release-only or no distinct merge behavior | 189 |
| Test/CI-only accounted rows | 52 |
| Known applicable gap rows | 73 |
| Unresolved source/applicability decisions | 40 |
| **Total** | **921** |

### Implemented and audited

- Close 14 runtime rows: quota burndown 876/889/890/899; owned Antigravity
  process cleanup 853/855/859/862/911; stored environment privacy 907;
  pricing 214/902; Azure version settings 407; Ollama recovery 603.
- Burndown preserves normalized provider/account reset windows, recorded capture
  age and utilization history. It does not extrapolate old readings.
- Environment wrappers redact automatic diagnostics without changing execution
  values. Process cleanup requires a fresh marker, same user and start identity
  before individual signals. Bounded parsing rejects truncated/conflicting
  evidence and empty-environment Apple vectors; unmarked siblings remain outside
  the new reaper's authority.
- Pricing resolves exact provider routes before aliases, preserves raw report
  identities, and uses historical event dates plus current Sol fallback rates.
  Parser predecessor `005a869f36400f7e` retains parsed rows and checkpoints while
  stale derived reports are recalculated. Mistral category policies were already
  delivered in #214; numeric row 462 was already represented in active paths.
- Azure shares its version override with CLI config while Default inherits the
  environment. Ollama explains empty Manual configuration, offers explicit
  guarded Auto recovery and retries recognized diagnostic candidates safely.
- Source audits cover 143 original rows across provider additions, quota,
  catalog/contracts, Claude/account behavior and maintenance. Remaining broad
  refactors, dependency/toolchain choices and unresolved policies stay open.
  Documentation rows 488/743 close through accurate QuotaKit provider/config
  guidance and preserved historical provenance.

### Verification and limits

Focused model/config/parser/provider and synthetic subprocess tests passed across
an integrated run and affected reruns. The final pricing/store run passed **149
tests**, the portable ownership run passed **seven**, and an isolated unchanged
Kimi timing suite passed **23**. Other affected suites passed in the preceding
run, including alias/historical pricing, Ollama diagnostic retry and source
architecture checks. Full repository lint reported **zero violations in 2,616
Swift files**; the last two fixture edits also passed focused strict lint.
Generated parser hash `15a7d46518e83cc0` is current.

Initial failures exposed stale pricing/cache expectations, shifted source anchors,
a Darwin environment boundary defect and the incomplete current Sol fallback.
These were corrected without weakening guards, process authority or timing budgets.
Independent security/process and provider/pricing reviews have no remaining
findings. The new research record is
[053](../CodexBarMobile/Research/053-upstream-quota-process-pricing-clearance.md).

Required hosted CI remains pending. Runtime paths require the full Mac shards;
the existing broad iOS path gate also matches the research document. No full local
suite, app launch, live provider/Keychain probe, archive/upload or release ran.

### Cleanup and next slice

There is **one primary worktree**, **103 local branches**, and **four origin
tracking refs including origin/HEAD** at this candidate checkpoint. Cleanup totals
**27 local and 16 remote branches removed**. Nine more completed snapshots were
source/test/doc reconciled to #214 main, bundled with SHA-256/exact-head proof,
and removed using expected-OID local ref deletion. Their private recovery bundle
is under `.git/upstream-cleanup-recovery/2026-09-29-nine-source-reconciled-refs/`.
The unfinished cost/Codex branch and unrelated battery work remain preserved.

Next: merge this exact candidate after required CI, remove its branch, update
issue #149 with verified merged counts, then group the remaining performance,
provider/UI, maintenance and source-verification work. Reconcile unique branch
contents and clean completed refs alongside each slice. All 140 historically
recorded merged/doc rows still require current-source spot checks before the full
goal closes. Refresh upstream at final closeout; do not advance the cursor merely
to reduce the raw backlog counter.

---

## Previous slice record: Mistral picker/billing and security/persistence audit

Code commit `7cdf18ad2b4e8845cbb3b744e58f86ac097bd43f` implements the Mistral picker and qualified billing-price
fixes. The previous merged documentation baseline is
`7294c03e3d22f7fe364cc3075dd18c41c63cf33d` ([PR #213](https://github.com/ColumbusLabs/QuotaKit/pull/213)).
This batch closes **six confirmed gap rows** (877/880/883/884/893/894), and source
audits all **17** unresolved `security and persistence` rows: 14 represented,
two test-only and one justified distribution-scope exclusion.

| Current combined evidence tier | Rows |
| --- | ---: |
| Documented merged or observed in current source | 381 |
| Source-audited justified exclusions | 81 |
| Release-only or no distinct merge runtime delta | 188 |
| Test/CI-only rows with no standalone runtime port | 43 |
| **Clear runtime gaps** | **59** |
| **Unresolved current-source/applicability decisions** | **169** |
| **Total** | **921** |

**693 accounted + 59 confirmed gap rows + 169 unresolved rows**, compared with
670/65/186 before this batch. These are commit rows, not missing feature counts
or required PRs. The [original ledger](upstream-backlog-ledger-2026-09-28.tsv)
changes only 17 current-source records; the [tail ledger](upstream-backlog-ledger-2026-09-29-tail.tsv)
changes seven records (six closures plus narrowed remaining pricing action 902).
All exact SHAs and the 12 historical columns stay intact.

### Implemented behavior and retained decisions

- Monthly Plan is an explicit supported provider choice across icon styles.
  It writes the existing stored metric. Icon-only layouts offer Auto/Monthly Plan
  without pinning an inherited global layout; explicit and mixed windows retain
  their precedence and Custom selection. Existing translated labels and the
  generic picker footer are reused.
- Billing prices match event, metric, group, API zone and service tier. Exact keys
  win; only a same-event price with both zone and tier absent can serve legacy
  tables. Nil and blank dimensions remain distinct, and another zone/tier price
  is not guessed. Consumed units, billed units, checked arithmetic and finite-cost
  guards retain their existing roles.
- The category-table refactor preserves the previous month/day token and model
  count rules. It does not claim a second token-accounting bug fix. Provider-local
  aliases and dated model pricing remain explicit gaps on their source rows;
  902 no longer asks for already implemented Mistral billing work.
- Security source evidence confirms cookie-domain scoping, no-prompt Muse access,
  opaque provider configuration, secure credential staging, iCloud device removal,
  portable preferences/shortcuts, opt-in power/expiry notifications, and daemon
  home/socket symlink handling. Existing tests referenced by those audit rows were
  inspected, not executed as part of the source-only audit.
- Row 481 concerns the upstream Linux/Omarchy desktop installer, absent from the
  QuotaKit distribution. [README](../README.md) now states the existing CLI-versus-
  separately maintained desktop boundary explicitly. QuotaKit's independent Linux
  CLI workflow already installs a regular executable before packaging, avoiding
  the upstream symlinked-binary concern. This does not remove Linux CLI support.

### Verification

**156 focused tests across 11 suites passed**, including 11 new regression test
methods for picker state and billing dimensions. The five-method billing suite
passed again after the only lint repair simplified a synthetic JSON helper.
The debug build passed. Full repository checks completed through branding,
localization, parser hash, manifests, packaging, shell, documentation and formatter
checks; full SwiftLint reported one violation in that new helper, and its focused
strict lint/format check passed after repair. No other source changed afterward.
Independent Luna review of the seven code/test files found no actionable issue.

Required hosted CI remains the merge gate. Existing path rules require the full
Mac suite for these runtime paths and skip iOS. No full local suite, app launch,
live provider/Keychain probe, release, or product-version change ran. This records
verified code and source accounting, not an installed app or live account result.

### Cleanup and next work

There is **one primary worktree**, 115 local branches and five origin tracking
refs at this slice's source inventory. The previous documentation branch was
removed after its exact tested tree matched the merged tree. Cleanup so far is
14 local and 14 remote branches; this batch's temporary branch will close with
its verified merge. Unique unfinished source and patches remain privately
recoverable. Primary app/build caches, signing material and release artifacts
are untouched.

**Next:** bounded Luna source audits of the remaining provider contracts, quota
correctness, catalog/architecture and additions groups run independently against
the pinned code commit while required CI completes. Record precise current-source
decisions, then group the next missing runtime work by dependencies. Do not rerun
CI for new audit documents on this already frozen runtime batch.

The [clearance goal](upstream-clearance-goal-2026-09-29.md) remains active. Both
broad upstream automations remain paused. Combined inventory stays exactly 921
rows through `25bba9b7fd9ce83c33053958f7366e23b2dc8a82`; refresh again at final
goal closeout. The monitor cursor remains
`cf79d1310493f2d028af62cc21e422b5f33c70a5` until all applicable work is merged
or specifically excluded. Version metadata, build numbers and appcast stay unchanged.

The sections below are historical snapshots; their counts are not current.

## Historical snapshot: clearance goal, Mac UX audit and fresh upstream tail (PR #213)

The persistent [clearance goal](upstream-clearance-goal-2026-09-29.md) is active.
The current implementation/source audit baseline is
`ac6c4c966f6012fffbc3144d40271b01a7646dfe`, the verified squash merge of
[PR #212](https://github.com/ColumbusLabs/QuotaKit/pull/212).
This slice audits **72 rows**: all 26 unresolved `Mac UX and reporting` rows and
46 newly discovered upstream commits. It changes source accounting, not runtime
behavior. Existing tests were inspected as source evidence, not executed.

The refreshed upstream head is `25bba9b7fd9ce83c33053958f7366e23b2dc8a82`.
The [original ledger](upstream-backlog-ledger-2026-09-28.tsv) retains its 875 SHAs
and all 12 historical fields. The [tail ledger](upstream-backlog-ledger-2026-09-29-tail.tsv)
adds ordinals 876–921: 27 nonmerges and 19 merges. Together they contain exactly
**921 unique rows**, matching the monitor-base-to-refreshed-head Git range.

| Current evidence tier across both ledgers | Rows |
| --- | ---: |
| Documented merged or observed in current source | 361 |
| Source-audited justified exclusions | 80 |
| Release-only or no distinct merge runtime delta | 188 |
| Test/CI-only rows with no standalone runtime port | 41 |
| **Clear runtime gaps** | **65** |
| **Unresolved current-source or applicability decisions** | **186** |
| **Total** | **921** |

There are **670 accounted rows, 65 clear runtime gap rows,
and 186 unresolved rows**. The previous 623/41/211 snapshot covered only
875 commits. The refreshed 46-row tail expands the inventory; raw row counts
measure commits, not missing features or required PRs. The original Mac UX audit
accounts for 18 rows and identifies eight gap/partial rows, reducing that original
unresolved inventory from 211 to 185. Tail decisions and precise remaining actions
are recorded individually in the new ledger.

### Grouped implementation actions

- Mac UX: one Homebrew installed-cask command/check/upgrade chain (386/459/687),
  DeepSeek optional-details visibility (417), passive Antigravity CLI selection
  and metadata preservation (580), additional balance/Doubao window mapping
  (594), layout-editor hint cleanup (665), and bounded opt-in hosting diagnostics
  (695). The Homebrew work must use QuotaKit's installed cask identity and does
  not authorize adding an official distribution lane.
- Fresh tail: group Mistral's Monthly Plan picker and billing dimensions/aggregation,
  model aliases and date-aware pricing, quota burndown/history context, and any
  process/security findings by shared dependencies. Merge wrappers, superseded
  experiments and upstream release notes are not separate runtime ports.
- Preserve QuotaKit's intentional transient compact-account expansion. Row 505's
  blank-currency fallback was already present before that upstream commit; the
  shared conversion refactor is represented, not a newly discovered product gap.
- Palette applicability and all remaining disputed rows retain explicit next
  checks. A fork-specific color difference alone is not evidence of a missing
  feature. Existing safety follow-ups 88/487 remain explicit.

### Cleanup completed during this slice

**12 worktrees became one primary checkout.** Four clean and six dirty side
checkouts were removed after their exact heads and staged/unstaged patches passed
recovery verification; the duplicate clean checkout was separately proven equal
to its retained source tree before removal. No side checkout had untracked files.
All unique unfinished source remains recoverable in private bundles and patches,
and its branch/source disposition continues. Cleanup does not claim it is merged.

**13 local branches and 13 remote branches were removed.** Completed heads were
matched to merged PR heads and merge commits on main; remote deletion used
expected-OID leases. Verified private recovery bundles precede all removals.
Current inventory is **one worktree, 115 local branches, and five origin tracking
refs** (including `origin/HEAD` and `origin/main`). The goal branch is temporary;
remaining unique branch/source inventories still need reconciliation and cleanup.
Primary app/build caches, signing files, local settings and release artifacts were
untouched. Full restoration evidence lives under `.git/upstream-cleanup-recovery/`.

### Verification and next slice

Local verification for this documentation-only slice covers row/schema integrity,
exact SHA range membership, preservation of historical fields, documentation links,
and existing CI path gates. Required hosted CI is the delivery gate; no local Swift
suite, app launch, live provider or Keychain probe belongs to this source audit.
The existing gates skip Mac and iOS tests for these documentation paths.

**Next:** implement the Mistral picker and billing fixes as one integrated batch,
using disjoint Luna assignments, focused synthetic tests and one required CI cycle.
Continue bounded audits of the remaining groups while cleaning completed refs.
Refresh upstream again at final goal closeout; advance the monitor cursor only
when every applicable row is implemented and merged or specifically excluded.
Both broad upstream automations remain paused. The cursor remains
`cf79d1310493f2d028af62cc21e422b5f33c70a5`; product versions, build numbers,
appcast and release state are unchanged.

The sections below are historical snapshots; their counts and checkout inventories
are not current.

## Historical snapshot after the identity and credential fixes (PR #212)

The implementation is merged at `ac6c4c966f6012fffbc3144d40271b01a7646dfe`
through [PR #212](https://github.com/ColumbusLabs/QuotaKit/pull/212).
Code commit `2ddfa198b247e58954898b87d035e9aa729ca6f2` closes four confirmed gaps:

- **387:** preserve SSH username case and deduplicate only hostname case variants.
- **390:** apply the fork's strict Hide Personal Info policy to System Account
  titles using stable numbered slots; retain raw labels when privacy is off and
  preserve promotion actions, checked/enabled state, restart note, and visibility.
- **391:** stop immediate Cursor retries for unchanged unconfirmed credentials,
  retain accepted usage, and retry changed credential/settings scopes normally.
- **601:** include ambient Codex active/archive session spend without file-backed
  account identity; share normalized source discovery and ownership fingerprints,
  deduplicate the ambient home, and retain named-account scan/auth guards.

| Current evidence tier | Rows |
| --- | ---: |
| Documented merged or observed in current source | 339 |
| Source-audited justified exclusions | 80 |
| Release-only or no distinct merge source delta | 167 |
| Test/CI-only rows with no standalone runtime port | 37 |
| **Clear runtime gaps** | **41** |
| Prior `adapted` claims still unverified on current `main` | 107 |
| Prior `pending` or `deferred` work needing current decision | 69 |
| Plausible historical exclusions needing per-row proof | 21 |
| Other review rows | 14 |
| **Total** | **875** |

There are **623 accounted rows**, **41 clear runtime gaps**, and **211 unresolved
rows**, compared with 619/45/211 before this batch. Counts measure upstream rows,
not features or required PRs. The [row-level ledger](upstream-backlog-ledger-2026-09-28.tsv)
retains all exact SHAs and historical fields; only the four current records
above change here. Unresolved applicability rows 200/315/317 and test/CI safety
follow-ups 88/487 remain explicit.

Verification: **162 focused tests across nine suites passed**, including 14 new
regression test methods for privacy, retry disposition, and authless local spend,
plus the extended SSH destination test. The debug build, repository lint,
parser-hash, format, localization, branding, palette, and documentation-link
checks passed. Independent review found no actionable issue. No full local suite,
live provider/Keychain probe, or app relaunch ran.

Required hosted CI remains the merge gate. Existing routing requires the full
Mac suite for these runtime paths and skips iOS. This describes verified source
and tests, not an installed build, release, or physical-device observation.

The fixed cut remains `bd77ea6a7b35c8e3b66d46285f718c8eebf285b7`: 758
nonmerges and 117 merges. The monitor cursor remains
`cf79d1310493f2d028af62cc21e422b5f33c70a5`. Both upstream automations remain
paused. All 12 worktrees, including six dirty source inventories, are preserved;
this batch creates no worktree. Product version, build numbers, appcast, and
release state are unchanged.

**Next:** source-audit the 26 unresolved `Mac UX and reporting` rows together,
recording net behavior and exact evidence before deciding which runtime work is
needed. Keep later implementation grouped by shared dependencies; do not restart
broad per-commit automation. Advance the cursor only after every applicable row
has its final disposition and adopted work is merged.

The sections below are historical snapshots; their counts are not current.

## Historical snapshot after the cache-scope and overflow fixes (PR #211)

The implementation is merged at `94e764a549de40bce8224a2e85a421d8ca9aa940`
through [PR #211](https://github.com/ColumbusLabs/QuotaKit/pull/211).
Code commit `35a2f0fc4453a3e31fa64ccb14b36bb6145ef453` closes two confirmed
correctness gaps without changing scanner receipts, persistence schemas, API
prices, the reporting horizon, or release metadata:

- **365:** validate raw cache ownership before the workspace refresh performs
  sidecar lookup or history import. Failed and other-home reads preserve the
  prior nonempty history; valid empty scans remain publishable.
- **73:** preserve the existing overflow-aware exact/request/row coverage
  accumulator through dashboard windows and Overview currency groups. Lost
  exactness remains sticky rather than being reconstructed from flattened counts.

| Current evidence tier | Rows |
| --- | ---: |
| Documented merged or observed in current source | 335 |
| Source-audited justified exclusions | 80 |
| Release-only or no distinct merge source delta | 167 |
| Test/CI-only rows with no standalone runtime port | 37 |
| **Clear runtime gaps** | **45** |
| Prior `adapted` claims still unverified on current `main` | 107 |
| Prior `pending` or `deferred` work needing current decision | 69 |
| Plausible historical exclusions needing per-row proof | 21 |
| Other review rows | 14 |
| **Total** | **875** |

There are **619 accounted rows**, **45 clear runtime gaps**, and **211 unresolved
rows**, compared with 617/47/211 before this fix batch. These counts measure
upstream rows, not features or required PRs. The
[row-level ledger](upstream-backlog-ledger-2026-09-28.tsv) retains all exact SHAs
and historical fields; only current fields for 73 and 365 change here. The
provider/shared audit's open questions (200, 315, 317) and test/CI safety
follow-ups (88, 487) remain explicit and unchanged.

Verification covers **82 unique focused tests** across cost provenance, merged
reports, snapshot/dashboard coverage, Overview summaries, workspace cache scope,
and the affected architecture gate. There are **17 new synthetic boundary cases**:
11 coverage cases and six cache-scope cases. The initial run exposed an incorrect
raw-scanner-cache preservation assertion and a stale source-line anchor; both
were corrected, and the three affected suites passed after rebuilding. A fixture
now explicitly establishes nonempty history before testing preservation. Repository
lint, parser-hash, format, localization, branding, palette, and documentation-link
checks passed. Independent review found no remaining issue. No full local suite,
live provider/Keychain probe, or app relaunch was run.

Required hosted CI remains the merge gate. Existing routing requires the full
Mac suite for these runtime paths and skips iOS. Source and focused-test evidence
is not a claim of installation, release, or live device behavior.

The fixed cut remains `bd77ea6a7b35c8e3b66d46285f718c8eebf285b7`: 758
nonmerges and 117 merges. The monitor cursor remains
`cf79d1310493f2d028af62cc21e422b5f33c70a5`. Both upstream automations remain
paused. All 12 worktrees, including six dirty source inventories, are preserved;
this batch creates no worktree. Product version, build numbers, appcast, and
release state are unchanged.

**Next:** address Codex System-account privacy labels (390) and local spend for
keyring-backed logins (601) as a bounded account-presentation batch using scoped
credential doubles. Continue grouped audits later without restarting broad
per-commit automation. Advance the cursor only after every applicable row has
its final disposition and adopted work is merged.

The sections below are historical snapshots; their counts are not current.

## Historical snapshot after the provider/shared audit (PR #210)

The source audit baseline is `origin/main=c364817d50f0380c56e35c2c7fbd47471b164679`,
the verified squash merge of [PR #209](https://github.com/ColumbusLabs/QuotaKit/pull/209).
All **42** previously unresolved `provider and shared correctness` rows received
current-source evidence. This batch makes **39 final decisions**: **33 accounted**
and **6 confirmed runtime gap or partial-coverage rows**. Three applicability
questions remain open. No runtime code changes are included in this audit.

The accounted rows comprise 25 represented behaviors, five source-audited
exclusions, one upstream release-bookkeeping row, and two test/CI-only rows.
Kiro's optional overage guard already matches upstream, including the CLI fallback.
Pi's temporary parser-key compatibility was superseded by the fixed upstream cut;
porting its old hash exception would introduce obsolete behavior. Source review
and existing test assertions support the represented decisions; those tests were
not executed during this documentation-only audit.

| Current evidence tier | Rows |
| --- | ---: |
| Documented merged or observed in current source | 333 |
| Source-audited justified exclusions | 80 |
| Release-only or no distinct merge source delta | 167 |
| Test/CI-only rows with no standalone runtime port | 37 |
| **Clear runtime gaps** | **47** |
| Prior `adapted` claims still unverified on current `main` | 107 |
| Prior `pending` or `deferred` work needing current decision | 69 |
| Plausible historical exclusions needing per-row proof | 21 |
| Other review rows | 14 |
| **Total** | **875** |

There are **617 accounted rows**, **47 clear runtime gap rows**, and
**211 unresolved rows**, compared with 584/41/250 before this batch. Counts
measure upstream rows, not features or required PRs. The
[row-level ledger](upstream-backlog-ledger-2026-09-28.tsv) retains all 875 SHAs,
all historical fields, and the precise source evidence and next action for each
of the 42 audited rows.

The six newly confirmed runtime gaps are Hooks input accessibility (147),
malformed optional Z.ai analytics in the opt-in JS provider path (188), forced
vibrancy affecting Overview highlights (202), opt-in hiding of unreachable
remote hosts (260), Grok visor icon decoration (285), and StepFun credit labels
and unknown-reset handling (470). These are source findings; no live provider,
macOS rendering, accessibility-tree, or device behavior was tested.

Two non-runtime follow-ups remain explicit in accounted test/CI rows: nested
process containment in the CI runner (88), and the second real-Keychain consent
gate in the opt-in Claude live test (487). Accounted here means no standalone
product runtime port; it does not claim that those harness changes are present.
Neither live test nor any Keychain probe was run.

Three rows remain unresolved: exact dependency/action compatibility and security
applicability (200), shared card context and explicit subtitle localization
coverage (315), and applicability of upstream toolchain/lint/release routes (317).
Historical PR pointers for 317 are preserved as evidence to inspect, not proof
that those changes are represented.

Verification for this batch is ledger integrity, documentation links, diff
whitespace, and changed-path CI routing. The existing gates skip Mac and iOS
jobs for these two documentation files; required hosted lint and Linux CLI CI
remain the merge gate. No local Swift build or test suite was started.

The fixed cut remains `bd77ea6a7b35c8e3b66d46285f718c8eebf285b7`: 758
nonmerges and 117 merges. The monitor cursor remains
`cf79d1310493f2d028af62cc21e422b5f33c70a5`. Both upstream automations remain
paused. Six dirty source worktrees are preserved; no new worktree was created.
Product version, build numbers, appcast, and release state are unchanged.

**Next:** implement cache-scope validation (365) and overflow-safe cost
aggregation (73) as one bounded correctness batch with focused tests. The
remaining uncertain rows can be audited in later bounded groups; do not
restart broad per-commit automation. Advance the cursor only after every
applicable row has a final disposition and adopted work is merged.

The sections below are historical snapshots; their counts are not current.

## Historical snapshot after the cost/history batch (PR #209)

The audit baseline is `origin/main=005c2e48efce0467d84e7cf62b9f93655cde7536`.
All 59 previously unresolved rows in the two cost/history groups now have an
individual source decision: **43 accounted** and **16 confirmed runtime gap or
partial-coverage rows**. The accounted rows comprise 38 represented behaviors,
two documentation rows, two structural/applicability exclusions, and one merge
wrapper accounted for by its children. Missing upstream test assertions alone
were not treated as missing runtime behavior.

The scanner change in code commit `77cc0627e33b885f901aa30dc85af1e672c94bb7`
accounts for upstream ordinal 800: priority reconciliation visits recorded day
keys, removes stale metadata inside the inspected window, and retains history
outside it. Upstream ordinal 776 is a source-audited exclusion: ordinal 800's
first-parent scanner diff reverses that earlier history clamp to retain daily
discovery accounting. QuotaKit's production reporting horizon is 365 days, with
existing fetcher bounds and reporting-period tests. Adding an unbudgeted search
for the first existing date partition would conflict with the paged scanner.

| Current evidence tier | Rows |
| --- | ---: |
| Documented merged or observed in current source | 308 |
| Source-audited justified exclusions | 75 |
| Release-only or no distinct merge source delta | 166 |
| Test/CI-only rows with no standalone runtime port | 35 |
| **Clear runtime gaps** | **41** |
| Prior `adapted` claims still unverified on current `main` | 123 |
| Prior `pending` or `deferred` work needing current decision | 86 |
| Plausible historical exclusions needing per-row proof | 28 |
| Other review rows | 13 |
| **Total** | **875** |

There are now **584 accounted rows**, **41 clear runtime gap rows**, and
**250 unresolved rows**. The previous totals were 539, 27, and 309. The gap count
increased because this audit confirmed 16 previously uncertain deltas, while
the scanner fix and the history-clamp exclusion dispositioned two prior gaps.
These counts measure upstream rows, not features or required PRs. The
[row-level ledger](upstream-backlog-ledger-2026-09-28.tsv) preserves all 875 SHAs
and their historical evidence; only current dispositions and follow-up actions
changed in this batch.

The newly confirmed gaps group into cache/read efficiency (47, 71, 149, 311,
362, 465), accounting and cache-scope correctness (73, 365, 547), credential
and identity behavior (387, 390, 391, 601), menu refresh (422), and OpenCode/SSH
reporting (485, 486). Performance rows have concrete source deltas; no measured
speedup or memory reduction is claimed. The shared dependency paths allow these
rows to be handled in coherent slices instead of one PR per upstream commit.

Focused verification covered **54 unique tests** across sparse metadata,
priority reconciliation, priority cursors, fair scheduling, and reporting-period
bounds. The three new metadata tests passed again after formatting. The
independent scanner review found no confirmed issue. Parser-hash generation,
format/lint, localization, customer-branding, provider-palette, and portable
repository checks passed. Required hosted CI and merge remain the integration
gate for this batch; local test evidence is not a claim of deployed behavior.

The fixed cut remains `bd77ea6a7b35c8e3b66d46285f718c8eebf285b7`: 758
nonmerges and 117 merges. The monitor cursor remains
`cf79d1310493f2d028af62cc21e422b5f33c70a5`. Both upstream automations remain
paused. Six dirty source worktrees remain preserved. Product version, build
numbers, appcast, and release state are unchanged. Continue by auditing the
remaining 250 uncertain rows in bounded behavior groups and integrating the
41 confirmed gaps in coherent slices. Advance the cursor only after every
applicable row has a final disposition and adopted work is merged.

The sections below are historical snapshots; their counts are not current.

## Historical snapshot after PR #207 and the 16-row follow-up

- The code audit baseline `origin/main=88ef1cac0690b115e27ed1b0116ebe14716f098a` includes the two Codex fixes in PR
  #207. Receipt-backed cache saves account for upstream ordinal 74; visible
  credential-owner rechecks account for ordinal 253. PR #207 passed its required
  hosted CI before merging.
- The fixed cut remains `bd77ea6a7b35c8e3b66d46285f718c8eebf285b7` and
  the monitor cursor remains `cf79d1310493f2d028af62cc21e422b5f33c70a5`.
  This range has 875 exact SHAs: 758 nonmerges and 117 merges.
- A follow-up audit resolved 15 plugin architecture rows using current-main
  source and tests: 13 behaviors are represented, one QuickJS source-size rule
  is CI-only, and one API-key adapter consolidation has no distinct provider
  behavior to port. A separate check found upstream ordinal 35's narrow cached
  reads represented by QuotaKit's compact report and catch-up projections.
  No quantified performance improvement is claimed for that row.

| Current evidence tier | Rows |
| --- | ---: |
| Documented merged or observed in current source | 267 |
| Source-audited justified exclusions | 72 |
| Release-only or no distinct merge source delta | 165 |
| Test/CI-only rows with no standalone runtime port | 35 |
| **Clear runtime gaps** | **27** |
| Prior `adapted` claims still unverified on current `main` | 143 |
| Prior `pending` or `deferred` work needing current decision | 121 |
| Plausible historical exclusions needing per-row proof | 30 |
| Other review rows | 15 |
| **Total** | **875** |

The first four tiers account for **539** rows. Another **309** rows need a
current-source decision; they are not a 309-feature implementation queue. The
**27** clear gaps are a defensible lower bound. Their workstreams are accounting
and scan identity (2), credentials/process/security (13), provider quota
correctness (5), plugin/configuration behavior (3), and reporting/widgets (4).
The [row-level ledger](upstream-backlog-ledger-2026-09-28.tsv) records each
SHA's exact disposition and evidence.

Both upstream automations remain paused. The cursor, product version, build
number, appcast, and release state are unchanged. Six dirty worktrees remain
preserved as source inventories. Resolve the remaining 309 uncertain rows by
shared behavior and exact exceptions, then integrate the 27 confirmed gaps in
coherent slices. Advance the cursor only after every applicable row has a final
disposition and adopted work is merged.

The sections below retain earlier 875-row and 850-row snapshots as historical
evidence. Their older counts are not the current remaining-work totals.

## 2026-09-28 snapshot after PR #205

- The QuotaKit audit baseline is `origin/main=f8481642fea06572cddcca389c0c2581e669873f`,
  the squash merge of PR #205. It includes the recent merged cost,
  provider, shared-code, ledger, and account-label repairs in PRs #199-#205.
- The upstream cursor remains `cf79d1310493f2d028af62cc21e422b5f33c70a5`.
  Fetched `upstream/main=bd77ea6a7b35c8e3b66d46285f718c8eebf285b7`
  yields 875 commits in the audit range: 758 nonmerges and 117 merges.
  This is 25 SHAs beyond the frozen snapshot below, not 875 unmerged features.
- The [row-level ledger](upstream-backlog-ledger-2026-09-28.tsv) includes all
  875 SHAs, the source drafts' evidence for 742 historical rows, and merged-PR
  provenance where an upstream SHA is explicitly named. Its
  `current_main_status` column distinguishes live verification from prior
  draft dispositions. A merged PR reference is evidence to inspect, not
  automatic proof of behavioral coverage.
- The 25 added SHAs comprise 13 runtime/product changes, four upstream release
  bookkeeping commits, and eight merge wrappers with no separate behavior.
  Eleven runtime entries remain absent or only partially present on current
  main; several belong to coherent Agent Sessions and Antigravity fixes.
- Both upstream automations remain paused. No upstream cursor, version, build
  number, appcast, or release artifact was changed during this audit.

## Remaining-work accounting at PR #205 snapshot

The row statuses below are disjoint and total 875. They measure **audit
evidence**, not features or PRs. A source-audited historical integration claim
is documented progress; it is not a promise that later overlapping changes
cannot have regressed that behavior.

| Current evidence tier | Rows | Interpretation |
| --- | ---: | --- |
| Documented merged or observed in current source | 251 | The prior 214 plus 35 exact mappings in provider, shared, and Codex cost groups, and two account-label fixes in PR #205. |
| Source-audited justified exclusions | 71 | The prior 70 plus one structural cookie/reset helper refactor whose behavior is present in shared code. |
| Release-only or no distinct merge source delta | 165 | 87 upstream release-bookkeeping rows and 78 merge wrappers; their child changes are counted separately. |
| Test-only rows with no standalone runtime port | 34 | The prior 33 plus a plugin fixture control that leaves the production collection budget unchanged. Test intent may travel with a related feature slice. |
| **Clear runtime gaps** | **29** | Two account-label gaps closed in PR #205; two Codex cost and credential-owner gaps were confirmed during this pass. |
| Prior `adapted` claim still unverified on current `main` | 158 | A staged branch or old label is not proof of merge. |
| Prior `pending` or `deferred` work needing current decision | 121 | Some may have landed in broad PRs; each still needs a current-main mapping. |
| Plausible historical exclusion needing per-row proof | 30 | Runtime or other files still require current behavior or applicability evidence. |
| Other review rows | 16 | Ten architecture/adaptation reviews, four disputed exclusions, one partially covered cost row, and one reopened Homebrew runtime decision. |

**The defensible lower bound is 29 runtime gap rows, not 875 missing features.**
Another 325 rows remain outside the closed evidence and clear-gap tiers. They
include historical merge claims, likely exclusions, and possible product work;
they are not a 325-feature implementation queue. Issue #149's prior 712-commit
count is stale; the cursor-to-head audit range is 875 at the fetched head above.

The group pass closed 133 rows without a feature port: 78 nonmerge commits
change only upstream `CHANGELOG.md`, `version.env`, or `appcast.xml`; 20
nonmerge rows change only `Tests/`; one previously covered test row has no
standalone runtime delta; and 34 merge commits have no runtime source in their
remerge resolution. Each ledger row records its exact path evidence. A merge's
child commits remain separate ledger rows. This path rule deliberately leaves
30 plausible exclusions open because they touch runtime or other surfaces.

A bounded review of the 19 unresolved `tests and CI` group rows accounted for
16 more: four behaviors already represented by current-main PR #192, and 12
test or fixture changes without a standalone runtime port. Three remain open:
OpenCodeGo production accumulation, a Homebrew release retry, and Python
runner containment. The ledger records the distinct reason for each.

A prior grouped pass resolved 51 uncertain rows: 36 verified current-main
behaviors, 12 source-audited exclusions, one test-only fixture, and two then
confirmed account-label gaps. It reviewed high-confidence subsets of
Claude/credential, plugin, provider-quota, and Mac menu groups, plus Linux-only
and Cursor rows. Unchecked rows in those groups stayed open.

This pass reviewed 129 unresolved rows across `provider and shared
correctness`, `Codex cost and catch-up`, and `Shared provider and plugin
contracts`. Thirty-eight received exact decisions: 35 current-main behaviors
with source/test anchors, one justified structural exclusion, and two confirmed
partial runtime gaps. The other 91 remain open. PR #205 closes the two prior
account-label gaps: privacy-safe swap labels in Claude cards and account-label
precedence in the dashboard. The newly confirmed gaps are Codex cache saves
that still read a second snapshot instead of retaining a receipt-backed
single-read baseline (upstream ordinal 74), and reauthentication that does not
recheck changed, removed, or workspace-mismatched credential ownership before
selection (ordinal 253). These remain linked to the cost and credential slices.

### Fixed-cut execution

Hold this catch-up pass at `bd77ea6a7b35c8e3b66d46285f718c8eebf285b7`.
Newer upstream commits belong to the next pass; they do not enlarge this
acceptance set while fixes are under review. The 29 clear-gap rows belong to
five workstreams:

| Workstream | Gap rows | First action |
| --- | ---: | --- |
| Accounting and scan identity | 3 | Reconcile Codex history bounds and the single-read cache save baseline; PRs #200 and #201 covered Pi identity and Claude spend/cache. |
| Credentials, process lifecycle, and security | 14 | Reconcile fresh credentials, credential-owner rechecks, bounded validation, teardown, owned child cleanup, and redaction. |
| Provider quota correctness | 5 | Reconcile TypeSafe, Antigravity, Kimi, and z.ai behavior. |
| Plugin and configuration behavior | 3 | Reconcile plugin tab, blank config, and validated cookie sessions. |
| Reporting and widget UX | 4 | Reconcile model labels, persistent menu row, and per-provider widget retention. |

Submit related slices together when they share source and tests. Independent
PRs can run concurrently because the protected branch does not require a
fresh base for its check gate. QuotaKit CI starts four full Mac shards even for
a small Mac-only fix, so one PR per upstream SHA would repeat that cost without
improving the evidence. Keep unrelated or high-risk fixes separate.

Resolve the 325 uncertain rows by their 26 existing `prior_group` values: cite
the current source or merged PR once for a genuinely shared behavior, apply
that decision to its exact SHA set, and list exceptions individually. Preserve
uncertain runtime cases as explicit follow-ups. This is a grouping method, not
a blanket assertion that a branch or PR title proves coverage. Measure progress
by verified slices merged and rows with defensible dispositions.

The 29 clear gaps include Codex sparse-history bounds, Claude Web reset-credit
fallback, TypeSafe balances, Grok model names, Keychain validation bounds,
Antigravity quota parsing, Kimi/z.ai availability, Agent Sessions teardown,
Antigravity descendant cleanup, Codex credential/plan refresh, app-server
trust, per-provider widget retention, Codex single-read cache saves,
credential-owner rechecks, environment redaction, and Notion/ZoomMate cookie
sessions. The ledger carries each SHA and current-source anchor.

Six dirty worktrees are preserved as source inventories. Their distinct
candidate slices include Kimi/CommandCode quota data, plugin cookie sources
and OpenCodeGo console fallback, Codex scanner performance residue, and
account-switcher label redaction. Several branch stacks duplicate merged
behavior or each other; 118 unmerged local branch refs collapse to 40 terminal
tips, and neither number measures missing upstream features. Apply scoped
diffs against current `main`; do not merge old branch trees wholesale.

### Next accounting and integration sequence

1. Finish the 158 old `adapted`, 121 `pending`/`deferred`, and 30 plausible
   exclusion decisions against current source and merged PR evidence. Record
   the exact QuotaKit commit, source anchor, justified exclusion, or linked
   follow-up per row. Preserve the six dirty worktrees while reconciling them.
2. Integrate the confirmed runtime gaps in coherent dependency slices, using
   the staged provider/plugin work only after comparison with PR #199 and the
   newer upstream fixes. Run focused checks during development and exact-head
   hosted CI at each merge gate.
3. Advance `UPSTREAM_MONITOR_BASE` only after every applicable row has a final
   disposition and all adopted work is merged. The paused automation and
   QuotaKit-owned release metadata remain unchanged until separately resumed
   or released.

The counts and consolidation order below are the **earlier 850-row snapshot**.
They are retained to show the starting point and must not be read as the live
remaining-work count.

This is a frozen, read-only accounting snapshot for CodexBar
`cf79d1310493f2d028af62cc21e422b5f33c70a5..03f4b68881930269793320d68776fd5f4f76d453`
against QuotaKit `main=b5fcb9efe91f49e7dd64e05e0060c1197bb05559`.
The row-level inventory is [upstream-backlog-ledger-2026-09-28.tsv](upstream-backlog-ledger-2026-09-28.tsv).
It records audit state, not approval to advance `UPSTREAM_MONITOR_BASE`.

## Accounting

- 850 upstream commits: 743 nonmerges and 107 merges.
- 742 rows have historical draft dispositions from the automation's
  `frozen-dispositions-draft-2026-09-26.tsv` and
  `recent-dispositions-draft-2026-09-26.tsv`. Those drafts predate merged
  QuotaKit PRs #192 and #196; an `adapted` label may refer only to a staged
  branch. Reconcile every row against current `main` before calling it done.
- Of the 742 prior rows, 507 need current-main reconciliation (358 adapted,
  90 deferred, 59 pending) and 235 need exclusion review (123 rejected,
  112 superseded). The 90 deferred rows have no linked QuotaKit issue in their
  blocker fields. Group or resolve any still-applicable deferrals explicitly.
- 108 commits have no historical draft disposition: 48 runtime or mixed,
  10 test-only, 5 apparent upstream release bookkeeping, and 45 merge wrappers.
  These are provisional path-based buckets, not final adoption decisions.
  Merge wrappers require their child commits and any distinct merge resolution
  to be accounted for.
- `git cherry` finds no patch-identical upstream nonmerge in `main` across
  this range. QuotaKit has adapted and squash-merged upstream work, so patch
  identity and upstream commit ancestry cannot measure behavioral coverage.

## Local integration inventory

At the start of cleanup, Git registered 102 worktrees. Ninety clean secondary
checkouts inside this project were removed with `git worktree remove` without
force. Their local branch refs were retained. Twelve registered worktrees
remain: primary `main`, six with tracked uncommitted edits, and five under
`~/.codex/worktrees` outside this project workspace. There are no open QuotaKit
PRs. The primary checkout still matches `origin/main`.

Preserve these six dirty checkouts until their differences are reconciled on
current `main`:

| Branch | Tracked dirty files | Scope |
| --- | ---: | --- |
| `agent/upstream-codex-workspace-credits` | 23 | Codex workspace, account menu and tests |
| `agent/upstream-cost-history-perf` | 9 | Scanner, cache and performance tests |
| `agent/upstream-plugin-spec-tail` | 61 | Provider/plugin specs, fixtures and docs |
| `agent/upstream-post-provider` | 5 | Scanner replacement and direct-fork tests |
| `agent/upstream-provider-correctness` | 17 | OpenCode/Go provider handling and tests |
| `agent/upstream-provider-quota-tail` | 10 | Kimi/CommandCode quota and tests |

Only two dirty file sets overlap: `agent/upstream-cost-history-perf` and
`agent/upstream-post-provider` both edit `CostUsageScanner.swift` and
`CostUsageScanner+CacheHelpers.swift`. Reconcile those together for issues
#193/#195. The other four dirty sets have separate paths, although shared
provider and sync contracts still require review.

Historical branch names are not proof of pending work. The tree of
`agent/upstream-followon-bulk` is identical to `main`. The tree of
`agent/upstream-new-tail` differs in 29 files and includes older versions of
mobile identity code and tests. Do not merge either old stack wholesale.

## Consolidation order

1. Reconcile the 742 historical rows against current `main` and classify the
   108 unreviewed rows, recording the exact QuotaKit PR/commit, current code
   evidence, justified exclusion, or linked follow-up for each applicable
   upstream behavior. Do not equate a staged branch with a merged result.
2. Handle cost and data-integrity gaps separately. Issue #193 has candidate
   commits on `agent/direct-fork-baseline-port` and related dirty scanner
   edits on `agent/upstream-post-provider`. Issue #195 has dirty cache and
   scanner work on `agent/upstream-cost-history-perf`. Issue #194 has no
   verified completion candidate in this inventory. Review and test each on
   current `main` before an integration PR.
3. Consolidate provider, plugin and credential changes from the four related
   dirty worktrees above, then inspect later upstream fixes in the 48
   unreviewed runtime or mixed commits. Preserve QuotaKit provider IDs,
   generated manifests, credentials and Mac-to-iPhone contracts.
4. Integrate remaining Mac UI/reporting changes only after checking old
   branch tips against current `main`; use scoped changes rather than old
   stacks. Run focused checks while iterating and required hosted checks at
   each final PR head.
5. Advance `UPSTREAM_MONITOR_BASE` only when all 850 rows have final evidence:
   adopted/adapted work merged, exclusions justified, and applicable deferred
   work linked to concrete follow-up issues. Keep `UPSTREAM_VERSION` tied to
   actual user-facing releases.

No builds, tests, PRs, merges, cursor changes, or releases were started during
this short cleanup and ledger pass.

## Combined final verification checkpoint — 2026-09-30

PR #217’s Recovery20 exact-head CI passed lint, Linux, iOS and macOS compatibility, but Mac shards exposed a locally reproduced stack overflow during fork-history hydration and redundant alias lookups in warm scans. The obsolete remaining run was cancelled. A coherent POSIX file-identity helper and reuse of one alias snapshot repair those paths without weakening receipt, parser, schema, path-moved or retry guards. The scanner edit updates the generated parser hash to `c52728bbaeedeb90`; the prior published `7607317f30850961` compatibility path is retained, with no unmerged intermediate producer whitelisted.

All 41 original-cut rows remaining after Recovery20 map to the integrated final wave. The combined source remains uncredited until coordinated focused tests, lint, exact-head hosted CI and covering merge pass. Extend #217 with this integrated wave and the reviewed nine-object fresh tail, then perform one required CI matrix. Merged credit remains 860/921; 930 objects have been observed. There is one worktree and 15 local branches.
