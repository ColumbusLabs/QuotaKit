# Upstream backlog reconciliation — 2026-09-28

## Current status after the cost/history batch

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
