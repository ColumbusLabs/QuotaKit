# Upstream source integration — November 2, 2026

Completion and hosted qualification: [authoritative issue #266 record](https://github.com/ColumbusLabs/QuotaKit/issues/266). Source classification alone is not a CI or merge receipt.

Pinned range: `5f93dc3068b3bee3f8753f3772614cc2949c335d..897bff31731bb4b21b105f6e8bf4c32a8a8bf095`: 58 reachable commits, 48 non-merges and 10 merge commits. Issue: [#266](https://github.com/ColumbusLabs/QuotaKit/issues/266).

The native result preserves QuotaKit/Columbus Labs identity, all original provider IDs (110 → 111 with OpenDesign), CloudKit/App Group and mobile record compatibility, signing/updater ownership, appcast, and all version/build numbers. `UPSTREAM_VERSION` and `UPSTREAM_SYNC_DATE` remain unchanged. No binaries are distributed.

Fork-specific adaptations retain verified native accounting separately from optional imported history, migrate every home-scoped verified projection transactionally, preserve compressed history when re-parsing is impossible, recheck account ownership for notifications, scope automatic MiniMax credentials to request origin, and keep the fork's marked-process cleanup safety. Unprovable compressed-history producer/timezone transitions retain the database and report unavailability rather than inventing fresh history. Bounded scans validate archive presence through persisted pages; explicitly unlimited full scans can finish that work in one pass. Status reads reuse the completed proof and filesystem changes become visible on subsequent refreshes. Invalid, future-schema and orphan-sidecar stores remain intact; proven rebuilds first save a standalone recovery snapshot. New plugin presentation metadata decodes fail-soft across versions. CI and source review use fixtures/stubs; no live provider, Keychain, cookies, CloudKit, local builds or test suites are used.

Classifications describe the final source intent; hosted qualification and the merge receipt on issue #266 are required for completion. No applicable slice is deferred.

| Commit | Disposition | Accounting |
| --- | --- | --- |
| `36b5f6c42` Fix plugin percentage refresh for selected windows | superseded | Final selected-window refresh in 7381b2922, 0fb9d4289, 7cb9ab23a and dab75f57a preserves this intent. |
| `aa7862abe` feat(plugins): allow built-in provider branding per snapshot | adapted | Snapshot branding retained independently of plugin ownership; optional wire decoration fails soft. |
| `42a7f8efd` fix(plugins): invalidate branded icons and captured switcher images | adapted | Invalidate branded menu/switcher captures using QuotaKit image and title caches. |
| `0e949181c` feat(plugins): show configurable multi-quota menu-bar summaries | adapted | Bounded multi-quota plugin summary and selected-window rendering; final layout chain dab75f57a. |
| `7381b2922` fix(plugins): keep selected quota percentages fresh | adapted | Selected quota refresh includes effective window/branding signature. |
| `0fb9d4289` fix(plugins): preserve selected quota refresh with snapshot branding | adapted | Merge conflict resolution combines selected-window refresh and snapshot branding; final native implementation. |
| `96225ba2c` build(deps): update Sparkle, swift-crypto, swift-log and SweetCookieKit | adapted | Adopt library pins/acknowledgements and manual CLI artifact-action dependency; omit absent Linux-desktop workflows and upstream release prose. |
| `173960d26` fix(cursor): explain expired app sessions | adapted | Cursor expiry guidance with existing no-UI credential/account fallback safeguards. |
| `d253dd113` fix(opencodex): stream usage log imports | adapted | Stream OpenCodex usage logs; preserve opt-in source separation. |
| `277a08488` chore(plugins): sync summary branch with main | merge-wrapper | No independent product resolution in combined diff; parent intents accounted in corresponding slices; release prose omitted. |
| `4949263ed` feat(menu-bar): make pace state bars the default | adapted | Pace state-bar defaults preserve explicit saved layout/color choices. |
| `7cb9ab23a` fix(plugins): integrate compact summaries with selected quota refresh | adapted | Merge conflict resolution combines compact summaries and refreshed selected-window/branding state. |
| `347978b69` chore(plugins): sync merged menu-bar defaults | merge-wrapper | No independent product resolution in combined diff; parent intents accounted in corresponding slices; release prose omitted. |
| `c73027f59` fix(cost): keep Codex scan state per Codex home | adapted | Transactional shared SQLite home migration extends fork verified/temporal tables; OpenCode uses a separate source key. |
| `140f0f202` build(deps): update Commander to 0.3.0 | adapted | Commander 0.3 explicit argument-tail resolver and native CLI regression fixtures. |
| `b60907bbf` Merge remote-tracking branch 'origin/main' into HEAD | merge-wrapper | No independent product resolution in combined diff; parent intents accounted in corresponding slices; release prose omitted. |
| `5475e8202` fix(l10n): validate plural arguments after ordinary placeholders | adopted unchanged | Plural printf positions account for preceding values and star arguments; source and fixture changes. |
| `daf94a2e6` fix(minimax): discover China web sessions and quotas | adapted | China quotas plus complete-origin imported cookie/token/cache scoping; explicit manual semantics retained. |
| `0179d0e11` fix(opencodego): reuse the active OpenCode API key for quotas | adapted | Use active OpenCode Go credential; retain QuotaKit token/account contracts. |
| `86c8efa21` Merge remote-tracking branch 'origin/main' into HEAD | merge-wrapper | No independent product resolution in combined diff; parent intents accounted in corresponding slices; release prose omitted. |
| `4f5bc00fc` feat(workbuddy): show platform reward credits as their own window | adapted | WorkBuddy reward window/expiry, finite totals and accepted-session/cancellation safeguards. |
| `a47fccfa0` feat(hooks): expose Codex raw-plan provenance on usage_updated | adapted | Codex raw plan provenance from OAuth/PAT/RPC into snapshot/hooks and QuotaKit environment aliases. |
| `d7a613291` fix(codex): keep cost history for rollouts archived as .jsonl.zst | adapted | Retain cached compressed rollouts without decompression; unprovable producer/timezone paths preserve DB and return honest unavailability. |
| `82ba6a2ed` Merge remote-tracking branch 'origin/main' into HEAD | merge-wrapper | No independent product resolution in combined diff; parent intents accounted in corresponding slices; release prose omitted. |
| `1a170f8b1` feat(codex): add custom names for Codex accounts | adapted | Custom names use hashed persisted login/workspace keys, privacy filtering and fork account UI. |
| `f146a1e3d` Merge remote-tracking branch 'origin/main' into HEAD | merge-wrapper | No independent product resolution in combined diff; parent intents accounted in corresponding slices; release prose omitted. |
| `b8187b87a` test: remove wall-clock deadline flakes | rejected | Only removes an incidental timeout in upstream-only DashboardClaudeSwapCollectionTests; fork has no corresponding deadline fixture. Existing timeout tests retained. |
| `565a24eb5` feat(menu-bar): add separator glyphs to the layout editor | adapted | Separator glyphs and V7 layouts retain V6/older downgrade projections. |
| `f1035ec50` fix(traecn): align credit summary precision | adapted | Trae CN credit precision while preserving fork browser/session traversal. |
| `76544a86f` fix(deepseek): discover Platform sessions across Chromium-family browsers | adapted | DeepSeek Chromium-family session discovery with profile/account binding. |
| `b1cac871c` ci: make test cleanup and optional-request ordering deterministic | adapted | Mounted discovery-home cleanup preserves isolated CODEX_HOME/strict inventory; optional request tests use deterministic events. |
| `365db9638` feat(notifications): warn before Codex weekly quota resets unused | adapted | Opt-in weekly reset reminders with completion-based receipts and current account/reset delivery guards. |
| `7606d49c2` Merge remote-tracking branch 'origin/main' into HEAD | merge-wrapper | No independent product resolution in combined diff; parent intents accounted in corresponding slices; release prose omitted. |
| `754e3fde6` Merge #4802: feat(plugins): snapshot branding, compact multi-quota summaries and selected-window refresh (#4787, #4801, #4802) | merge-wrapper | No independent product resolution in combined diff; parent intents accounted in corresponding slices; release prose omitted. |
| `500a7a6d5` fix(sync): re-send snapshots whose CloudKit save was dropped | adapted | Dropped CloudKit save marker clears for retry; old callbacks cannot confirm new desired snapshots. |
| `85607bbd4` fix(claude): show the CLI's rate-limited model breakdown notice | adapted | Claude CLI rate-limit breakdown message preserves fork scoped process/credential handling. |
| `d25834d07` fix(copilot): show monthly pace in the menu bar | adapted | Copilot monthly menu pace uses native QuotaKit render data. |
| `787188431` fix(menu-bar): stop repeating the window label next to Auto % | adapted | Automatic-window label deduplication uses fork renderer per-line behavior. |
| `79438e435` fix(perplexity): show organization pool credits | adapted | Perplexity organization pool credits in fork reference models and quota windows. |
| `ebc3cb8c9` fix(bedrock): show unavailable billing data instead of zero spend | adapted | Bedrock unavailable billing remains unknown instead of fabricated zero spend. |
| `12e9aa09a` feat(providers): add OpenDesign subscription quotas | adapted | OpenDesign provider111, native manifests/icons, appended mobile zones and numeric sync fixture. |
| `474a15590` fix(cursor): support Brave Origin for browser login and cookie imports | adapted | Brave Origin browser support with SweetCookieKit0.5.11 and synthetic profile coverage. |
| `c379ff588` fix(zai): show prepaid-only BigModel balances | adapted | z.ai prepaid-only balance using shared provider detail renderer. |
| `4d9400fb6` feat(plugins): use shared browser cookie imports | adapted | Shared browser traversal/cancellation and explicit cookie resolver precedence preserve account scope. |
| `4aa40314c` feat(cli): allow serve clients to request fresh usage measurements | adapted | Forced refresh requests bypass stale response joining while provider-level coalescing/throttling remain. |
| `72543fc2f` feat(plugins): declare a Usage Dashboard link in the manifest | adapted | Plugin dashboard URL participates in approved binding and is rechecked before opening. |
| `2e687c8ae` feat(cli): describe provider authentication inputs in config providers JSON | adapted | Read-only CLI auth input inventory with QuotaKit CLI/config naming and no credential values. |
| `41cf60fa8` fix(claude): create the watchdog child group at spawn and keep its exit status | adapted | Owned child group at spawn, WNOWAIT exit ownership, bounded cleanup; fork marked-PID reaper retained. |
| `d8e55d39a` fix(litellm): show the team-member budget as the personal budget | adapted | LiteLLM team-member personal budget retains bounded plugin mapping. |
| `279a263f6` fix(cost): price GPT-6.1 Sol Fast requests at Fast rates | adapted | Sol Fast rates and resumed tier evidence; explicit unknown-tier roundtrip retained. Legacy cached Priority remains conservative when absent provenance cannot distinguish a rotated-out authoritative trace from old source inference; fresh scans honor tier transitions. |
| `f20961a91` fix(kiro): read usage from the API first and use the V2 harness on Kiro CLI 3 | adapted | Kiro API-first with V2 CLI3 harness and fixture-only auth recovery. |
| `9ea096eda` fix(copilot): explain ended subscriptions | adapted | Explain ended Copilot subscriptions without losing historical allowance semantics. |
| `dab75f57a` feat(plugins): render plugin snapshots through the menu-bar layout | adapted | Plugin snapshots render through native fork layouts; persisted IDs/ownership remain unchanged. |
| `95c1d57b2` feat(cost): price identified Codex requests across multiple SSH hosts | adapted | Identified multi-host ledger schema2 conservatively deduplicates and prices with local collector provenance. |
| `a8b880d8f` feat(codex): add reset-credit expiry countdown reminders | adapted | Reset credit countdown opt-in, preserve old summary receipt hashes, record delivered receipts with owner/inventory rechecks. |
| `348e2fa8d` chore(release): prepare 0.83.0 | rejected | upstream release-only bookkeeping; preserve QuotaKit release ownership |
| `7577a26ce` chore: publish v0.83.0 update feed | rejected | upstream release-only bookkeeping; preserve QuotaKit release ownership |
| `897bff317` chore: start 0.83.1 development | rejected | upstream release-only bookkeeping; preserve QuotaKit release ownership |
