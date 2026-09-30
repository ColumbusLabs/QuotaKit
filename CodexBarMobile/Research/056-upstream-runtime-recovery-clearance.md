# Grouped upstream runtime recovery

Status: done for implementation and focused local verification — required hosted CI and merge pending

## Scope and design

Continue the clearance goal after frozen PR216 using one shared primary checkout
and disjoint implementation ownership. Preserve QuotaKit identity, schema6,
account ownership, source selection, cancellation, fairness, versions and cursor.

- Cost scanner/store: row149 skips raw history for fresh files, with explicit
  unloaded counts, receipt/stamp-bound strict hydration, alias-before-move and
  direct-parent handling. Unloaded/stale/cancelled histories must never become
  empty replacements. Memory/read work47/311/465 remains open for a following bounded slice.
- Codex56: fixed first-failure reason codes for admission, evaluation and
  persistence, preserving every decision and persisted candidate shape. Log only
  approved aggregate fields; storeRequested does not mean durable storage.
- CLI413/486/547/205: full provider history without clipping, SSH freshness,
  known empty30-day totals and explicitly requested Claude cost breakdown.
  Preserve per-source failure and unknown-usage semantics for any grouped AGY work.
- Provider188/470/849/617/847: optional analytics containment, structured
  balances, unknown quota shapes, credential recovery; Console/prepaid row485 remains open.
  Kimi monthly exhaustion uses a provider-declared blocking quota and shared
  metric projection; raw snapshots and the monthly row remain authoritative.
- Mac202/370/665/695/797: visible tinted cards, guarded placeholder closure,
  layout option cleanup, bounded startup diagnostics and persistent refresh text.
- Root842/861: JSON-whitespace-only configuration is absent, with nonempty invalid
  JSON still protected; nonisolated off-actor teardown cancels tasks before
  releasing its assertion, preserving task-field actor isolation.
- Release475/572: validated transport switch applies to both notarization ZIP/DMG
  submissions. Downloaded app verification requires configured QuotaKit bundle/team
  and a strict all-architecture Developer ID signature, after asset presence.

## Verification plan and boundaries

Freeze all writers before one integrated focused build/test run. Include receipt,
load/save/reopen, stale/cancelled hydration, fork/alias and parser-adoption fixtures;
privacy sentinel and admission parity fixtures; stubbed CLI/provider transports;
monthly blocker/unknown/expired model cases; placeholder/watch diagnostics; blank
config, off-actor release and signature-gate fixtures. The portable SQLite priority suite lives in TestsLinux so both Mac and Linux
targets include it. Refresh only affected exact architecture anchors, then scoped/full required lint and independent reviews.

Release tooling fixtures use fake transport, unpacking and codesign commands:
valid, missing asset/app, symlink, download/signature rejection and missing/invalid
expected signing team. The validated S3 option cases cover default,0,1 and rejected
values for both submissions. These tests do not prove a real released artifact's
signature. No product release, real signing/notarization, live provider, browser,
Keychain, SSH probe, installation or relaunch is part of this slice.

Rows remain open until source behavior, relevant checks and required exact-head
CI/merge are verified. The prior candidate has860 accounted/60 known gaps/1 unresolved
of921; this document does not advance those counts. Cleanup proceeds from verified
source and recoverable exact-head evidence, not commit ancestry alone.

## Recovered branch documentation

Recover the six-line inherited counter-origin explanation from the audited
intermediate branch. It describes already-present fork subtraction and conservative
reset containment; this is documentation recovery and grants no extra ledger credit.

## Local verification and repairs

All originally planned focused filters passed across affected-only runs, covering
42 suite names (including the added process/drain checks); no whole local package
suite ran. Thirty suites passed in the first completed build, including39 portable
tests. Later runs verified the remaining providers, monthly-blocker projection,
status/settings/config/teardown and process paths.

Actual driver fixtures exposed a renamed-path retry that deferred itself forever
after successful old-key hydration. Removing only that redundant deferral allows
receipt-validated history to rekey before its forced parse; unavailable/stale and
existing-target protections remain. Independent source review and every actual
driver case passed: warm zero raw-history reads, one-file append, unavailable force
and rename retries, deleted aliases in ordinary/app catch-up modes, malformed
details with positive/zero token histories, released receipts, cancellation and
newer retry requests surviving an older commit. Schema remains6; generated parser
hash is5709a6e4c9c0f7cf, retaining only published predecessor7607317f30850961.

Failure-time file/token/usage comparisons retain exact opaque byte equality. A
successful full reparse may reorder JSON object keys, so post-success assertions
compare path, row index and all decoded usage-row fields instead. No data field or
physical row identity assertion was removed. Moved architecture anchors were
refreshed with exact reference fingerprints; the new opt-in Claude breakdown has
a narrow provider-owned justification, while blocking-quota projection remains
generic.

PR216’s native pipe CI repair is inherited here. Its first proposed Foundation
throwing-read variant was rejected after the actual short-open-pipe fixture and
stack sample proved blocking. The final bounded nonblocking POSIX reader passed
synthetic EBADF/prefix/non-EOF and existing subprocess/shell output cap, drain,
timeout/cancellation and cleanup fixtures. Required exact-head CI remains the
delivery gate; no live provider, Keychain, SSH, real signing or app relaunch ran.
