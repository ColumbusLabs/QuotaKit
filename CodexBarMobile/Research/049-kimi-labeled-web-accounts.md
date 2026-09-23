# Kimi labeled web accounts

Status: done

## Goal

Add labeled Kimi web-cookie accounts to QuotaKit for Mac and CLI, preserving the
existing China/International region setting and cookie-source preferences while
keeping account credentials isolated. Avoid changing the established CloudKit
or iPhone snapshot contract.

## Upstream source and behavior

Adapt the relevant parts of upstream commits `36a4fb218` (labeled web accounts),
`91390a195` (catalog coverage), and `5216664d1` (Linux browser-support gate).
Kimi account selection uses its own `kimi-auth` cookie, the provider's saved
region, and the web route; selected-account failures do not fall back to ambient
credentials or browser discovery. The separate Moonshot plugin refactor is not
a dependency of this Kimi slice.

## QuotaKit adaptation

- Reuse QuotaKit's token-account editor, cookie injection and account-selection
  flow. Preserve Kimi's existing region and cookie-source settings outside the
  temporary selected-account snapshot.
- Scrub Kimi cookie and API-key environment credentials when a saved account is
  selected. A selected account is forced through web/manual-cookie settings;
  only this explicit manual-cookie account path bypasses CLI browser support.
- Keep Kimi account data in the existing `providers[].tokenAccounts` config and
  catalog. No new provider ID, persistence format, or mobile model is introduced.

## CloudKit and iPhone contract

CloudKit provider records are keyed by device, provider ID, and account email;
the record key has no local token-account UUID. Kimi responses have no account
email, but QuotaKit already uses a saved token-account label as the fallback
`accountEmail` identity before storing each account snapshot. The generic
fan-out emits all accounts only when those identities are non-empty, distinct
after case/whitespace normalization, and map to distinct record names;
otherwise it retains only the selected account for that push. A label change
rekeys that account's record, and existing stale-record reconciliation deletes
the old key. The iOS record-name parser now splits only the device and provider
prefixes, preserving `|` characters in the account identity suffix without
changing the CloudKit or snapshot wire format.

## Verification

- Focused iOS `SnapshotCacheTests` class run passed: 68 tests, 0 failures. It
  includes the new `Work|Prod` record-name deletion regression and the existing
  nil-email multi-account grouping test.
- Focused Mac Kimi/account/sync coverage passed: 29 tests across
  `KimiTokenAccountTests`, `ProviderCredentialCharacterizationTests`,
  `TokenAccountSyncCoverageTests`, and `SyncCoordinatorMultiAccountTests`.
- SwiftFormat passed on all 10 changed Swift files. Strict SwiftLint passed on
  the 8 changed Swift files without repository-wide baseline violations; no
  lint warnings occur in the changed `SnapshotCacheTests` or release-note
  lines.
- iOS localization audits passed for all locales and all 287 source keys;
  provider manifest check reports all 73 providers current; `git diff --check`
  passed.

All tests use synthetic tokens, fixtures, and in-memory/stubbed providers; no
live Kimi account, Keychain, browser-cookie discovery, or CloudKit writes were
used.
