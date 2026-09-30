# Upstream cost, provider and maintenance clearance

Status: done — included in verified PR #216 merge 7b6935bfdfd109fe4bfb49e7c1e1402f2ae303b2, exact-head CI36701444039; retained by the final PR #217 delivery.

Delivery record: see the [current reconciliation](../../docs/upstream-backlog-reconciliation-2026-09-28.md). The scope, verification counts, limitations and pending statements below are historical slice checkpoints; the current delivery record supersedes their delivery status.

## Scope and design

Continue the grouped upstream clearance from the PR #215 source cut and final
upstream `25bba9b7fd9ce83c33053958f7366e23b2dc8a82`. This slice changes Mac,
CLI, mobile provider accents and shared infrastructure. It does not prepare a release.

- Parse common RFC3339 cost timestamps through a native path with historical
  formatter fallback. Preserve day, fractional precision and offset behavior.
  Validate incremental token timestamp ordering at the append boundary and delta;
  unknown prefixes and reordered replacement/fork generations still need full
  validation. Retain cancellation, scan budgets and resume checkpoints.
- Workspace reports read priced rows and aggregates without materializing token
  history. Normal Store reads retain full histories, and omitted histories stay
  distinct from empty histories. Do not treat this as per-file scanner hydration.
- Hugging Face browser wallet access is opt-in and default-off. Keep inference
  allowances separate from money. Bind browser billing to a single matching user
  identity, preserve incomplete/no-data states, and keep bearer credentials out of
  cookie-only requests. Use provider-owned configuration and settings hooks.
- Linux Devin manual credentials use the same resolver and validity policy as
  fetching. Only that supported source can bypass browser availability checks.
- Bound shell discovery output while draining subprocess pipes; reject oversized
  or truncated data. Preserve termination, cancellation and timeout behavior.
- Reject unrepresentable Codex OAuth numeric reset values without trapping; retain
  field aliases and safe truncation semantics for ordinary finite values.
- Apply the same numeric boundary to RPC spend controls. Antigravity CLI uses its
  local login and rejects saved-account overrides; implicit CLI reads omit saved
  OAuth account labels. Preserve saved labels separately from provider identity.
- Provider reordering retains unavailable plugin settings and secrets. Descriptor
  replacement updates every registry view without changing insertion order or
  the manifest bootstrap lifecycle.
- Compact account rows apply the provider's reset-display policy to each visible
  window while retaining all window headroom for ordering. Preserve privacy,
  stale-reading labels, accessibility and expansion state.
- Adopt verified provider accents on Mac and iPhone, preserve the established
  widget colors, and record explicit decisions for retained fork accents. Keep
  adaptive mobile contrast behavior and the existing release-notes version.
- Convert provider RGB literals without changing their values. Align compatible
  dependency constraints and root/widget locks while preserving fork dependencies.
  Pin checkout revisions and require Xcode 26.3 test compilation for relevant CI.
- Correct documentation against the fork's supported public distribution policy.
  QuotaKit's manual CLI artifact workflow is not a public musl release lane;
  remove unused SDK settings and unsupported archive promises. Keep its supported
  manual glibc/Mac packaging and existing signing-team policy.

## Acceptance and completion

Use focused timestamp/scanner/cache, provider plugin, credential, bounded capture
and numeric parser fixtures, plus synthetic workflow/script checks. No real
accounts, browser import, Keychain access, app relaunch or release is required.
Run relevant format/lint/build checks and focused tests once source writers finish,
then required exact-head hosted CI. Review account identity and process boundaries
independently. Mark this record done only after implemented behavior is verified.

Focused Mac verification covered 361 tests, followed by 111 affected tests after
fixture and widget-color repairs, then 94 CLI/registry/architecture tests. Independent
review found and corrected implicit Antigravity CLI account labeling; its affected
43 tests passed. Package resolution, the CI path-gate script and synthetic
process-group cleanup passed. The focused iPhone palette suite passed all 8 tests.
Full lint passed across 2,627 files, with focused format/lint checks after the final
registry and CLI fixes. Required hosted CI and merge remain pending; these results
do not establish a released app.

Preserve all 921 SHA rows and the first twelve historical ledger columns. Credit
implemented rows only with tested source evidence; source decisions and historical
merged re-verification are recorded separately. Report merged and candidate counts
separately, update issue #149, and remove completed branches after verified merge.
Reconcile unique unfinished branch contents before deletion. Keep the monitor
cursor unchanged until the entire upstream goal has fresh closeout evidence.
