# Upstream history and account editing

Status: implementation complete. Hosted qualification, done status and the verified merge receipt are maintained in [issue #252](https://github.com/ColumbusLabs/QuotaKit/issues/252).

## Approach

Adapt upstream `6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e..59a7d46ac61338786e5d32d8324a3e414525e601` onto QuotaKit origin/main. Keep the entire 106-provider catalog and all existing identity/sync/release contracts.

Saved token edits preserve UUID, metadata and active selection; blank replacement leaves the credential intact and editing a dormant account cannot activate its source. Reordering resolves active selection by UUID. Overview optionally expands cached accounts without fetching, borrowing another account's quota or revealing labels against privacy settings.

Claude history includes Cowork direct JSONL logs while retaining account-config directory isolation. Existing unreadable roots must fail before replacing valid cached history; missing files during enumeration are normal churn. Auto CLI follows the active swap account only without an explicit source/account override; labeled fallback retains the real fallback account identity.

Pi retains unsupported backend token history as unpriced local history and uses order-independent source fingerprints. OpenCode Go uses configured app source and its bounded local reader for CLI cost history. Preserve the documented 365-day Available year selection; explicit longer reader requests are covered separately. Plugin selection retains full instance identity; optional row severity and validated, bounded monochrome SVG icons remain Mac-local. Grok CLI billing and Codex dashboard are adapted to existing fork APIs.

## Verification

Independent adversarial source review and the exact final-head existing hosted CI are mandatory. Use no local automated Swift/Xcode/build/test/lint suite, real credentials/accounts/cookies/Keychain/CloudKit or binary distribution. Current public standard-hosted CI is free, restore-only and adds no artifact/cache storage. All release metadata/build numbers, appcast/signing inputs, Shared/iPhone wire schemas, CloudKit identifiers and StoreKit behavior remain unchanged unless source review identifies a concrete required contract adaptation.

Full per-commit accounting: `docs/upstream-sync-2026-10-19.md`. Mark this work done only after hosted behavior checks and merge readback.
