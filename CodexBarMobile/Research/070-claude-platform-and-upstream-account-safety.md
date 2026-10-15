# Claude Platform credits and upstream account safety

Status: implementation complete. Hosted verification and the authoritative completion status are maintained in [integration PR #247](https://github.com/ColumbusLabs/QuotaKit/pull/247). The completion record is marked done only after the implemented behavior passes the required hosted checks.

Integrate the nine upstream commits from `052ded413` through `a49c61c30` from current QuotaKit `origin/main`. Claude Platform is an independent prepaid API-credit provider, disabled by default. Add an append-only provider identifier and reuse compatible mobile quota and billing projections, icon and color conventions. Keep all 103 existing providers, notifications and widgets compatible; the wallet has no fabricated quota budget, while actual expiring API/purchased credit grants retain upstream usage lanes.

Adopt OAuth profile-display email fixes without converting an unverified display identity into an organization/history owner. Muse manual consent may earn its credential grant; background access stays noninteractive. Preserve existing provider-scoped browser permissions and persistent configuration. Menu typography is optional and persisted compatibly. CLI concurrency preserves deterministic provider output. Acknowledgements are generated from exact existing dependency pins.

Verification uses independent source review and the existing free hosted Mac, plugin-engine, iOS/shared, compatibility, Linux and aggregate gates. Do not perform live-provider, Keychain, CloudKit, app-install, binary-distribution or local build/test probes. The detailed commit and exclusion ledger is `docs/upstream-sync-2026-10-15.md`.
