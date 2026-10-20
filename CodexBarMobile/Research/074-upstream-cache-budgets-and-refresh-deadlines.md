# Upstream cache, budgets and refresh deadlines

Status: implementation complete. Hosted qualification, final done status and merge evidence are maintained in [issue #254](https://github.com/ColumbusLabs/QuotaKit/issues/254).

## Approach

Integrate all applicable intent from upstream `59a7d46ac..e59282ece` as targeted QuotaKit-native adaptations, with per-commit accounting in `docs/upstream-sync-2026-10-20.md`.

Keep Claude persistent writes incremental while retaining root/account isolation, unreadable-source cache protection and complete historical totals. Contain hidden Codex dashboard work at refresh deadlines without replacing verified API usage with unrelated account data. Vercel budgets stay opt-in and use existing provider/config/sync seams; preserve the complete provider catalog. Menu labels and local-only session discovery use persisted backward-compatible settings. Provider fixes, TypeSafe geometry, ILS estimates and raw CLI IDs retain existing public identities.

## Verification

Obtain independent adversarial review of persistent data, authentication/cancellation, provider/config and workflow changes. Require all applicable exact-head hosted checks. Local work is source/static review, documented generation and pinned formatting only. No local automated test/build/lint suites or live credentials/accounts/Keychain/CloudKit probes. Release metadata/appcast/distribution remain unchanged; source-only CLI workflow improvements are not dispatched by this integration.
