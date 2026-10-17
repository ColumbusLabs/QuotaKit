# Upstream spend, providers, and account pools

Status: implementation complete. Hosted verification, done status, and the final merge receipt are maintained in [issue #250](https://github.com/ColumbusLabs/QuotaKit/issues/250), the authoritative completion record.

## Scope and design

Integrate upstream `f50cd6cee4db4e96e4823a51f74eb462a56bbb66..6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e` from current QuotaKit origin/main. Preserve all 104 existing provider identifiers and add Future AGI and Munito with QuotaKit-owned manifests, settings, iPhone sync metadata, and assets. Keep Gemini browser-account quota windows distinct from CLI quotas.

Adopt menu spend items and persisted layout migration, user-plugin overview/gauge parity, opt-in local HTTP server management and SSH CLI cache, Claude tcr account pools/forecasts/config-directory mapping, bounded detached test fixtures, and translations. Local Claude directory mappings must not propagate through iCloud; retain receiver-local mappings for existing account IDs.

Preserve QuotaKit identity, paths, appcast, signing/entitlements, shared record compatibility, release versions and build numbers. Reject upstream release bookkeeping and upstream-owned publishing infrastructure; its cold-build and Apple-ticket follow-ups only affect that absent workflow.

## Verification and constraints

All automated lint, Swift builds/tests, and iOS simulator checks run in existing GitHub CI. Use source inspection, diff checks, documented generation, and write-formatting locally. No real credentials/accounts, Keychain UI, browser cookies, live CloudKit, installation, relaunch, packaging, binary distribution, or release publication. Independent adversarial source review is required for account/config/cache, server exposure, persisted menu migration, provider and mobile/shared contracts.

Public repository standard hosted runners are free under current GitHub billing rules. CI uses restore-only caches and no artifact uploads/cache saves. Do not trigger manual release or historical diagnostic workflows. No billing/storage settings changes.

## Completion evidence

The linked completion record is marked done only after independent source review, exact-head hosted checks, and verified merge. Commit accounting: `docs/upstream-sync-2026-10-17.md`.
