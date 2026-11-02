# Upstream integration: November 2, 2026

Completion and verification status: [authoritative issue #266 record](https://github.com/ColumbusLabs/QuotaKit/issues/266). This design is done only when that record confirms exact-head hosted qualification and merge.

Range: `5f93dc3068b3bee3f8753f3772614cc2949c335d..897bff31731bb4b21b105f6e8bf4c32a8a8bf095` (58 reachable commits, 48 non-merges).

Adopt useful provider, Mac product, dependency, CLI, test, and localization work. Adapt fork-owned verified cost accounting, optional OpenCode history, per-account privacy and process ownership, shared wire compatibility, and appended mobile quota subscriptions. Preserve all existing provider IDs, QuotaKit public identity, appcast and distribution ownership, CloudKit/App Group identifiers, entitlements, and version/build metadata.

OpenDesign extends the registry from 110 to 111. Mobile notifications append its ID without changing existing zones. New plugin decoration fields must fail soft when an older client cannot decode them. Dropped CloudKit snapshot saves may retry, while delayed old callbacks must not confirm a replacement payload. Reset reminder preferences default off and recheck current account/privacy before delivery.

Source review and hosted CI are required before the cursor advances. Local builds, test suites, live accounts, Keychain/browser imports, and CloudKit mutations are excluded. No binary distribution is authorized. Per-commit disposition and final qualification belong in `docs/upstream-sync-2026-11-02.md` and issue #266.
