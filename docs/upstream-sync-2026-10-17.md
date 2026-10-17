# Upstream integration — 2026-10-17

## Frozen range and accounting

- QuotaKit source base: `8dea6b32e8858ccf5c5b04ec056e710151e557a3` (`origin/main`).
- Reviewed upstream base: `f50cd6cee4db4e96e4823a51f74eb462a56bbb66`.
- Frozen upstream head: `6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e`.
- 18 reachable commits, all linear: 12 adapted product/test/localization intents; six rejected release/publishing-only commits; zero merge wrappers, supersessions, or applicable deferrals.
- Implementation accounting is recorded here. [Issue #250](https://github.com/ColumbusLabs/QuotaKit/issues/250) maintains the authoritative verification and merge completion receipt.

| Commit | Decision | Subject | Evidence and QuotaKit adaptation |
| --- | --- | --- | --- |
| `eca5dcc258e54d789ea58f8c55c8438d2a708941` | adapted | feat(plugins): include user plugins in Overview and switcher gauges (#4549) | User plugins in Overview/switcher gauges; preserve QuotaKit menu and settings behavior. |
| `196eabf996d940a18230f51bfe26719a6336f58a` | adapted | feat(settings): manage the bundled HTTP usage server (#4553) | Optional bundled HTTP server settings/controller; QuotaKit CLI path and lifecycle, default disabled. |
| `cbafb46419f3e9b9a88d866f7f11470959a42924` | adapted | feat(menu): add Spend items and conditions to menu bar layouts (#4530) | Spend layout items/conditions with backward-compatible persisted layout migration and quota/spend refreshes. |
| `667dd3a58729479eca86562ae89213c97fad8c07` | adapted | test: bound detached fixture lifetime to the test process (#4570) | Owner-bounded detached process fixtures, preserving QuotaKit descendant fixture synchronization. |
| `729b595bd0454c90cb93278335e0db9f8114ad0d` | adapted | fix(claude): show session forecasts on claude-swap cards (#4566) | Claude swap session forecasts through QuotaKit menu/account usage projection. |
| `c8fa04e1758455970f56bfbe1cc9e8d7e6bfece2` | adapted | feat(claude): read tcr account pools through the claude-swap adapter (#4517) | Read-only tcr account pools through shared Claude adapter; preserve account identity and compatible sync models. |
| `8b931397a1107ee8bc9c01115cecf3a90f3b38b3` | adapted | feat(claude): map token accounts to a Claude config directory (#4556) | Local token-account Claude directory mapping; exclude machine paths from outgoing iCloud data and preserve receiver-local mappings. |
| `6fdf13002ea5b5190ab91415cda2b0f9e9cf62ae` | adapted | feat(cli): opt-in app usage cache for locked-keychain SSH sessions (#4554) | Explicit app CLI cache opt-in for locked-Keychain SSH, QuotaKit cache paths and no-UI safeguards. |
| `bbc2e229cb59baf3225dc90683837b2994a5c283` | adapted | feat(futureagi): add billing-period usage (#4572) | Future AGI billing-period provider with catalog/manifests/mobile/shared assets and usage projection. |
| `416076bacd4cced766d2ed824c3e528c98dbadde` | adapted | fix(i18n): translate the Indonesian Keychain cookie prompt (#4580) | Indonesian Keychain cookie prompt with QuotaKit customer-facing identity. |
| `0ff1cf55c0a27b63cbb4a7359e0ef2d098114d97` | adapted | feat(gemini): add a Gemini app source for 5-hour and weekly limits (#4535) | Gemini app browser-source 5-hour/weekly quotas distinct from Gemini CLI; preserve sync/widget semantics. |
| `23a4fa27939b1147b700106568906b360b4b13c2` | adapted | feat(providers): add Munito organization spend limits (#4531) | Munito organization spend limits with complete provider registry/mobile/shared integration. |
| `9eaab90d1aa246d63167d0763199cd6edeb20133` | rejected | chore(release): prepare 0.77.0 | Upstream 0.77.0 release changelog/version bookkeeping; QuotaKit versions and release ownership must remain unchanged. |
| `d235901d4fc51f9421f43838e8a60f567bd6038e` | rejected | docs: update appcast for 0.77.0 | Upstream public appcast publication; QuotaKit appcast ownership and binary-distribution boundary. |
| `a91669f2ff972ac2a549ed8c20725fdc1a510194` | rejected | chore: start 0.77.1 development | Upstream 0.77.1 development version bookkeeping; ordinary integration is build-number neutral. |
| `5fb13f80635813e8dd80aa7964819552a0d88caf` | rejected | ci: publish complete CodexBar releases from Actions | Upstream-specific signed-tag release pipeline embeds Pete signing/Homebrew/publication ownership and retires local release wrappers. QuotaKit retains its own release configuration and workflow; no supported QuotaKit Homebrew publication contract. |
| `1532c70225b993f119479f73ce7929a17a08ae0b` | rejected | fix(ci): allow cold universal widget release builds | Timeout-only follow-up in the upstream release.yml rejected above; QuotaKit has no equivalent publishing job. |
| `6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e` | rejected | fix(ci): retry dropped Apple ticket-service connections | CI-only stapler transport shim installed solely by the rejected upstream release.yml; no QuotaKit call site or observed failure requires it. |

## Fork contracts

Preserve QuotaKit / Columbus Labs identity, configuration and Application Support paths, repository and appcast ownership, release scripts/signing inputs, entitlements/App Groups/CloudKit topology, versions and build numbers. Existing provider IDs/order must all remain, with only Future AGI and Munito added. Preserve backward-compatible shared/iPhone records, widgets, notifications, StoreKit, and credential ownership/no-UI recovery safeguards.

## Adaptation safeguards and review resolutions

- The bundled server launches `Contents/Helpers/QuotaKitCLI`, passes its token through `QUOTAKIT_DASHBOARD_TOKEN`, and recognizes the actual QuotaKit readiness log. Synthetic helper tests cover lifecycle, restart, shutdown, and token exclusion from arguments.
- The SSH cache uses QuotaKit Application Support storage and a `quotakit-app` source marker. It contains quota figures only, uses owner-only regular files, rejects stale/future entries, and is restricted to matching default accounts in non-GUI sessions. Generic server `permissionDenied`/HTTP 403 failures never become cached success, even when an unrelated optional Keychain lookup recorded a lock.
- Claude directory mapping stays machine-local through outgoing secret stripping and incoming UUID-based local restoration; explicit directory scans exclude ambient/Pi history and cannot publish another configured scope's cached cost snapshot.
- Claude forecast buckets distinguish external account sources and are excluded from ambient account-history adoption. tcr is read-only for account activation; existing claude-swap widget ownership bytes remain compatible. The external tcr schema does not consistently supply stable organization UUIDs, so no unsupported organization-identity inference is added.
- V5 layout payloads participate in V6 loading and all older projections remain paired. Spend progress bars sign cost-only changes, including imported/programmatic layouts.
- Future AGI zero-allowance and Munito no-limit data retain generic details on iPhone without fabricated $0 budgets, quota windows, resets or statuses. Positive configured budgets remain visible. Existing 104 provider identifiers/order and legacy palette fingerprints are preserved; quota notification metadata expands additively to 79 providers/237 zones.

## Verification

Required qualification: final source review, independent adversarial review, exact-head hosted CI, and merge readback. Results are published in the linked completion record. No local automated Swift/Xcode tests, builds, or lint suites are authorized by default. Local work is source inspection, `git diff --check`, documented generation and write-formatting. No real account/credential/cookie/Keychain/CloudKit probes or release/distribution actions.

CI cost eligibility: live repository is PUBLIC. Existing CI runners are standard `macos-26`, `macos-15`, `ubuntu-24.04`, and `ubuntu-24.04-arm`; no larger/self-hosted or reusable runners. Push to the topic branch starts no workflow, PR starts only CI, and merge to main starts CI. Release workflows require manual/tag/release events; historical diagnostic workflow is restricted to its own branch and is absent here. CI restores existing caches only and has no artifact upload or cache-save action, so this batch adds no artifact/cache storage. Current cache usage is below the included 10 GiB. Existing artifacts from other workflows are not created, deleted, or counted as this integration's free-storage proof. Standard hosted runners for public repositories are free under [GitHub's current billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions). No paid usage, billing changes, storage-cap changes, or gate weakening.

## Completion receipt

The authoritative [issue #250 completion receipt](https://github.com/ColumbusLabs/QuotaKit/issues/250) records the final reviewed head, PR, exact-head CI, merge commit, monitor/cursor result, research status and cleanup after they are verified.
