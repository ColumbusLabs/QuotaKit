# Upstream clearance goal — 2026-09-29

## Current checkpoint

PR #214 is verified merged as `80dac739a375b3dd6ca54ce2f8e192b3ca2175cd`:
**693 accounted, 59 known gaps, 169 unresolved / 921**. Its required CI passed
and the tested/squashed trees match. One primary worktree remains.

The next candidate implements 14 gap rows and includes 143 original-row source
audits plus focused documentation parity. Its proposed counts are **808 accounted,
73 known gaps, 40 unresolved / 921**, pending exact-head hosted CI and merge.
Implementation and independent review are verified locally; the goal stays active.
Cleanup has removed 27 local and 16 remote branches, leaving 103 local refs and
four origin tracking refs including HEAD. Preserve the remaining unique source
until its applicable behavior is integrated or specifically dispositioned.

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
