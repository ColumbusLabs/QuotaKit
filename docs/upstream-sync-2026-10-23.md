# Upstream integration — 2026-10-23

Frozen upstream range: `8de11fffdf1a5db45f4d26197f947e2b4a37b6a7..7683b73676bf25e1c347082e383b6807c853b00b`. QuotaKit origin base: `6deb481baa42b2d96ddbe3c2827eeb579fba613e`. Tracking and authoritative qualification: [issue #260](https://github.com/ColumbusLabs/QuotaKit/issues/260).

All 26 reachable commits are linear: 20 adopted/adapted intents, six rejected whole commits with concrete reasons, zero merge wrappers, superseded commits, or applicable deferrals. Exclude upstream release/changelog hunks throughout. No wholesale merge.

| Upstream commit | Decision | Intent and treatment |
| --- | --- | --- |
| `e439651eab11e5ac6051072d85aba90c5a5f4e49` | adapted | fix(kimi): show gift credit balances with their expiry (#4691) |
| `0538e94b464db0c12776e4bf6e7b11c66e44d275` | adapted | fix(cursor): use the X Subscription weekly pool as the main meter (#4695) |
| `71e3e56b06cebc43c8acc5d3372b52e7e917ce65` | rejected | Third-party CodexBar GTK integration link targets an absent Linux desktop integration; retain existing explicit upstream provenance rather than advertise unqualified QuotaKit compatibility. |
| `49e75815870959213c1e5892fb8c583e9372ba0f` | adapted | fix(kiro): skip offline background CLI probes that open sign-in tabs (#4589) |
| `4654968e91f0886b72f5eace382274be3bb5d30d` | adapted | feat(cost): add Claude Mythos 5.1 and Mythos 5 pricing (#4578) |
| `aa232d7f9ffce83dcb559bf7a56abc93c477b40c` | adopted | fix(l10n): restore Ukrainian strings reverted by #4576 (#4703) |
| `eb7d060e4d932883737ee79fbb7dd4bd817ecba0` | rejected | Qt Linux desktop icon renderer/build action is absent from QuotaKit; portable Linux CLI is retained separately. |
| `575a2446a50113b9afa5156d64915dc94ee19045` | adapted | feat(providers): add Soniox organization usage (#4678) |
| `cf393586c2cd8cf3b2f70f77ce05449ab540992c` | adapted | feat(cli): add Copilot device-code login (#4717) |
| `bcc4c567d7d984578a65bfa0bdecee1534eaf1b8` | adapted | feat(codex-accounts): log redacted registry mutations for account-loss diagnosis (#4699) |
| `0703a0c015ffb08c0cbe45131f86d88a7bc85907` | adapted | feat(providers): add Trae CN usage (#4682) |
| `616c5b12d4a472050ec9b4cdb959443ecfd22e57` | adapted | fix(claude): count Cowork usage once and rebuild stale serve dashboards (#4718) |
| `8928b6ee4c8069f283d4621486ffbeaf8086cb12` | adapted | fix(tavily): handle a null pay-as-you-go limit (#4711) |
| `5a84dca9ba4f5a365a09ad63810a5ff1804622d2` | adapted | fix(kimi): keep web usage when a lapsed plan has no Code pools (#4700) |
| `1ffa960112eb56f6bddce2d7a8d21378e560e103` | adapted | fix(claude): report limits unavailable when a web answer has no quota windows (#4687) |
| `204aec7fe20cac15ff1a8990f4650477b4da3010` | adapted | perf(menubar): skip unused reset formatting on cached renders (#4720) |
| `871cce35622ef5180636337721c7520160ea926d` | adapted | fix(menubar): draw both user-plugin windows in the merged icon (#4719) |
| `edcf630d44a2ab394469bae78054c6dd788651fb` | adapted | feat(settings): adopt native Liquid Glass in Settings on macOS 26+ (#4708) |
| `b5a5c0e7153528a10191393831e6f5a109cfcdd8` | adapted | fix(linux): route make check and lint to the Linux lint target (#4688) |
| `3e060a954d7310bf2125074024f0b0f8f91db4b0` | rejected | Upstream version and release-only changelog bookkeeping. |
| `064c37dad67e77edeb6c1bb5263a0a8efffa62e2` | rejected | Upstream public appcast/release artifact ownership; QuotaKit appcast is unchanged. |
| `575d6ad7ad3a320f171ff1612a4b310a8d120439` | rejected | Upstream development version and release-only changelog bookkeeping. |
| `d4207d4f6626bfb0dd712da30fc100daf4b9f3ad` | rejected | Linux desktop launcher/autostart installer is absent from QuotaKit. |
| `6ad1ba02d3ca81e6346fcf2a7302f6af6b2b3b44` | adapted | fix(menubar): use medium weight for stacked menu bar text (#4729) |
| `676af3b8dd59d675322af2f9ca912e25c836a2eb` | adapted | fix(plugins): report an unset plugin endpoint as needing configuration (#4727) |
| `7683b73676bf25e1c347082e383b6807c853b00b` | adapted | feat(plugins): show refresh errors, window titles and resets, and feed hooks for user plugins (#4734) |

## Fork adaptations and verification design

- Append Soniox and Trae CN to all existing 106 provider IDs and generated manifests. Preserve existing order, saved configuration and wire identifiers. Soniox without a positive budget has no synthetic quota; allowlisted billing details use existing optional Mac/iPhone wire fields. Generic quota eligibility never fabricates measured allowance.
- Keep QuotaKit branding, config/Application Support paths, identifiers, CloudKit/App Group/notification/StoreKit/recovery behavior, appcast, entitlements, signing inputs and all release/build numbers. New optional Mac `RateWindow.title` decodes older data; it does not alter the mobile wire schema.
- Preserve fork account ownership and notification state keys. User plugins use separate quota hook/session baselines, account-aware lifecycle invalidation, existing privacy/rate limiting, current generation/config/runtime publication guards, validated title limits and fail-closed endpoint approval. Hide Personal Info also suppresses plugin account identity cards.
- Preserve strict Enterprise Copilot account matching and optimistic private config writes; managed Codex diagnostics contain operation/count/result metadata only. Kiro scheduled reachability checks remain unauthenticated and bounded. No live provider probes or credential/Keychain/cookie/CloudKit access.
- Rebuild stale Claude Cowork rows and dashboards via local artifact generation 19→20, schema 3→4 and report semantics 7→9. Keep existing lower-bound behavior and compatible Codex parser predecessor `c939f17d29a7e29d` for the shared pricing-only hash change.
- Keep QuotaKit renderer reset/cache/locale/day keys and fleet behavior while using selected reset formatting and native macOS 26 Settings; retain older macOS fallback. Cursor weekly pools export a Weekly label and typed identity to iPhone, use weekly warning thresholds for the single shared pool, and stay out of Session-only widgets. Other providers retain Mac’s existing warning-setting slot semantics. Monthly Cursor Plan/Auto/API windows retain billing-cycle pace without claiming weekly identity; widgets normalize only provably stale Cursor identities from older Mac payloads. Legacy untyped window fallback and extra-window warning disablement remain compatible.
- Require exact-head free hosted lint, Mac shards, compatibility/widget build, Linux CLI and applicable iOS/Lite gates, plus independent adversarial review. No routine local build/test/lint/resolver/device runs. Cheap source/whitespace checks only locally.
- Repository PUBLIC; ordinary workflows use standard GitHub-hosted runners. CI restores existing caches only and uploads no artifacts/caches. Never dispatch release workflows or change account billing controls. [Current billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

Completion is established by the linked issue receipt only after all required exact-head checks pass and the reviewed head is merged. A branch implementation or staged cursor is not completion.
