# Upstream integration for November 6, 2026

Status depends on exact-head hosted CI and merge evidence in [issue #270](https://github.com/ColumbusLabs/QuotaKit/issues/270).

Bring the pinned 45-commit range into QuotaKit while preserving its provider catalog, credential policies, synced quota identities, and release ownership. Review the [per-commit integration ledger](../../docs/upstream-sync-2026-11-06.md) for scope and the linked WebKit retirement follow-up.

Credential and caching changes use isolated fixtures. Check Claude weekly-only quotas in Mac notifications, menus, and iPhone widgets. Keep Bedrock cache entries scoped by credentials and keep QuotaKit’s verified ledger metadata and historical reconciliation paths. Use current GitHub hosted CI gates and independent review for credential, persistence, and runtime ownership changes.
