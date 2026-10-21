# Upstream widget recovery and cache memory

Status: implementation complete. Hosted qualification, final done status and merge evidence are maintained in [issue #256](https://github.com/ColumbusLabs/QuotaKit/issues/256).

## Approach

Integrate applicable intent from upstream `e59282ece..489aad74f` through targeted QuotaKit adaptations, with all ten commits accounted for in `docs/upstream-sync-2026-10-21.md`.

Use origin-filtered streaming for Devin storage import and immutable record reuse for Claude incremental cache refreshes. Preserve account/source isolation, cache durability, private credentials and the full provider catalog. Antigravity should represent Gemini using measured ordinary quota when available while retaining model-specific windows and existing mobile projections.

Recover stale Mac widget extensions only after app version changes and only after current-user, QuotaKit signing identity, process identity and staleness checks. Preserve widget snapshot JSON, App Group paths and shared/iPhone contracts while simplifying snapshot copies and process helpers.

## Verification

Use fixture/pure-model tests in existing hosted CI and independent adversarial review for credential, persistence, process termination and widget compatibility risks. Require exact-head hosted qualification before merge. Local work is source/static review and pinned formatting only. No live credentials, browser imports, Keychain, CloudKit operations, local builds/tests, app launches or binary distribution. Release metadata and appcast remain unchanged.
