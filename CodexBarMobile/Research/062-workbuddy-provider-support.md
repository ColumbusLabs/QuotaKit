# WorkBuddy provider support

Status: `in-progress` — implementation is staged for independent review; hosted integration validation is pending.

## Scope

Add WorkBuddy's Chrome-bound credit quota source to QuotaKit Mac and synchronize a deliberately narrow balance section to iPhone. The Mac provider uses the provider-plugin runtime with Chrome cookies, manual Cookie-header entry, and validated session caching. The iPhone receives the quota meter, reset description, and only finite `Left`, `Total`, and `Reserved` values from the `Credits` section.

## Decisions

- Append WorkBuddy to `UsageProvider`, generated provider manifests, widget choices, and the iOS quota catalog so existing provider IDs and CloudKit subscriptions remain stable.
- Keep WorkBuddy disabled until the user enables it. On macOS, automatic imports use Chrome; manual cookie entry works independently of browser import support.
- Retry the previous Chrome major only after an authentication failure. Sum only credit-denominated packages, reject non-finite aggregate amounts, and preserve balances when optional reset listings fail. Accept imported cookies only after a complete valid summary and optional reset lookup; cancellation and malformed data do not accept the session.
- Sync only the `Credits` section with finite numeric `Left`, `Total`, and `Reserved` rows. Do not send generic provider detail rows, account email, account identifiers, or cookies to iPhone. A successful snapshot without valid rows clears stale detail data.
- Add an append-only iOS quota alert subscription and branded provider mark. The catalog reaches 90 Mac providers and 73 quota providers (219 state-zone subscriptions).

## Validation

Local builds, tests, lint, and account-backed checks were intentionally not run for this staged integration task. The host integration gate must validate provider registry, parser fixtures, localization, phone detail sanitization, and widget selection before this research entry moves to `done`.
