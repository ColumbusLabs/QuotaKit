# Upstream quota, process privacy and pricing clearance

Status: done — included in verified PR #215 merge 64bd8cd644ce7bc82ab98d4084b913f1a4540c79; retained by the final PR #217 delivery.

Delivery record: see the [current reconciliation](../../docs/upstream-backlog-reconciliation-2026-09-28.md). The scope, verification counts, limitations and pending statements below are historical slice checkpoints; the current delivery record supersedes their delivery status.

## Scope and design

This grouped upstream slice changes Mac menus, CLI/shared provider configuration,
and local process/cost infrastructure. It adds no iPhone runtime feature or release.
Source decisions use QuotaKit main `80dac739a375b3dd6ca54ce2f8e192b3ca2175cd`
and final upstream cut `25bba9b7fd9ce83c33053958f7366e23b2dc8a82`.

- Quota burndown uses recorded, account-scoped Codex/Claude reset windows and
  existing series normalization. Keep utilization history beside it. Capture age
  describes old observations; usage is not projected forward.
- Retained process environments use a transparent dictionary wrapper whose
  automatic diagnostics expose only entry count. Execution and optional-value
  semantics remain available. A source guard checks retained declarations.
- Antigravity print probes opt into descendant cleanup. A fresh inherited marker,
  same-user check and process start identity authorize individual signals.
  Revalidate before TERM/KILL; preserve unmarked siblings and existing timeout
  teardown. Linux environment reads are bounded; Darwin parsing stops at the
  environment terminator and cannot use later Apple vectors as ownership evidence.
- Pricing resolves exact provider-qualified models before aliases, preserves raw
  Antigravity report model IDs, and applies historical event-date cutoffs before
  today's catalog. Current bundled Sol rates change with its historical cutoff.
  Preserve compatible parsed rows/checkpoints while recalculating derived reports.
- Azure's API version uses the existing provider-config extension seam. Default
  inherits the environment, v1 retains its existing route, and custom values survive.
- Ollama empty Manual credentials explain recovery. An explicit guarded action
  switches to Auto; diagnostic retries use the same candidate policy as fetching.

## Acceptance and completion

Use deterministic parser/model/config fixtures and synthetic owned subprocesses;
no real provider probes, browser imports or Keychain access. Run focused tests,
strict repository lint and required hosted CI, then verify the merged tree matches
its tested PR head. Document independent review and resolved failures. No full local
suite or app relaunch is required by this slice.

After verification, close the 14 runtime rows and two documentation rows in the
921-row ledger while retaining the first twelve historical columns and exact SHAs.
Source audits of other rows are separate from implemented behavior. Issue #149 and
reconciliation report verified merged counts. Remove the completed branch after
merge; recover unfinished unique branch contents before cleanup. The upstream
cursor and alignment metadata remain pinned until the entire goal is satisfied.

## Verification record

The targeted chart, environment, provider settings, parser and subprocess suites
passed across the integrated run and affected reruns. The final pricing/store
rerun passed 149 tests; the portable ownership suite passed seven tests; an
isolated existing Kimi timing suite passed 23 tests. Independent review found
no remaining findings after the Darwin boundary, Ollama diagnostic retry, and
current/historical Sol corrections. Full repository lint reported zero violations
in 2,616 Swift files; the final two fixture edits also passed focused strict lint.
The generated parser hash is `15a7d46518e83cc0`.

The initial failures were retained in local verification logs. Narrow reruns
corrected stale pricing/cache expectations and exact source-location anchors;
no source guard, process identity authority, or timing budget was weakened.
Required hosted CI remains the delivery gate. Its existing iOS path rule also
matches this research document, despite the absence of iPhone runtime changes.
