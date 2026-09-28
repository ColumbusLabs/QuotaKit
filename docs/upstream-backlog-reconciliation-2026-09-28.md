# Upstream backlog reconciliation — 2026-09-28

## Live refresh after PR #200

- QuotaKit `origin/main=77746961dc157fa554d652236e8e651ec092ccd3`
  includes PR #200's Pi root-identity fix. PR #199 had already merged the
  direct-fork, Codex append-prefix, and Pi temporal accounting fixes; issues
  #193, #194, and #195 are closed. PR #201 is open with hosted checks running.
- The upstream cursor remains `cf79d1310493f2d028af62cc21e422b5f33c70a5`.
  Fetched `upstream/main=bd77ea6a7b35c8e3b66d46285f718c8eebf285b7`
  yields 875 commits in the audit range: 758 nonmerges and 117 merges.
  This is 25 SHAs beyond the frozen snapshot below, not 875 unmerged features.
- The [row-level ledger](upstream-backlog-ledger-2026-09-28.tsv) now includes
  all 875 SHAs, the source drafts' evidence for 742 historical rows, and
  merged-PR provenance where an upstream SHA is explicitly named. Its
  `current_main_status` column distinguishes live verification from prior
  draft dispositions. A merged PR reference is evidence to inspect, not
  automatic proof of behavioral coverage.
- The 25 added SHAs comprise 13 runtime/product changes, four upstream release
  bookkeeping commits, and eight merge wrappers with no separate behavior.
  Eleven runtime entries remain absent or only partially present on current
  main; several belong to coherent Agent Sessions and Antigravity fixes.
- Both upstream automations remain paused. No upstream cursor, version, build
  number, appcast, or release artifact was changed during this audit.

## Current remaining-work accounting

The row statuses below are disjoint and total 875. They measure **audit
evidence**, not features or PRs. A source-audited historical integration claim
is documented progress; it is not a promise that later overlapping changes
cannot have regressed that behavior.

| Current evidence tier | Rows | Interpretation |
| --- | ---: | --- |
| Documented merged or observed in current source | 173 | Includes 132 historically source-audited integrations, eight later mapped adaptations, one corrected Mistral exclusion, 26 newly checked older-tail rows, two Pi root-identity rows merged in PR #200, and four test/CI behaviors represented by PR #192. |
| Source-audited justified exclusions | 58 | Concrete supersession, platform, release, structural, test, or documentation rationale. |
| Release-only or no distinct merge source delta | 165 | 87 upstream release-bookkeeping rows and 78 merge wrappers; their child changes are counted separately. |
| Test-only rows with no standalone runtime port | 33 | The earlier 21 plus 12 test/fixture-only rows from the bounded test/CI group audit. Test intent may travel with a related feature slice. |
| **Clear runtime gaps** | **32** | 21 older-tail and 11 newly arrived rows are absent or materially incomplete on current `main`. They form fewer coherent implementation slices. |
| Prior `adapted` claim still unverified on current `main` | 203 | A staged branch or old label is not proof of merge. |
| Prior `pending` or `deferred` work needing current decision | 149 | Some may have landed in broad PRs; each still needs a current-main mapping. |
| Plausible historical exclusion needing per-row proof | 46 | Runtime or other files still require current behavior or applicability evidence. |
| Other review rows | 16 | Ten architecture/adaptation reviews, four disputed exclusions, one partially covered cost row, and one reopened Homebrew runtime decision. |

**The defensible lower bound is 32 runtime gap rows, not 875 missing features.**
Another 414 rows remain outside the closed evidence and clear-gap tiers. They
include historical merge claims, likely exclusions, and possible product work;
they are not a 414-feature implementation queue. Issue #149's prior 712-commit count is
stale; the cursor-to-head audit range is 875 at the fetched head above.

The group pass closed 133 rows without a feature port: 78 nonmerge commits
change only upstream `CHANGELOG.md`, `version.env`, or `appcast.xml`; 20
nonmerge rows change only `Tests/`; one previously covered test row has no
standalone runtime delta; and 34 merge commits have no runtime source in their
remerge resolution. Each ledger row records its exact path evidence. A merge's
child commits remain separate ledger rows. This path rule deliberately leaves
46 plausible exclusions open because they touch runtime or other surfaces.

A bounded review of the 19 unresolved `tests and CI` group rows accounted for
16 more: four behaviors already represented by current-main PR #192, and 12
test or fixture changes without a standalone runtime port. Three remain open:
OpenCodeGo production accumulation, a Homebrew release retry, and Python
runner containment. The ledger records the distinct reason for each.

### Fixed-cut execution

Hold this catch-up pass at `bd77ea6a7b35c8e3b66d46285f718c8eebf285b7`.
Newer upstream commits belong to the next pass; they do not enlarge this
acceptance set while fixes are under review. The 32 clear-gap rows form 18
coherent slices in five workstreams:

| Workstream | Gap rows | First action |
| --- | ---: | --- |
| Accounting and scan identity | 7 | Reconcile Claude cache/spend and Codex history bounds; PR #200 covered Pi root identity. |
| Credentials, process lifecycle, and security | 13 | Reconcile fresh credentials, bounded validation, teardown, owned child cleanup, and redaction. |
| Provider quota correctness | 5 | Reconcile TypeSafe, Antigravity, Kimi, and z.ai behavior. |
| Plugin and configuration behavior | 3 | Reconcile plugin tab, blank config, and validated cookie sessions. |
| Reporting and widget UX | 4 | Reconcile model labels, persistent menu row, and per-provider widget retention. |

Submit related slices together when they share source and tests. Independent
PRs can run concurrently because the protected branch does not require a
fresh base for its check gate. QuotaKit CI starts four full Mac shards even for
a small Mac-only fix, so one PR per upstream SHA would repeat that cost without
improving the evidence. Keep unrelated or high-risk fixes separate.

Resolve the 414 uncertain rows by their 26 existing `prior_group` values: cite
the current source or merged PR once for a genuinely shared behavior, apply
that decision to its exact SHA set, and list exceptions individually. Preserve
uncertain runtime cases as explicit follow-ups. This is a grouping method, not
a blanket assertion that a branch or PR title proves coverage. Measure progress
by verified slices merged and rows with defensible dispositions.

The 32 clear gaps include Codex sparse-history bounds, Claude Web reset-credit
fallback, partial Pi/Claude spend preservation, Claude cache reuse, TypeSafe
balances, Grok model names, Keychain validation bounds, Antigravity quota
parsing, Kimi/z.ai availability, Agent Sessions teardown,
Antigravity descendant cleanup, Codex credential/plan refresh, app-server
trust, per-provider widget retention, environment redaction, and Notion/ZoomMate
cookie sessions. The ledger carries each SHA and current-source anchor.

Six dirty worktrees are preserved as source inventories. Their distinct
candidate slices include Kimi/CommandCode quota data, plugin cookie sources
and OpenCodeGo console fallback, Codex scanner performance residue, and
account-switcher label redaction. Several branch stacks duplicate merged
behavior or each other; 118 unmerged local branch refs collapse to 40 terminal
tips, and neither number measures missing upstream features. Apply scoped
diffs against current `main`; do not merge old branch trees wholesale.

### Next accounting and integration sequence

1. Finish the 203 old `adapted`, 149 `pending`/`deferred`, and 46 plausible
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
