# Upstream clearance goal — 2026-09-29

## Current checkpoint

[PR #216](https://github.com/ColumbusLabs/QuotaKit/pull/216) is verified merged as
`7b6935bfdfd109fe4bfb49e7c1e1402f2ae303b2`: **860 accounted,60 known gaps,1 unresolved /921**.
Exact head `caa71f847b013d10d9edf4a75f721e32590499d5` passed every required
[CI36701444039](https://github.com/ColumbusLabs/QuotaKit/actions/runs/36701444039)
gate. The squash tree exactly matches the tested tree; main and origin/main are
synchronized. Its isolated native pipe fix preserves prefix/error/EOF semantics.
Identical-tree post-merge CI36706769713 was cancelled and completion verified.

Runtime-recovery source `778882884196e59cf4ead0a405cd2cadef4df852` has exactly the locally verified
source tree from `c245ec6a0d0a4e19e2c53e564f0495f6896b0be9`. It closes20 concrete rows in its candidate:
**880 accounted,40 known gaps,1 unresolved /921**. All planned focused filters
passed across42 suite names in affected-only runs; full lint passed with zero
violations across2644 files plus locale/parser/package/release-helper gates.
Publication and required exact-head hosted CI remain delivery gates; this candidate
is not a verified merge. The next wave is active on the primary checkout for the
remaining41 rows and applicable fresh-tail behavior with GPT6 Luna max owners.

A safe upstream refresh found nine additional objects through
`5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f` (930 observed total).
Those nine are audited separately and receive no ledger credit here. The monitor
cursor remains `cf79d1310493f2d028af62cc21e422b5f33c70a5`.

Cleanup removed **118 local and19 remote refs**. **15 local branches and one
primary worktree** remain before this publication. Fourteen source-covered
intermediate branches and PR216's slice branch were retired with expected-OID
checks, complete source audits and a verified self-contained recovery bundle.
Unique unfinished work and unrelated battery work remain protected. No full local
suite, live provider/browser/Keychain/SSH probe, product release, app relaunch or
product-version/cursor advance ran.

## Finish line

The user authorized a persistent goal to clear all upstream work and remove
unnecessary worktrees and branches, cleaning as each slice finishes.

Completion requires:

1. Every upstream row from monitor base `cf79d1310493f2d028af62cc21e422b5f33c70a5`
   through a freshly verified final upstream head has a final, evidence-backed
   disposition. Every applicable missing runtime behavior is implemented,
   verified, and merged. Exclusions need specific fork/applicability evidence.
2. Refresh upstream again before closeout and reconcile any intervening commits.
   Advance the monitor cursor and upstream-alignment metadata only after this
   condition is met. An empty raw counter is not proof of product equivalence.
3. Remove completed side worktrees and local/remote branches after an audit of
   their exact heads, PR state, dirtiness, unique commits and net behavior.
   Recover or integrate unique unfinished work; do not discard unrelated work.
4. Keep clean synchronized main, the ledger, reconciliation and issue #149
   consistent with verified merged evidence. Report remaining counts and next
   slice at each closeout.

A product release, installation, live account probe, or Keychain prompt is not
part of this goal. Required focused checks and hosted CI are authorized.

## Working method

Use bounded grouped slices. The main agent owns framing, source decisions,
integration, review and delivery. Prefer GPT-6 Luna at max reasoning for
independent bounded source audits and implementation. Share one required CI
cycle per integrated runtime batch, run focused local tests, and use the
existing documentation gates for source-only audits. Stop redundant post-merge
CI only after verifying that its tree equals the exact tested PR tree.

Clean as work closes. A squash merge need not make a branch an ancestor of main:
verify exact merged PR heads, contained source changes and later source
supersession. For dirty inventories, preserve a recoverable snapshot before any
removal and reconcile every applicable unique change into the ledger.

Keep the two broad upstream automations paused during this consolidated goal.
Do not restart per-commit automation alongside these batches.

## Audited range and fresh inventory

- Original fixed cut: `bd77ea6a7b35c8e3b66d46285f718c8eebf285b7`, **875 rows**,
  tracked in the [original ledger](upstream-backlog-ledger-2026-09-28.tsv).
- Newly refreshed head: `25bba9b7fd9ce83c33053958f7366e23b2dc8a82`.
- [New tail manifest](upstream-backlog-ledger-2026-09-29-tail.tsv): **46 rows**
  (27 nonmerges and 19 merges), individually source-audited in the first goal slice.
- Combined inventory: **921 rows**. The original SHA and historical fields
  remain intact; the tail uses the same 16-column schema and ordinals 876–921.

The initial verified implementation baseline was PR #212's squash merge
`ac6c4c966f6012fffbc3144d40271b01a7646dfe`. Counts and cleanup state at each
subsequent slice live in the
[reconciliation](upstream-backlog-reconciliation-2026-09-28.md).

## First goal slice

The first goal slice audits 72 rows: the 26 unresolved `Mac UX and reporting`
rows and the 46-row refreshed tail. That slice's combined accounting was
**670 accounted, 65 runtime gaps, 186 unresolved / 921 total**.
The older Mac UX rows yield 18 represented decisions and eight gap/partial rows.
No runtime behavior changes in this source-accounting slice.

Next, implement Mistral Monthly Plan picker/billing fixes as a grouped batch,
then continue the remaining runtime work and source audits until the finish line
is verified. Worktree and branch cleanup proceeds alongside these slices.

## Initial cleanup completed

Twelve unattached local branches and nine existing remote branches were removed.
Every exact head matches a merged PR head, its merge commit is on current main,
and no branch is attached to a worktree. Remote deletion used expected-OID
leases. A private 5 MB recovery bundle was verified before removal; the per-ref
heads, PRs and merged commits are recorded under the primary checkout's
`.git/upstream-cleanup-recovery/2026-09-29-completed-refs/`.

A duplicate clean checkout (`upstream-next-bulk`) and its branch were then
removed after exact tree comparison against the retained `upstream-direct-fork-port`
checkout and a separate verified recovery bundle. Neither checkout had dirty or
ignored files.

Fresh counts after those removals: 115 local branches, nine origin tracking refs,
and 11 worktrees. Remaining checkout and unique-change reconciliation is active;
these inventories are not an instruction to preserve completed work forever.

## Side worktree recovery and removal

All ten remaining side checkouts were removed after recovery verification, leaving
**one primary worktree**. Four were clean and six had tracked text changes; none
had untracked files. Their branch heads remain available while source disposition
continues. This removes redundant physical checkouts without claiming that all
of their source changes are merged.

The private recovery directory
`.git/upstream-cleanup-recovery/2026-09-29-side-worktrees/` contains a verified
bundle of all ten exact heads, per-checkout staged and unstaged binary-capable
patches, SHA-256 inventory proofs, and restoration instructions. Every patch pair
was checked and applied in staged-then-unstaged order against its exact saved
HEAD using an isolated temporary Git index before any removal. The working
source and real index were not used for those recovery checks.

Only two rebuildable cached lint binaries were omitted from the side snapshots.
Primary `.build`, `QuotaKit.app`, local settings, provisioning profiles, Xcode
state and release artifacts were outside the cleanup. Fresh state is one primary
worktree and 115 local branches. Branch/source
reconciliation continues until the goal's finish line is verified.

## Additional remote cleanup

Four more remote branches were removed after exact merged PR-head and main
merge-commit verification, expected-OID deletion leases, and a verified private
recovery bundle under `.git/upstream-cleanup-recovery/2026-09-29-remote-merged/`.
Later, unmerged local heads on similarly named branches remain preserved. Total
cleanup is 13 local and 13 remote branches; the current origin inventory has
five tracking refs, including `origin/HEAD` and `origin/main`.

## Mistral and security/persistence slice

The next runtime/source slice implements six Mistral picker and billing gap rows
and resolves all 17 security/persistence audit rows. Combined accounting becomes
**693 accounted, 59 runtime gaps, 169 unresolved / 921 total**, with exact SHAs
and historical fields preserved. Independent review and 156 focused tests passed;
required hosted CI is the delivery gate. The separate monthly/daily category
rules were preserved, not counted as another fixed feature.

Provider contracts, quota correctness, catalog/architecture and provider additions
are the next independent source audit groups, using the pinned tested code commit.
One worktree remains; cleanup now totals 14 local and 14 remote branches, including
PR #213's temporary branch. Continue cleanup as each subsequent slice closes.

## Quota/process/pricing/provider slice

Code candidate `773099859e5beed780f3b6b8bb401496a5efeb3c` covers recorded quota burndown, retained-environment diagnostics, owned probe cleanup and bounded parsing, reserve/product aliases with historical/current pricing, Azure version settings and Ollama recovery/diagnostics. Focused checks, strict lint and independent reviews passed. Required hosted CI includes Mac and the current research-document-triggered iOS gate. See the current reconciliation for exact rows, counts, check limits and verified recovery directories.

Nine more completed local snapshots were removed after semantic source/test/doc review and a verified private bundle. The unfinished cost/Codex snapshot remains for performance parity and branch-specific source decisions; branch cleanup is not evidence that those changes were implemented.

## Combined final verification checkpoint — 2026-09-30

PR #217’s Recovery20 exact-head CI passed lint, Linux, iOS and macOS compatibility, but Mac shards exposed a locally reproduced stack overflow during fork-history hydration and redundant alias lookups in warm scans. The obsolete remaining run was cancelled. A dedicated history-hydration thread prevents a synchronous actor-queue hop from reusing the parser’s nearly exhausted stack; a per-job autorelease pool bounds temporary Foundation objects. Status-only reads avoid duplicate identity reconciliation, and warm scans reuse one alias snapshot. These changes preserve receipt, parser, schema, path-moved and retry guards. The POSIX identity helper alone did not resolve the crash. The scanner edit updates the generated parser hash to `c52728bbaeedeb90`; the prior published `7607317f30850961` compatibility path is retained, with no unmerged intermediate producer whitelisted.

All 41 original-cut rows remaining after Recovery20 map to the integrated final wave. The combined source remains uncredited until coordinated focused tests, lint, exact-head hosted CI and covering merge pass. Extend #217 with this integrated wave and the reviewed nine-object fresh tail, then perform one required CI matrix. Merged credit remains 860/921; 930 objects have been observed. There is one worktree and 15 local branches.

### Integrated runtime verification

All product modules and the full test bundle compile. Subsequent affected-only runs pass fork source recovery, executor isolation, physical-row read semantics, the 512-visit catch-up bound and warm-scan performance. Account/plan reset-credit admission and warning/widget ownership regressions pass after the reviewed repairs. The native hooks fixture verifies editable empty fields, AX roles/prompts and unchanged bindings; offscreen hosting cannot establish onscreen VoiceOver names. The remaining checks are one architecture anchor and the OpenRouter widget fixture, then final lint and the required exact-head hosted matrix. Candidate rows receive no merged credit until that matrix and covering merge pass. A fresh upstream fetch still reports the same 930-object head.

## Frozen final candidate

Source `57c46c3d6dbe7e534169e592bd95fdf601b5d941` exactly matches the locally tested tree. All83 planned focused filters and affected widget/reset/native/plugin checks pass; full lint and independent delta reviews pass. PR217 now carries Recovery20 + final41 + fresh9 with candidate930/930 accounting, zero missing applicable implementation and zero unresolved rows. First12 historical fields remain unchanged for all existing921rows. Candidate implementation evidence is separate from merged860/921credit. Required exact-head hosted CI, covering merge, recoverable retirement of remaining old refs, final upstream refresh and cursor/tracker closeout remain the delivery steps. No product release is requested.

The final candidate prepares the monitor cursor at the fully reconciled `5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f`. Active main remains at the earlier cursor while CI runs; branch protection and the verified covering merge make activation atomic. Shipped-upstream alignment and product/build versions remain unchanged.

### Portable retirement fixture repair

The first combined hosted run found an obsolete Linux-only Crof credits fixture referring to removed runtime types. It is replaced by Core-only opaque-history/config/catalog compatibility checks that also run on Mac. Both new tests pass locally; no production source changed. Superseded runs were cancelled before another matrix; the covering exact-head gate remains pending.

### iOS retirement fixture repair

Both hosted Linux architectures and lint pass after the portable fixture repair. Hosted iOS exposed stale Crof/provider-count expectations in `QuotaProviderListTests`; the fixture now checks 71 active providers, 213 subscription zones and readable historical Crof zone names. Production source remains unchanged. All 33 provider-list tests pass in a private macOS harness with byte-identical shared source and only the unused app-module import removed. All Mac diagnostics are collected before publishing the combined fixture repair; required exact-head CI and verified merge remain pending.

### Full-matrix fixture audit

All four Mac shards exposed stale provider retirement/count, decoration, account-label, safety-source-anchor, logout-revision and enabled-widget fixture expectations. The run is terminal with no timeouts. All 20 affected suites have latest passing focused evidence across a 233-test/20-suite batch and the affected 20-test/3-suite rerun. Production source remains unchanged; all scoped format/lint checks pass. The repaired head is prepared for one complete required matrix. The prior Claude web fixture missed the uncached request client and allowed synthetic placeholder-cookie CI requests to escape; the replacement TaskLocal transport captures both clients without account credentials. Required repaired-head CI, covering delivery and recoverable branch retirement remain pending.
