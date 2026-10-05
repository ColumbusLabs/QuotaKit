# WorkBuddy provider support

Status: `done` — focused feature verification and the final integration gate passed on `027900bcc75db61ab327e52bb926e11314c8bee1`; PR #226 merged as `d62d2c881bb8ce4192590723c28e0b5973eb57c9` ([hosted run](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37332130170)).

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

These focused receipts verify this implemented feature. The scanner crashes, architecture fingerprints, and request-ledger failures were repaired in subsequent hosted cycles. Final exact-head hosted CI run 37332130170 passed the applicable lint, Linux, macOS, iOS, and Xcode compatibility gates on PR #226 head `027900bcc75db61ab327e52bb926e11314c8bee1` ([run](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37332130170)). PR #226 merged as `d62d2c881bb8ce4192590723c28e0b5973eb57c9`. Verified origin/main cursor and tail readback: `cursor=14567f0b6711ef38741cadd7ff20ef76a2053af2; fetched upstream=6a26b2e9b1b60471970deb6fe663f9e5f284e2ce; newer tail=20 DAG/7 non-merge commits outside the pinned reviewed range; UPSTREAM_VERSION=v0.69.0`. No local WorkBuddy tests/builds or account-backed checks were run, and no real account or browser-cookie session was used.
