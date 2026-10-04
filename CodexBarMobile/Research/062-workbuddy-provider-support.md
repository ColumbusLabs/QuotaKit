# WorkBuddy provider support

Status: `done` — implemented behavior passed focused hosted verification; the broader Mac integration gate remains open.

## Scope

Add WorkBuddy's Chrome-bound credit quota source to QuotaKit Mac and synchronize a deliberately narrow balance section to iPhone. The Mac provider uses the provider-plugin runtime with Chrome cookies, manual Cookie-header entry, and validated session caching. The iPhone receives the quota meter, reset description, and only finite `Left`, `Total`, and `Reserved` values from the `Credits` section.

## Decisions

- Append WorkBuddy to `UsageProvider`, generated provider manifests, widget choices, and the iOS quota catalog so existing provider IDs and CloudKit subscriptions remain stable.
- Keep WorkBuddy disabled until the user enables it. On macOS, automatic imports use Chrome; manual cookie entry works independently of browser import support.
- Retry the previous Chrome major only after an authentication failure. Sum only credit-denominated packages, reject non-finite aggregate amounts, and preserve balances when optional reset listings fail. Accept imported cookies only after a complete valid summary and optional reset lookup; cancellation and malformed data do not accept the session.
- Sync only the `Credits` section with finite numeric `Left`, `Total`, and `Reserved` rows. Do not send generic provider detail rows, account email, account identifiers, or cookies to iPhone. A successful snapshot without valid rows clears stale detail data.
- Add an append-only iOS quota alert subscription and branded provider mark. The catalog reaches 90 Mac providers and 73 quota providers (219 state-zone subscriptions).

## Validation

[Hosted CI run 37224122297](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37224122297) tested exact PR #226 head `07e23dc21fddd3d037e62ce46d079e5e4e696ea6`. In [Mac shard 3](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37224122297/job/111500300747), all 23 named WorkBuddy plugin tests passed with explicit QuickJS and JavaScriptCore parameterizations, including cookie acceptance, malformed/overflowing summaries, optional reset failures, cancellation, and authentication retry. WorkBuddy settings and localization tests also passed. The dedicated generic plugin A/B step did not run because the preceding full Mac shard failed; the WorkBuddy engine evidence comes from its parameterized suite.

The [iOS job](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37224122297/job/111500300762) passed 174 XCTest cases, 619 Swift Testing cases across 46 suites, and four UI tests, including WorkBuddy sanitized details and the 73-provider/219-subscription catalog contracts. [Hosted lint](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37224122297/job/111500146762) passed localization completeness, generated manifests, and palette parity across all 90 Mac providers.

These focused receipts verify this implemented feature. The overall Mac integration gate remains open for nine scanner SIGBUS process failures and two stale architecture fingerprints; their repairs and all applicable checks on the final reviewed PR head remain required before merge. No local WorkBuddy tests/builds or account-backed checks were run, and no real account or browser-cookie session was used.
