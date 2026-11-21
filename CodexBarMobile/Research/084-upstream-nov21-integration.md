# Upstream integration — 2026-11-21

Status: done after independent source verification; hosted merge qualification is tracked in PR #281.

Delivery requires all applicable checks on the exact PR head; the PR and upstream-sync issue #280
are the authoritative hosted verification and merge receipt.

## Design

Port upstream range 1f6da9bec..c94b855f3 onto origin/main 2645b241a,
without merging upstream history. TrustedRouter appends a provider ID; retain
all existing provider order and persisted/synced identities. Reuse existing
mobile balance projection rather than introduce incompatible wire fields.
Notion personal pools/workspace credits use QuotaKit’s native provider architecture.
Codex Ultrafast and reporting-window changes adapt QuotaKit’s verified cost store
and retention model rather than replace schema/history safeguards.

## Boundaries and verification

No release metadata/build increments, appcast/distribution/signing changes or live
provider/Keychain/CloudKit probes. Isolated branch preserves divergent user main.
Independent source review for provider/shared/credential/persistence changes.
Full applicable hosted CI is justified by shared provider catalog, persistence,
dependencies, Mac menu and CLI scope; no local Swift/Xcode suites are planned.
See docs/upstream-sync-2026-11-21.md and integration PR for per-commit accounting.
