# Final upstream runtime clearance

Status: done for implementation and focused local verification; required exact-head hosted CI and merge pending.
Date: 2026-09-30

## Scope

Close the remaining original-cut runtime contracts after the Recovery20 slice, grouped by shared dependencies: cost rows 47/311/465; provider rows 215/285/417/485/522/594/796/802/810; shared Mac rows 147/260/422/458/580/858/865; Antigravity rows 207/352/381/424/541/650/846; Claude rows 114/212/425/512/623/782/783/806; Codex authority rows 145/251/845/856/857; plugin/cookie rows 841/866. The nine-object fresh tail through `5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f` adds the narrow spend-header layout and optional-request fixture determinism; merge-only and upstream release bookkeeping receive explicit dispositions.

## Design

- Keep immutable stamped status/activity reads separate from scanner baselines; stream physical SQLite rows and preserve malformed-row counts, retry receipts and aggregate semantics.
- Share provider balance extraction across layouts, previews and automatic text while retaining real quota windows and account-scoped Codex credits.
- Retire Crof from active catalogs while retaining opaque historical sync/config identifiers. Existing iPhone records remain readable; current alert subscriptions omit the retired provider.
- Retain failed widget entries only with current-process account evidence, independently per enabled selectable provider. Never fabricate a quota denominator for balances.
- Rebuild an explicitly tracked menu only while its owner and selected provider remain current. Keep ordinary deferred scheduling and temporary submenu state separate from persisted account expansion.
- Bound credential validation and local process authority checks; preserve account/plan identity before dashboard or reset metadata publication. Personal-information hiding uses stable opaque account labels.
- Scope opted-in plugin cookie jars to same-origin HTTPS requests and enforce generation-aware durable cookie/bearer mutation so stale failures cannot clear a newer login.
- Keep Claude reset grants live-only and Web-primary; allow one safe opt-in fallback with the original request cookie. Preserve warning continuity only through verified ownership and compatible reset episodes.
- Preserve Antigravity family quota lanes and unknown usage, explicit source authority, compatibility gates and safe failure diagnostics.
- Scrub inherited secret-shaped environment names at existing test entrypoints using one helper; verify via fake processes without credentials or SwiftPM.

## Verification plan

One coordinated focused Swift build/test pass after all writers freeze, including changed behavioral suites and the affected Recovery20 lazy-history receipt/retry fixtures. Run full repository lint and required exact-head hosted CI before merger. Independent reviews cover cost data integrity, cookie mutation, Codex authority and shared UI wiring. Builds, test success, merged credit and end-goal completion are separate evidence layers.

No release, app installation, provider login, browser import, real Keychain read or live account probe is part of this clearance slice. Build numbers and monitor cursor remain unchanged until complete final row-level reconciliation.

## Current evidence

- Fake-process test-environment entrypoint checks and shell sharding fixtures passed.
- Root shared Swift files passed scoped SwiftLint; owner scopes have their own formatting/lint artifacts.
- All product and test targets compile. All 83 planned focused filters have passing completed evidence across coordinated affected-only runs, including additional OpenRouter balance, account/plan reset-credit and native hooks fixtures. Full package execution was omitted locally; required hosted CI remains the delivery gate.
- Dedicated hydration-worker and per-job pool tests pass, as do bounded catch-up status, physical-row streaming and warm-scan performance. Independent reviews cover actor/cookie/account ownership and final changes.
- Full lint gates pass: zero strict violations in 2,670 files, format, 22 Mac localization catalogs, all 287 iOS localized source keys, parser/registry, package/release helpers, docs/shell/CI gates, branding and 87-provider palette.
- Hooks proof checks native editable empty AX fields, prompts and unchanged bindings. Offscreen SwiftUI hosting does not prove onscreen VoiceOver names; semantic titles and explicit labels are retained.
- No final-wave row receives merged credit before exact-head hosted CI and covering merge. A fresh upstream fetch confirms the same 930-object head.
