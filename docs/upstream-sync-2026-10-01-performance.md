# Upstream performance integration — 2026-10-01

Pinned range: `2ef5bb6305dda4570d8d080f348cf76a45a392bd..2e4633073aa8e2bbb06c5563e02e61e44370c92f` (12 commits, no merges).
QuotaKit base: `90d939e773c109d96975d1ec5e5247f876d37564`.

## Design and fork constraints

Adopt the complete upstream performance train as one QuotaKit-native batch. Keep provider boundaries, persisted paths, report/window ownership, cache invalidation, recovery receipts, timestamp interpretation and Mac-to-iPhone data contracts unchanged. Cache/persistence work requires independent adversarial review and regression coverage. Final producer hashes are generated from QuotaKit source; upstream hash values and upstream release bookkeeping are not imported.

- Process classification: reuse string basenames and lazy arguments while preserving QuotaKit's resolved-executable priority and ChatGPT app-server bundle/symlink ownership checks.
- Local day keys: bounded time-zone calendar/day memo; exact date-key parity, DST boundaries, signed formatting and concurrent eviction fixtures.
- Pricing: provider-local identity index and normalized lookup memo; unchanged catalogs keep their stamp while a validated sidecar records freshness. Changed catalogs retain atomic replacement and last-valid-cache recovery.
- Codex: reuse stable cached paths, SQLite discovery within each enrichment operation, and enumeration metadata; preserve file identity, missing/replacement handling, cache receipts and completeness.
- Claude/Vertex: reuse ordered reconciliation and encoded persistence identities, and skip impossible Vertex classification. Preserve QuotaKit's compact artifact wrapper, keyed report memo, source recovery, window certification and eviction policy. Advance the native Claude producer generation from v13 to v14 as required by the parser-version gate, preserve prior-generation artifacts, and keep Vertex generation v7.

The mobile project consumes `Shared` rather than SwiftPM `CodexBarCore`. This train changes local Mac/core implementation while preserving synced payloads and identifiers. Existing hosted path gates own Mac/core checks; no iOS/shared contract change is introduced.

## Commit accounting

| Commit | Disposition | Representation |
| --- | --- | --- |
| `f8ecbff50d7670a72ad8382e8b1b56d52965bcab` | Adapted | Process basename and lazy argument path, with QuotaKit executable/ownership safeguards. |
| `d97dfdeb77c60ca6e5e57a4631dca24ec3791d00` | Adapted | Indexed provider-local pricing merge and regressions. |
| `a2a088b635468032a6c3b4b6521310181e1fb53b` | Adapted | Gregorian/day-key reuse and callers; fork key normalization retained. |
| `4c9e083177204e7262bdec68926705599de57c4f` | Adapted | Codex cached-path reconciliation without redundant probes. |
| `4b0bda1324e1467278dde6b749207e86cfc64794` | Adapted | Per-call SQLite title database discovery reuse. |
| `25888a0ff7a5fead0893f2cb193e39e074eac4ff` | Adapted | Codex listing metadata/path reuse and identity regressions. |
| `958494057ba2b10cee7509506083c84f27ddebc1` | Adapted | Claude reconciliation reuse; fork report semantics retained. |
| `74c0d6d78ff737855bde344c0ab2e4be0c8de18d` | Superseded by final QuotaKit regeneration | Intermediate upstream parser hash is not applicable to the fork's producer tree. |
| `3a0467f0d58003b1b9fbcaf386222bff8e1ae4a7` | Adapted | Vertex classification precheck with escaped/root/request fixtures. |
| `455203d8e2710f6c14cef49bbcc411cd3e10a324` | Adapted | Claude persistence identity reuse; fork cache versions and recovery preserved. |
| `643dd0e795ee9df30cecc5ea11220134b1579571` | Adapted | Identical pricing refresh stamps and report-memo parity. |
| `2e4633073aa8e2bbb06c5563e02e61e44370c92f` | Adapted generated artifact | Regenerate with `Scripts/regenerate-codex-parser-hash.sh` from the final QuotaKit sources. |

Each product commit's upstream CHANGELOG text is represented by consolidated QuotaKit Unreleased wording; upstream release/version sections are omitted. No eligible product slice is rejected or deferred.

## Verification and delivery

Source review, independent adversarial review, and cheap static checks precede one complete hosted CI cycle on the final reviewed PR head. Required lint, Mac shards, Xcode compatibility build and Linux portable checks must pass before exact-head merge. No local Swift/Xcode build/test, provider credentials, Keychain UI, cookie import, live CloudKit writes, packaging or distribution.

Before workflow-triggering actions, live public repository visibility, standard GitHub-hosted runners and the existing $0 Actions budget with Stop usage enabled are checked. No paid settings or spending/storage limits change; dependency/cache keys remain unchanged.

Static source review verified moved provider-architecture anchors without changing their provider fingerprints or reasons. Independent adversarial review covers process ownership, calendar parity, pricing precedence/freshness, persistence identities and Codex reconciliation/selection. Synthetic tests exercise these behaviors; expensive benchmarks remain opt-in. Hosted results and the verified merge are recorded on the integration PR and automation memory after delivery.
