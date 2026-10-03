# Independently verified Codex daily spend

Status: done
Date: 2026-10-03

## Failure and endpoint

The installed Mac serialized an overlapping Codex day at $0.552216 and
522,908 tokens while newer local aggregates accumulated. Whole-history
coverage ranked legacy summaries above partial scanner reports, blocking the
day on Mac and again in iPhone reconciliation. Fresh quota and payload dates
did not establish freshness of those retained daily values.

The whole-window precedence was introduced in `1ed1dae31` on August 13,
2026 to preserve complete history during reindexing. It also retained every
overlapping daily value against partial reports. The installed Mac and current
base shared that merge implementation; this was a latent boundary gap exposed
by catch-up, rather than a recent removal of the history protection.

The endpoint is repeated verified daily updates through both outgoing sync
transports, warm and cold iPhone caches, persisted summaries, the optional Cost
Ledger, and both spend views, without dropping retained historical data.

## Contract

- Source completeness and pricing completeness are independent.
- A daily proof carries source kind, nonidentifying source scope, persistent
  ledger lineage, monotonic revision, and verification time.
- SQLite persists proof and compact aggregates in one transaction. Existing
  stores migrate additively; historical rows do not gain invented proof.
- Same-contribution newer revisions replace a day, including decreases and
  explicit zero days. Equal or older revisions are idempotent.
- Unsupported or malformed proof cannot gain authority. Partial omissions are
  no-ops. Omitted proofed days inside complete bounds require explicit zero
  evidence before deletion; expired days may leave a complete moving window.
- A fresh complete bounded baseline may adopt a new source scope or lineage
  within the caller's same device/provider/account lane. Incomparable partial
  revisions cannot do so.
- The source inventory, relevant file anchors, parser completion and unsettled
  forks remain verification requirements. Current-day proof does not require
  replaying all historical session bodies.
- Local Codex estimates take precedence over dashboard fallbacks for local
  days. Dashboard charges are not added to that estimate or borrowed as proof
  of resolved local pricing.
- Reconcile individual device/account contributions before adding distinct
  Macs. A combined point cannot claim one contributor's proof.
- Unknown pricing may retain prior known dollars only as an unknown lower
  bound while verified tokens advance.

## Persistence and compatibility

The wire adds optional Codable day evidence inside existing opaque payloads;
it adds no CloudKit record fields or indexes. Mobile Cost Ledger proof uses a
versioned, delimiter-safe encoded marker in its existing sourceRevisionKey,
avoiding a SwiftData schema change or cache deletion. All point reconstruction,
cache identity and daily freshness paths preserve the contract.

## Verification and delivery

Focused regression gates cover repeated overlapping-day increases, yesterday
corrections, zero/decrease, unknown pricing, omissions, ordering, migrations,
restart-safe revisions, account/root/lineage isolation, inventory/fork gates,
30/365-day windows and rollover. Mobile gates include warm/full/delta/replay,
cold hydrate and persistence/relaunch, two Macs, and Cost Ledger on/off.

Run repository lint, relevant Mac builds and the required iOS release test
gate. Independent review must resolve blocking findings before publication.
Deploy the iPhone reader before the Mac producer; verify processing and tester
availability independently of upload success. App Store approval and actual
phone installation are separate outcomes. Verify the published Mac artifacts,
appcast and installed bundle, then observe its outgoing day proofs over normal
refresh cycles. Do not use raw unverified rows as the publication oracle.

## Current release context

At investigation, public Mac was 0.32.4.31 and App Store iOS was 1.11.2;
TestFlight had 1.11.4 build 178 in the internal Team group. The phone's install
channel was later confirmed as App Store. Delivery is authorized for TestFlight
first and a full Mac deployment. The user explicitly prohibited App Store
submission; no App Store version, review submission, or public iOS release may
be created as part of this task.

## Verified implementation

- The final six Core regression suites passed 192 tests; the subsequent
  cold-empty projection change passed all 38 cache snapshot tests.
- Shared reconciliation, both outgoing transports, and Mac publication
  regressions passed in the coordinated focused run.
- The full iOS simulator release gate passed 787 tests, with no failures or
  skips, on iPhone 17 Pro with iOS 27.
- Repository lint and localization audits passed. The final cold-empty change
  additionally passed scoped formatting and strict lint.
- Independent review resolved the reconciliation, persistence, freshness,
  inventory, buffered-parser, and cold-zero findings. Production CloudKit
  schema verification passed; optional payload evidence needs no schema field.

The existing navigation smoke renderer crashed on the unchanged base under
iOS 27. Rendering through an attached UIKit hosting window repaired that test
fixture, and the full simulator gate then passed. Delivery and post-deployment
observations remain separate from these implementation checks.
