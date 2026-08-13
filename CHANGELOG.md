# Changelog

Notable QuotaKit Mac and cross-platform release changes are documented here.

Older upstream history is intentionally preserved in Git, but this file now focuses
on Columbus Labs QuotaKit releases and product-facing changes.

## 0.32.4.17 / iOS 1.11.3 — 2026-08-13

### Fixed
- Usage & Spend: preserve complete Daily Spend totals and model breakdowns on iPhone while a Mac's local Codex history is catching up, then replace them once the complete refresh finishes.

## 0.32.4.16 / iOS 1.11.3 — 2026-08-05

### Added
- CLI: add a built-in auto-refreshing QuotaKit web dashboard at `/`, including provider brand icons, grouped multi-account cards, spend charts, and a status display that stays hidden when no provider status exists.
- CLI: add `quotakit dashboard --output <path>` for atomic snapshot publication and `--identity full` for explicit real-email output on trusted private surfaces; the default remains redacted.
- Dashboard v1: include claude-swap account windows, pace, active state, and identity under the Claude provider row when that integration is enabled.
- Currency: add Korean won (KRW) to the preferred-currency picker with zero-decimal formatting.
- Command Code: recognize the Individual GOAT plan and its monthly credits.
- Notion AI: track Business and Enterprise workspace allowances for rolling and billing-period windows, with calendar-aware pace estimates.
- Provider plugins: support local JavaScript or TypeScript providers with manifest-driven settings, approval-bound network and cookie access, and generic detail rows and charts.
- Sessions: discover live pi and OMP sessions alongside Codex and Claude Code, including mixed-version local and remote CLI support.
- CLI: expose Codex cost-history completeness in JSON and add an experimental provider-native-only scan mode (#2520). Thanks @NickGuAI!
- Usage & Spend: add an accessible daily, weekly, and cumulative token-activity heatmap backed by the existing persistent cost scan cache (#2548). Thanks @Yuxin-Qiao!
- Settings: the sidebar is now resizable — drag the divider between 200–380pt; the width persists across launches.
- z.ai/GLM: route BigModel aliases and relay-file keys only to China endpoints, reject canonical cross-region overrides before bearer auth, and keep Kimi browser import disabled when Cookie Source is Off (#2351). Thanks @Leehow!
- Kimi: enrich Code API and CLI usage with the monthly membership pool from a signed-in Kimi Desktop session, using WAL-safe read-only cookie access (#2351). Thanks @Leehow!
- Sessions: discover live pi and OMP sessions through one Pi-family scanner, with dialect-aware metadata, PID-only startup rows, and mixed-version CLI/remote support (#2529). Thanks @wdmitchelluk!
- Kimi/GLM: distinguish Kimi Code from the regional Open Platform, bind China and international keys to their issuing hosts, and show GLM Coding Plan's 5-hour window as primary with MCP separate (#2351). Thanks @Leehow!
- Provider plugins: declarative detail rows/charts plus bundled JavaScript conversions for OpenAI, z.ai, OpenRouter, Poe, and ClawRouter behind `CODEXBAR_JS_PROVIDERS=1`.
- Provider plugins: install local JavaScript or TypeScript providers with manifest-driven settings and generic menu cards, approval-bound network/cookie access, and sandboxed Sucrase transpilation.
- OpenCode Go: per-model cost and request breakdowns by day in the shared cost history chart, resolved from the local session database (#2649). Thanks @kentoku24!
- Copilot: decode the AI credits counter for token-billed seats and expose it in `quotakit diagnose`, so Business seats with zero-entitlement quotas are no longer blank at the data layer (#2613, refs #2593). Thanks @Yuxin-Qiao, and @KSEGIT for the discovery!

### Changed
- Claude: retire the Always allow Keychain prompt policy; existing selections migrate to Only on user action, and background refreshes no longer launch Claude Code, `claude-swap`, or credential-reading helpers.
- Synced reviewed CodexBar development through `a90dfed5c`, adding Fireworks and IBM Bob to QuotaKit's complete Mac/iPhone provider catalog, safer Codex cost-cache persistence, quota presentation improvements, and Mac reliability fixes while preserving QuotaKit identity, Columbus Labs release ownership, CloudKit and App Group contracts, and all build numbers.
- Cost history: add the upstream SQLite `CostUsageStore` foundation and fixture coverage without switching QuotaKit's production cache or iCloud/iPhone summary contract yet.
- Provider plugins: import the latest Synthetic, Poe, xAI, and z.ai JavaScript parity and sandbox support while retaining QuotaKit's native-default fetchers and typed compatibility payloads for iCloud and iPhone.
- Provider plugins: add a portable QuickJS engine for Linux and explicit local engine testing while keeping QuotaKit's native provider fetchers as the default where typed compatibility data feeds iCloud and iPhone.
- CLI dashboard: paint a cached shell immediately and stream provider rows as they finish, while retaining redacted account identity by default and QuotaKit-owned browser storage keys.
- Provider plugins: add golden-tested JavaScript implementations for OpenRouter, ClawRouter, Deepgram, and sub2api. QuotaKit keeps their native fetchers as the default so typed usage remains available to iCloud and iOS, while Crof and Venice continue using bundled JavaScript by default on macOS.
- Settings: refresh the Plugins pane to match the other panes — labeled install and directory rows with a Show in Finder affordance, a tilde-abbreviated path, a properly sized empty state, and consistent section footers.
- Settings: localize every Plugins pane control, status, approval prompt, and alert across all complete app locales.
- **Breaking JSON change:** provider-specific usage payload keys are being removed from `quotakit usage --format json`, `serve /usage`, and synced snapshots in favor of the generic Codable `usage.details` sections. The app and text CLI now render those same declarative rows and charts.
- Menu: move each usage window's used percentage and reset time into its title row, with all pace detail on one line (#2182). Thanks @jack24254029!
- Codex: define Fast cost as estimated API Fast USD, resolve it models.dev-first with model-specific API ratios, and refresh GPT-5.6 Terra/Luna fallback rates (refs #2175). Thanks @iam-brain!
- Synced upstream CodexBar changes through `98c286dbe`, adding the built-in serve dashboard, atomic dashboard snapshots, optional full identity, claude-swap dashboard accounts, KRW, and quota/runtime reliability fixes while preserving QuotaKit identity, Columbus Labs release ownership, CloudKit configuration, config paths, and all Mac/iOS build numbers.
- Synced upstream CodexBar changes through `a1fd8c5a9`, adding richer CLI JSON and native-only scans, token-activity heatmaps, resizable settings, plugin refinements, and provider correctness and reliability fixes while preserving QuotaKit identity, Columbus Labs release ownership, CloudKit configuration, config paths, and all build numbers.
- Synced upstream CodexBar changes through `a82f509ea`, including Notion AI, provider plugins, Pi-family sessions, quota and regional-auth fixes, and refreshed menu-bar pacing while preserving QuotaKit identity, Columbus Labs release ownership, CloudKit configuration, config paths, and all build numbers.
- Synced upstream CodexBar changes through `cee0fd074`, adding portable QuickJS plugins, packaged-resource smoke coverage, progressive dashboards, active claude-swap menu-bar usage, and quota fixes while preserving QuotaKit identity, Columbus Labs release ownership, native-default sync providers, CloudKit configuration, privacy defaults, and all Mac/iOS build numbers.
- Synced upstream CodexBar changes through `b39714de3`, adding standalone CLI resource packaging, omitted-reset-credit handling, Kimi duplicate-lane suppression, and exact-clock menu countdowns while preserving QuotaKit identity, Columbus Labs release ownership, native-default sync providers, CloudKit configuration, privacy defaults, and all Mac/iOS build numbers.
- Synced upstream CodexBar changes through `56a763eaa`, adding the SQLite cost-store foundation, wrapped menu metric rows, provider-plugin parity updates, and opt-in Claude statusLine guidance while preserving QuotaKit identity, Columbus Labs release ownership, native-default typed sync providers, CloudKit configuration, privacy defaults, and all Mac/iOS build numbers.

### Fixed
- Menu: allow long metric reset and pace details to wrap to two lines and include their content in the cached-height fingerprint so translated text is not clipped.
- CLI packaging: ship the CodexBarCore SwiftPM resource bundle beside `QuotaKitCLI`, include it in release archives, and smoke-test standalone resource loading without the build checkout.
- Codex: confirm a redeemed manual reset when the provider omits the consumed credit from the next inventory only after both usage samples corroborate the reset.
- Kimi: use the official usage-lane labels and hide the Code 7-day row only when its percentage and reset match the primary weekly quota.
- Menu bar: keep custom reset countdown tokens aligned with the opened menu by using the exact display clock rather than a rounded wall minute.
- Packaging: resolve the CodexBarCore SwiftPM resource bundle from `QuotaKit.app/Contents/Resources` and smoke-test the bundle's declared executable without relying on the build checkout.
- Claude: render the menu-bar indicator from the active claude-swap account and treat that presentation snapshot as loaded without suppressing ambient refresh retries.
- Codex and z.ai/GLM: decode monthly spend-control credit limits and credit-based Coding Plan windows, including the 5-hour primary reset, while retaining QuotaKit's MCP cadence semantics.
- Menu: make percentage labels follow the Usage bars fill setting.
- CLI serve: bound the full request head against slow-trickle holds, keep slow provider work running after a request deadline, and deliver completed late results to cache and already-waiting requests.
- Codex: apply redeemed manual resets immediately without waiting for the previous weekly-boundary confirmation window.
- Antigravity: wait for a cold-started signed-in `agy` server to become quota-ready before falling back.
- Cost cache: keep save-time overshoot aligned with the documented load cap so an accepted cache cannot immediately rewrite itself above the read limit.
- Grok: keep the usage label and pace estimate through the whole billing cycle instead of dropping to a bare "Credits" bar once fewer than about 3.5 days remain.
- Kimi and z.ai/GLM: keep regional credentials bound to their issuing hosts, add Kimi Desktop membership usage, and preserve safe cookie-source behavior.
- Command Code: parse rolling 5-hour and weekly limits alongside monthly credits.
- Usage & Spend: retain validated Codex totals while the local scanner refreshes.
- ZoomMate: preserve browser-cookie scope across the provider's API hosts.
- Overview: stop the infinite menu flicker when hovering between provider chart submenus with Agent Sessions enabled — no-op session rescans no longer invalidate menus, submenu hovers no longer trigger rescans, and session updates defer tracked-parent rebuilds like other data refreshes (#2652). Thanks @qazi0!
- Widgets: bound widget-snapshot file I/O with a defensive timeout and skip further container access once it wedges, so a blocked macOS 26 app-group open() can no longer beachball the app or hang the widget (#2267 follow-up).
- Command Code: parse and display 5-hour and weekly rolling limits alongside monthly credits and reset times (#2466). Thanks @derekszen!
- OpenCode Go: include Zen balance in CLI usage reads without waiting beyond five seconds (#2583). Thanks @Yuxin-Qiao!
- Usage & Spend: keep validated Codex totals visible while the local scanner catches up, with refresh indicators in the dashboard and menu cost rows (#2397). Thanks @hhh2210!
- ZoomMate: preserve browser cookie scope so parent-domain sessions reach both API hosts without leaking host-only cookies (fixes #2507). Thanks @weddle!
- Sync: propagate provider configuration edits made by the CLI or directly in `config.json` to the iCloud fleet without echoing remotely applied writes.
- Codex: classify rate windows by duration, so a 30-day window renders as Monthly with its real reset countdown instead of masquerading as the Session card — consistently across the provider card, widgets, and submenu (#2600, fixes #2592). Thanks @Yuxin-Qiao!
- Codex: bound the persisted cost-usage cache with entry/byte budgets, window-aware pruning, and a load-refusal cap, so the main process no longer grows without limit on large session corpora (#2646, refs #2637). Thanks @Yuxin-Qiao!
- Codex: resume fork catch-up from a validated cached offset when a rollout is appended, charging only the appended suffix against scan budgets instead of restarting the bounded full scan (#2648). Thanks @xx205!
- Claude: report a provably unreadable OAuth delegated refresh as terminal with a long cooldown, instead of looping "run claude login, then retry" and relaunching the CLI every poll cycle (#2650, refs #2634). Thanks @kes02!
- Usage & Spend: keep priced Codex model rows visible when the history also contains unpriced Auto Review routing rows, labeled as a partial breakdown with ranking removed (#2643). Thanks @akshayprabhu200!
- Perplexity: pin the promo expiry date to English formatting regardless of system locale, matching the rest of the string and the JS plugin (#2651). Thanks @kes02!
- OpenRouter: use the server-reported current-period remaining for the key-limit meter and "left" text instead of deriving both from cumulative lifetime usage (#2612, fixes #2605). Thanks @Yuxin-Qiao!

## 0.32.4.15 / iOS 1.11.3 — 2026-08-02

### Added
- Sync: opt-in iCloud sync (Settings → iCloud Sync, default off) syncs provider configuration, a curated preferences subset, and per-device usage snapshots across Macs via CloudKit; API keys/cookies/tokens ride end-to-end-encrypted fields with their own opt-out, hooks and machine-local paths never sync, and menus can show accounts from other Macs with last-known usage ("via <Mac> · 1h ago") when the local fetch is unavailable. The app now also watches `config.json`, so external CLI edits apply live.
- z.ai: add 7-day and 30-day model-usage chart ranges with dataset-consistent legends, colors, and daily tooltips (#2524). Thanks @LeoLin990405!
- Refresh: add a default-off global Low Power Mode that limits automatic provider, local usage, and storage work to once every 30 minutes while keeping manual refresh immediate (#2518). Thanks @Carl723000!
- CLI: `quotakit hooks watch` continuously polls providers and fires hooks on real quota/status transitions for headless installs, with in-memory baselines, event rate limits, `--interval` (default 300s, minimum 60s), `--provider`, and JSON output (#2536). Thanks @OfficialAbhinavSingh!
- Claude: compact multi-account menu for claude-swap — with four or more accounts the active account keeps its full card while the others become one-line rows sorted by remaining headroom, constrained accounts surface in red/amber, the healthiest switch target gets a star, and the healthy tail folds behind a summary row. Click a row to expand its full card.
- Menu: the compact multi-account layout now covers every stacked multi-account list — token accounts on any provider and Codex accounts (flat lists; workspace-grouped Codex lists keep their sections).
- Menu bar: Session/Weekly/Auto pace layout tokens that render the signed pace delta (`+11%`, `-8%`, `0%`), restoring the pre-0.45 "Both" display in the layout editor (#2540, fixes #2534). Thanks @kratocz!

### Fixed
- Cursor: label modern Auto and API quota lanes correctly in the Mac menu, matching the iPhone app.
- Cursor: make on-demand extra usage follow the shared optional-usage setting and remove the unsupported credits placeholder (#2338). Thanks @Zihao-Qi!
- Antigravity/Sessions: inspect processes in-process via libproc instead of spawning full-system ps/lsof, eliminating repeated macOS 26 “access data from other apps” prompts (#2267 hardening).
- Doubao: show Agent Plan windows alongside Coding Plan usage for Volcengine AK/SK accounts that subscribe to both products (#2517). Thanks @Astro-Han!
- Augment: store session cookies owner-only (0600), atomically publish updates, and repair permissions on legacy files (#2567).
- Ollama: direct declined Chrome Keychain access recovery to the provider card's Refresh (⌘R) action instead of the ambiguous manual-cookie path (#2072).
- Menu: merged provider tabs now size to their own content when switching from Overview instead of padding every tab to the tallest provider and leaving large blank regions.
- Codex: persist and budget fork-parent discovery so missing parents quiesce between inventory changes instead of sweeping every rollout on each refresh (#2525, #2538). Thanks @xx205, and @Helmi and @kiranmagic7 for the investigation!
- Claude: Auto cold boot with Keychain disabled loads without manual refresh (#2494, fixes #2493). Thanks @gmkbenjamin!
- Menu: no more stray floating "Refresh" tooltip beside the menu when switching tabs with the cursor over the actions area.
- Providers: write the Factory and Cursor session files (bearer/refresh tokens, auth cookies) owner-only (0600), matching the codex/kimi/antigravity credential stores.
- Menu: keep Overview↔provider switches flash-free by hosting every card row in one reusable AppKit container, including GPU-selection Overview rows.
- Codex: keep confirmed weekly reset lows and confetti private until the previously published reset boundary is due (#2481). Thanks @gmkbenjamin!
- Usage: populate verified z.ai, Kimi, and Grok rate-window durations for pace and forecasts while leaving unknown provider cadences unset (#2431, supersedes #2514). Thanks @Yuxin-Qiao!
- Command Code: persist validated browser sessions so CLI refreshes and the local service can reuse them (#2541). Thanks @rbonill!
- Menu: provider tab switches no longer blank out card rows mid-switch. Cached tab content is replanted into the attached hosting views (SwiftUI payload swap) instead of detaching `item.view`, which made Tahoe's NSMenu paint fallback "NSMenuItem" placeholder rows for a few frames; residual structural churn now renders blank instead of placeholder text. Verified frame-by-frame via 120fps screen recordings driven by the self-probe.
- OpenCode Go: read idle WAL-mode local history without creating SQLite sidecars (#2544). Thanks @Astro-Han for the report!
- Keychain: stop "QuotaKit Cache" login-keychain password prompts from dev and test tooling. Unbundled processes (`swift build` binaries, dev CLI runs) now use a process-local cache instead of the shared keychain item, never freeze a broken trusted-app ACL onto it, and test-blocked processes disable legacy keychain interaction process-wide and export the suppression flag to spawned child binaries.
- MiMo/StepFun: feed monthly token-plan windows into usage history, pace, and forecasts (#2526, part of #2431). Thanks @LeoLin990405!
- CLI: clearer error when setting an API key for the codex provider — point users to the openai provider for Platform keys (#2510, fixes #2501). Thanks @Yuxin-Qiao!
- Kiro: explain the kiro-cli requirement when no fetch strategy is available (#2465). Thanks @hxy91819!
- Linux: posix_spawn compatibility for glibc file-actions symbols; musl and Darwin paths unchanged (#2531). Thanks @kocaemre!
- Menu: switching provider tabs no longer flashes. The sibling-tab warmup now runs off a tracking-safe timer (the previous Task-based warmup never fired while the menu was open, which is the only time it matters), and provider tabs share one stable menu height via an invisible spacer, so a switch is a single-frame content swap with no window resize. Verified frame-by-frame with a new env-gated self-probe (`CODEXBAR_FLICKER_PROBE_DIR`).

### Changed
- Synced upstream CodexBar changes through `eddf0b4a1`, adding opt-in Mac fleet sync, provider-manifest derivation, safer session ownership, low-power refresh controls, headless hook watching, faster process discovery, and cost/quota accuracy fixes while preserving QuotaKit release ownership, public identity, CloudKit container, existing iPhone sync, and all build numbers.
- Synced upstream CodexBar changes through `41bc0141e`, adding stable provider-tab swaps and height, non-interactive development caches, monthly MiMo/StepFun pacing, idle OpenCode WAL fallback, and cross-platform process fixes while preserving QuotaKit release ownership, public URLs, config paths, CloudKit setup, and all build numbers.

## 0.32.4.14 / iOS 1.11.3 — 2026-08-01

### Fixed
- iPhone Spend dashboard: sync each model's actual token total from Mac so the Model Mix Tokens view shows Sol, Terra, Luna, and other model usage instead of an empty state.

## 0.32.4.13 / iOS 1.11.3 — 2026-07-31

### Added
- Spend dashboard: switch the model breakdown between API-equivalent cost and total token usage, with clear partial-history handling.
- Menu bar: add customizable drag-and-drop token layouts and weekly session-equivalent forecasting.
- Providers: add DeepInfra usage and balance, ai& spend, OpenRouter token accounts, DeepSeek cost summaries, broader Doubao arkcli support, Qwen Cloud individual Token Plans, and ZoomMate credits, history, and pacing.
- Alibaba: add Personal/Solo Token Plan variants for mainland Bailian and international Model Studio accounts.
- CLI: add safe cookie re-import and quota-aware guard commands under the QuotaKit command name.
- Claude: show prepaid credit balance from cached or manually configured web sessions and add an option to hide Daily Routines.
- Claude: show model-scoped weekly claude-swap windows and optionally show a card when only one account is available.
- Codex: add local workspace indexing as the foundation for per-workspace usage attribution.
- OpenCode Go: add daily local cost and plan-usage history.
- Overview: raise the merged provider limit from three to six.

- Claude: compact multi-account menu for claude-swap — with four or more accounts the active account keeps its full card while the others become one-line rows sorted by remaining headroom, constrained accounts surface in red/amber, the healthiest switch target gets a star, and the healthy tail folds behind a summary row. Click a row to expand its full card.
- Menu: the compact multi-account layout now covers every stacked multi-account list — token accounts on any provider and Codex accounts (flat lists; workspace-grouped Codex lists keep their sections).

### Changed
- Synced upstream CodexBar changes through `9bb9c42fb`, adding compact multi-account menu layouts and event-tracking-safe switcher warmup while preserving QuotaKit release ownership, public URLs, config paths, CloudKit setup, and all build numbers.
- Synced upstream CodexBar changes through `8ef86077e`, including preferred-currency conversion, xAI billing history, Claude weekly pacing, optional Crof quota alerts, and StepFun support while preserving QuotaKit release ownership, public URLs, config paths, CloudKit setup, and all build numbers.
- CLI: redact stored credentials from `quotakit config dump` by default; use `--show-secrets` to reveal raw values.
- Menu bar: remove status-item hover tooltips while retaining VoiceOver titles.
- Cost displays: use consistent labels while preserving reported-versus-estimated provenance in settings and per-value hints.
- Synced upstream CodexBar changes through `ab31038ed`, preserving Claude widget quota across partial and token refreshes only for the matching OAuth profile or selected account, and recognizing claude-swap re-login status while preserving QuotaKit release ownership, CloudKit setup, config paths, and build numbers.
- Synced upstream CodexBar changes through `b036579b4`, including safer provider endpoint overrides, Doubao Agent Plan usage, OpenCode Go authoritative web-window overlays, Ollama session recovery, MiniMax Linux API-key support, calendar-correct cost history, and CLI version-path fixes while preserving QuotaKit release ownership, public URLs, config paths, CloudKit setup, and iOS build numbers.
- Synced upstream CodexBar changes through `02b4ba278`, including Claude weekly-window ordering and fallback accuracy, Kimi weekly duration accuracy, Ollama session reuse, safer automatic Safari-cookie handling, LongCat Firefox imports, localized session equivalents, stacked menu-title alignment, WidgetKit refresh-loop prevention, and Linux Alibaba Token Plan support while preserving QuotaKit release ownership, CloudKit setup, config paths, and iOS build numbers.

### Fixed
- Keychain: keep Cursor and Claude refresh available when Keychain access is disabled by using memory-only cookie caches and preventing background Claude prompts.
- Claude: isolate cached credentials by profile, preserve enterprise spend-cap extra usage, and keep the account Weekly quota ahead of exhausted model carve-outs.
- Codex: bound and resume cost scans across very large session corpora so they do not pin a CPU core or lose history.
- Amp: map subscription-plan usage to percentage windows instead of reporting a misleading cookie error.
- Grok: let explicit cookie refresh import and validate a browser session for safe background reuse.
- Hooks: preserve configured hooks across config saves and ignore stale hook launches from other installations.
- Menu: prioritize exhausted automatic-display windows while preserving provider-specific preferences.
- Widgets: prevent quota-reset reload loops and remove the unintended dark background overlay.
- Refresh: prevent macOS 14 launch crashes caused by TaskLocal task-allocation corruption.
- Menu bar: render custom-layout provider icons at native size with correct light/dark tinting.
- Menu: prefer weekly quota windows for the switcher’s weekly progress, with provider-specific fallback.
- Command Code: improve progress-bar contrast in dark mode.
- Widgets: keep cost rows on one line with large token counts.
- OpenCode/OpenCode Go: preserve computed sub-1% usage percentages instead of rescaling them as direct fractions.
- OpenCode Go: prefer local usage for unscoped Auto refreshes while keeping account- and workspace-scoped requests web-first.
- StepFun: keep password-login web ID headers aligned with the anonymous token.
- Menu bar: refresh custom cost and reset tokens when their source data or displayed boundary changes.
- Usage: normalize session-equivalent forecasts against aligned partial-session samples.
- Usage: align current/latest and historical cost and token metrics by period.
- Codex: exclude parent-copied prefixes from compact subagent usage when the fork boundary matches the parent snapshot.
- Usage & Spend: render share-card PNG exports without black backgrounds and keep complete model rows visible beside incomplete sources.
- ElevenLabs: clamp character and voice-slot usage percentages at 100% during overage.
- Ollama: reuse validated browser sessions and skip inaccessible Safari cookies during automatic fallback while retaining explicit permission guidance.

## 0.32.4.12 / iOS 1.11.3 — 2026-07-17

### Added
- Codex: show the backend-authoritative count of banked limit resets, the next
  exact expiration in the menu, and every known exact expiration in provider
  details without inventing timestamps when the backend returns a partial list.
- ZenMux: add Management API usage with five-hour and weekly quotas, subscription expiry, and USD PAYG balance. Thanks @kays0x!

### Fixed
- Claude: preserve each account’s last-good OAuth usage during rate limits and isolate retry cooldowns per credential. Thanks @ruushu!
- Claude: recover a missing credentials file from a valid Claude Code Keychain item without showing Keychain UI when Never prompt is selected (#1975). Thanks @OfficialAbhinavSingh!
- Codex cost usage: invalidate cached fork totals when the parent session appears, changes, or resolves to a different file, preventing stale inherited baselines. Thanks @xx205!
- Cursor: bind interactive account login to one readable browser, preserve the active session on cancellation or failure, and prevent background refreshes from replacing the selected account. Thanks @chapati23!
- Menu bar: prevent duplicate provider items when usage updates re-enter initial status-item setup (#2162). Thanks @ss251!
- Codex cost usage: count restarted subagent token counters without subtracting the parent's unrelated cumulative baseline (#2193). Thanks @qiuruiyu and @harjothkhara!
- Ollama: clarify that Cloud quota limits require a signed-in browser session with cookies when API-key verification is used.
- Claude: suppress duplicate all-model scoped quota rows beside the primary Weekly row.
- Copilot: hide quota bars explicitly marked unlimited while preserving finite Premium and Chat quotas. Thanks @Zihao-Qi!

### Changed

- Synced upstream CodexBar changes through `e6b2ea490`, including ClinePass,
  LongCat, Neuralwatt, the unified usage and spend dashboard, private local
  usage-sharing cards, Cursor token-cost reporting, and hardened shared-stat
  aggregation while preserving QuotaKit release ownership and CloudKit setup.

## 0.32.4.11 / iOS 1.11.1 — 2026-07-11

### Added
- Menu bar: add a display option to show reset time when quota runs out.
- Kimi K2: add a Usage Dashboard shortcut to the legacy credits page.
- Codex: add GPT-5.6 Sol, Terra, and Luna pricing, including alias and
  cache-write handling.
- Codex: add a provider option to hide Spark quota rows without hiding credits
  or other extra usage.
- Documentation: add Azure OpenAI provider setup and troubleshooting notes.
- sub2api: add group-key usage with daily, weekly, and monthly quotas, multi-account switching, wallet balance, and expiry details. Thanks @weirdo-adam!
- Kimi: reuse fresh signed-in Kimi Code CLI credentials in Auto mode without refreshing or rewriting CLI-owned authentication state. Thanks @Leechael!
- Factory: add API-key usage authentication with API-first Auto mode and recoverable fallback to the existing web session path. Thanks @araa47!
- Developer tooling: add an offline adaptive-refresh replay CLI for comparing policy behavior against caller-supplied JSONL traces. Thanks @hhh2210!

### Fixed
- Kiro: clear inherited signal masks in spawned pipe and PTY probes, preventing the CLI from ignoring termination under a blocked parent mask. Thanks @txarly89!
- CLI PTY: preserve deadline timeouts while draining late output and classify child exits by observation time, eliminating scheduler-dependent success/timeout races. Thanks @kiranmagic7!
- Quota warnings: isolate threshold episodes by stable account ownership so one account cannot duplicate or suppress another account's alert. Thanks @vincent-peng!
- Claude: cache successful CLI version probes for 30 minutes while invalidating on executable changes, avoiding repeated PTY launches without retaining failed or stale wrapper results. Thanks @Yuxin-Qiao!
- Linux CLI: bootstrap the configured IANA timezone before Foundation startup on non-FHS systems, preventing SIGILL on NixOS (#2127). Thanks @xikhar!
- Ollama: release temporary dashboard network sessions after each fetch, preventing repeated refreshes from retaining delegates and URL-cache resources. Thanks @astuteprogrammer!
- Amp: release temporary API and dashboard network sessions after every fetch, preventing repeated refreshes from retaining delegates and URL-cache resources.
- Linux CLI: prevent usage rendering from crashing in Foundation bundle discovery when formatting rate windows. Thanks @thanthi-del!
- CLI: defer login-shell PATH probes until Codex RPC launch, preserve login PATH for explicit script overrides, and reap session-escaped helpers without cross-probe descriptor inheritance. Thanks @anagnorisis2peripeteia!
- Menus: keep overview provider-row clicks reliable during live menu rebuilds without stealing nested Copy or plan actions. Thanks @Yuxin-Qiao!
- Startup: load persisted plan-utilization history away from the main thread so mature histories no longer delay app launch. Thanks @Yuxin-Qiao!
- Provider cleanup: prevent in-flight usage, status, token-cost, and cached-hydration work from republishing stale state after a provider is disabled, unavailable, or re-enabled. Thanks @Yuxin-Qiao!
- Agent Sessions: coalesce overlapping unchanged remote refresh requests so menu opens do not repeat Tailscale discovery and SSH passes. Thanks @Yuxin-Qiao!
- Agent Sessions: keep Tailscale discovery headless and fall through across installed CLI variants, preventing repeated Tailscale menu-bar launches. Thanks @willsarg!
- Cost usage: zero the scanner's 60-second refresh debounce on app-driven fetches so non-forced refreshes (hourly timer, post-launch, scope/settings changes) reflect rows appended between fetches instead of serving a stale snapshot that `UsageStore.tokenFetchTTL` then pins for up to an hour (#2089). Thanks @Yuxin-Qiao!
- Codex cost usage: contain interleaved cumulative counters from Ultra-mode fork lineages so repeated lineage switches cannot inflate token and cost history (#2037). Thanks @Zihao-Qi!

### Changed

- Synced upstream CodexBar Mac changes through `7465c6a11`, including reliable
  overview-card click routing, Kimi Code CLI credential reuse, fresh cost
  snapshots, and Sub2API support while preserving QuotaKit release ownership,
  branding, config paths, CloudKit setup, and iOS build numbers.
- Synced upstream CodexBar Mac fixes through `99c3d94d4`
  (`a0102190e..99c3d94d4`), including Claude Auto fallback when expired CLI
  credentials only have MCP Keychain state while preserving QuotaKit release
  ownership, appcast metadata, config paths, CloudKit setup, and iOS build
  numbers.
- Synced upstream CodexBar Mac fixes through `a0102190e`
  (`820bfa145..a0102190e`), including Codex weekly reset-boundary ownership for
  quota-reset celebrations while preserving QuotaKit release ownership, appcast
  metadata, config paths, CloudKit setup, and iOS build numbers.
- Synced upstream CodexBar Mac fixes through `820bfa145`
  (`98de97833..820bfa145`), including Gemini OAuth recovery when current CLI
  installs omit `oauth2.js` and the upstream Pi cumulative-token scanner revert,
  while preserving QuotaKit release ownership, appcast metadata, config paths,
  CloudKit setup, and iOS build numbers.
- Synced upstream CodexBar Mac improvements through `98de97833`
  (`2d58d098..98de97833`), including the settings pane reorganization,
  leading-aligned settings footers, menu viewport restoration after manual
  refresh, stale menu highlight fixes, Claude OAuth Keychain pre-alert
  cooldowns, passive Claude probe update suppression, bounded Codex session
  metadata reads, Pi Ultra token overcount fixes, Cursor/filter widget options,
  ChatGPT-bundled Codex CLI discovery, Kimi K2 credential messaging, and
  broader menu/refresh/widget/provider test coverage while preserving QuotaKit
  release ownership, appcast metadata, CloudKit setup, config paths, Cursor
  mobile label parity, and iOS build numbers.
- Synced upstream CodexBar Mac improvements through `2d58d098`
  (`3b039d15..2d58d098`), including Codex OAuth account isolation, Spark quota
  visibility, reset-time menu display, Kimi K2 dashboard links, GPT-5.6
  pricing, bounded unknown-model pricing refresh, CLI serve timeout retention,
  Claude reset occurrence handling, Claude never-prompt Keychain cache
  hardening, Azure OpenAI provider documentation, cost-history chart stability,
  Catalan localization updates, and broader provider/runtime test coverage
  while preserving QuotaKit release ownership, appcast metadata, CloudKit
  setup, config paths, and iOS build numbers.

### Fixed

- Codex: require weekly reset-boundary advancement before celebrating quota
  resets while keeping same-email workspace accounts isolated.
- Codex accounts: isolate authenticated OAuth and browser-cookie requests from
  shared URL caches and cookie stores.
- Claude OAuth: honor QuotaKit's never-prompt Keychain policy in bundled CLI
  paths and defer stale cache cleanup until Keychain access is re-enabled.
- Claude OAuth: let Auto mode fall through when expired CLI credentials only
  have MCP Keychain state, avoiding doomed background refresh attempts.
- CLI server: retain timed-out route and provider work until it actually exits.
- Token costs: coalesce bounded pricing-catalog refreshes when newly observed
  models are still unpriced.
- Cost history: keep model breakdown menus steady while hovering and make
  overflowing histories scrollable.
- Catalan: complete current strings and enforce catalog parity.

## 0.32.4.10 / iOS 1.11.1 — 2026-07-07

### Added

- Agent Sessions: list and focus live local or SSH-discovered Codex and Claude
  Code sessions from the menu and CLI.
- Wayfinder: add opt-in local gateway health, routing, savings, and latency
  usage with configurable loopback URL support.
- Claude: show opt-in read-only claude-swap accounts as stacked usage cards
  without delaying ambient refreshes.
- Claude: switch inactive claude-swap accounts directly from stacked usage
  cards through claude-swap without reading Claude credentials.
- Claude CLI: surface model-scoped weekly limits alongside all-model usage
  without duplicating matching web limits.
- Quota warnings: add opt-in predictive pace alerts for Codex and Claude
  session and weekly limits, with one alert per risk episode.
- Documentation: add provider references for Mistral, Perplexity, Qoder, and
  Synthetic, plus Wayfinder setup and troubleshooting.
- Widgets: make Kimi available with Weekly, Rate Limit, and Monthly quota rows.

### Changed

- Synced upstream CodexBar Mac improvements from the previous QuotaKit Mac
  release through `3b039d15`, including Agent Sessions, CLI cards,
  claude-swap accounts, Kimi widgets and subscription rows, Claude scoped
  weekly CLI limits, Wayfinder, CrossModel, Doubao Coding Plan, Qoder,
  Mistral, Perplexity, Synthetic, and ClawRouter provider docs, Codex credit
  and cost-history improvements, provider refresh scoping, quota warning
  threshold and predictive warning settings, settings and menu resilience,
  provider config relay scoping, localization updates, and release validation
  hardening while preserving QuotaKit release ownership, appcast metadata,
  CloudKit setup, config paths, and iOS build numbers.

### Fixed
- Codex menu: hide error-only optional Credits and OpenAI web setup diagnostics
  while keeping them visible in provider Settings.
- Codex quotas: show the session quota as unavailable while an exhausted weekly
  limit is still binding, including menu-bar icons and widgets.
- Codex cost history: reuse cached aggregate pricing and one pricing catalog
  across daily and project reports, carry fresh cache state across launches,
  and treat unpriced models as migrated.
- Kimi K2: reject non-finite credit and token values before they reach menus,
  CLI output, or widgets.
- Kimi: show the five-hour rate limit before the weekly quota while preserving
  existing menu-bar metric preferences.
- Menus: scope manual refresh state to the provider being refreshed, allowing
  independent provider refreshes without greying unrelated rows.
- Claude history: quarantine same-directory account-switch samples until
  credential ownership is stable, preventing plan-utilization history from
  crossing accounts.
- Sakana AI: parse server-rendered quota reset timestamps as UTC instead of
  device-local time.
- Widgets: honor the shared used-versus-remaining display preference.
- Claude: isolate OAuth history per credential, preserve continuity through
  refreshes, bound stale web requests so Auto can reach CLI fallback, add a
  Session + Weekly menu-bar metric, preserve real zero-usage sessions, and
  prevent logged-out background Auto fallbacks from opening browser OAuth.
- Keychain prompts: explain macOS password entry and the opt-out path before
  access begins.
- OpenAI API: explain unsupported project service-account keys instead of
  surfacing a generic credit-balance authorization error.
- Codex and Pi cost history: invalidate stale pricing caches and avoid
  double-billing cached input.
- Antigravity CLI: reuse an authenticated same-user `agy` server for faster
  one-shot usage checks while excluding QuotaKit-owned managed sessions.
- Quota warnings: add on-screen alert presentation and session-reset
  celebration handling while keeping iPhone push writes intact.
- Quota warnings: use compact per-window threshold editors that save on focus
  loss, Return, or window close while preserving provider inheritance.
- Ollama: validate API keys against an authenticated endpoint instead of the
  public model catalog while preserving refresh cancellation.
- Display settings: keep display mode, work days, multi-account layout, and
  cost summary selectors interactive on macOS 27.
- Antigravity: recover CLI listening ports from Linux procfs when `lsof` is
  unavailable, including process network namespaces.
- Gemini: prefer Google's paid-tier plan label over generic Free, Workspace,
  or Paid fallbacks while preserving acronym casing in the CLI.
- Codex: avoid false session-reset celebrations from transient zero-usage
  samples until the reset boundary advances.
- Settings: keep visual-only preference changes and provider reordering on
  cached UI paths instead of refreshing provider quotas while preserving
  refreshes for data-affecting settings.
- MiMo: flag a stale local-fallback cache in the summary so an old
  `Scripts/mimo-usage.py` cache is not misread as live usage.
- Widgets: show token-cost rows with their own age when they lag a fresh quota
  snapshot, and retry fast token-scan failures without waiting out the hourly
  cache.

## 0.32.4.9 / iOS 1.11.1 — 2026-06-28

### Changed

- Synced upstream CodexBar Mac improvements through `e810f7e`
  (`af13c528..e810f7e`), including Codex credit-limit display, Sakana AI,
  live status submenus, Kiro PTY usage loading, browser cookie
  discovery hardening, CLI `/usage` provider isolation, Codex usage-only refresh
  enrichment fixes, privacy redaction, z.ai team usage, Mistral Vibe cookie
  restoration, cost-cache correctness, and menu performance updates.

### Fixed

- Usage pace: keep rounded on-track deficit and reserve labels visible instead
  of collapsing all on-track deltas to "On pace".
- Usage display: keep positive values below one percent visible instead of
  rounding them to zero.
- Kiro: run account, usage, and context commands through a PTY so current CLI
  versions return usage without timing out.
- OpenAI web: ignore stale profiles from removed browsers, discover registered
  installs outside standard app folders, and surface browser-profile access and
  cookie-load timeout diagnostics.
- CLI server: collect `/usage` providers concurrently under finite per-provider
  deadlines so one hung provider degrades to its own error row without discarding
  healthy results.
- Privacy: hide account and team identity values without showing placeholder
  text or empty account rows.
- Codex: avoid monthly-credit CLI enrichment during usage-only OAuth refreshes.
- Menu bar: show pace as `0%` instead of a signed `+0%` or `-0%` when the pace
  delta rounds to zero.
- Menu: align the persistent Refresh row with native actions, keep Settings,
  About, and Quit keyboard-navigable, and use a narrower Usage Dashboard icon.

## 0.32.4.8 / iOS 1.11.1 — 2026-06-23

### Changed

- Synced upstream CodexBar Mac improvements through `af13c528`
  (`ef8007fc..af13c528`), including CLI pace output, CI observability and
  dependency updates, stricter blank-localization checks, and broader
  provider/runtime test coverage.

### Fixed

- Claude: stop installed-version checks from invoking a login shell and
  triggering unwanted Keychain prompts.
- Usage totals: keep Today tied to the current local calendar day across cost,
  Admin API, and Poe surfaces instead of showing the latest historical bucket.
- Antigravity: align compact icons and automatic highest-usage selection with
  grouped Gemini and Claude/GPT quota lanes while ignoring non-renderable
  cadences.
- Memory pressure: finish isolating utility-queue source reads from main-actor
  state to prevent the remaining callback crash.
- Localization: reject blank translated values and restore affected Vietnamese
  provider prompts.

## 0.32.4.7 / iOS 1.11.1 — 2026-06-18

### Changed

- Synced upstream CodexBar Mac improvements through `ef8007fc`
  (`9e7a70a..ef8007fc`), including endpoint-override hardening for Azure
  OpenAI, Deepgram, z.ai, and MiMo, private Codex OAuth auth-file writes,
  redacted diagnostic output files, CLI `/health` build-version reporting,
  Claude CLI rate-limit backoff, MiniMax token-plan recovery, menu refresh
  behavior, generated `llms.txt` linting, and broader provider/runtime test
  coverage.
- Synced upstream CodexBar Mac improvements through `9e7a70a`
  (`3f3e2f4a..9e7a70a`), including usage-card spacing parity with the Overview
  layout, locale-checker diagnostics, Linux Swift toolchain CI caching, and
  upstream 0.37.1 changelog provenance.
- Synced upstream CodexBar Mac improvements through `3f3e2f4a`
  (`2fd5bccf..3f3e2f4a`), including Burn Down widgets, Codex profile-home
  accounts and combined menu metrics, Bedrock CloudWatch activity, Claude web
  session renewal persistence, MiniMax/Command Code/OpenCode Go fixes, compact
  native menu action rows, menu/chart responsiveness fixes, package-size
  stripping, static Linux CLI build support, localization updates, and broader
  provider/runtime/widget test coverage.
- Synced upstream CodexBar Mac improvements through `2fd5bccf`
  (`05545feb..2fd5bccf`), including Codex reset-credit display, Cursor
  personal spend beside team pools, Mistral monthly usage, storage breakdown
  details, provider-sidebar sorting, usage-confidence metadata, memory-pressure
  cache trimming, process-output bounds, Kiro/Cursor/Antigravity quota fixes,
  Windsurf Devin import updates, Codex web timeout hardening, localization
  updates, Antigravity highest-usage ranking alignment, provider-colored inline
  usage dashboard bars, MiMo auth-redirect retries, cookie-cache timeout
  ordering stabilization, and broader provider/runtime test coverage.

### Fixed

- Mac updates: prevent launch and background refresh from showing Keychain
  permission prompts after an app update.
- Keychain migration: update existing credential accessibility in place without
  reading secret values or deleting/re-adding items, and retry safely later when
  macOS reports that interaction would be required.
- Claude OAuth: limit promptable Keychain reads to explicit user actions such as
  opening the menu or running a manual refresh.

## 0.32.4.6 / iOS 1.11.1 — 2026-06-16

### Changed

- Synced upstream CodexBar Mac improvements through `0.35.1` development
  (`1d39e0ca..2e4b3556`), including Antigravity quota-summary pooling,
  transient launch retries, Linux HTTP probing, Gemini API-key auth recognition,
  MiMo balance/token usage, local session-log fallback, prompt refresh failures,
  browser-cookie isolation hardening, weekly pace work-day configuration,
  open-menu usage refresh, status-menu appearance fixes, editable cost-history
  settings, Command Code credit resilience, and release dSYM/Sparkle signing-path
  validation helpers.
- Synced upstream CodexBar Mac improvements through `b1e52908`
  (`2e4b3556..b1e52908`), including explicit provider registration, shared
  token/environment/cookie resolution, a LiteLLM provider, Italian/Indonesian/
  Polish/Arabic/Persian/Thai Mac localizations, bounded subprocess output
  draining, Claude cookie and OAuth ownership tests, Copilot reset-time display,
  menu/provider refresh coordination, usage snapshot preservation, provider
  readiness test stabilization, broader provider/runtime test coverage, and
  website provider logo refreshes.
- Synced upstream CodexBar Mac improvements through `ac01d736`
  (`b1e52908..ac01d736`), including Poe, Chutes, and Zed provider
  integrations, XDG config-home support adapted to QuotaKit config paths,
  Kiro helper process cleanup, Antigravity reset-time parsing, menu/status
  refresh fixes, widget and usage-pace display updates, localization updates,
  provider website assets, and broader provider/process test coverage.
- Synced upstream CodexBar Mac improvements through `05545feb`
  (`ac01d736..05545feb`), including LiteLLM budget spend display,
  manual-refresh quota stability, non-interactive menu-card hover behavior,
  and stricter app-locale placeholder validation.
- Antigravity: prefer app and `agy` quota summaries, group usage into Gemini and Claude + GPT session/weekly pools, and preserve IDE and OAuth fallbacks. Thanks @Zihao-Qi!
- Antigravity: show structured quota reset timestamps from the current `resetTime` field (#1553). Thanks @akunzai!
- Configuration: honor absolute `XDG_CONFIG_HOME` paths while rejecting relative paths and preserving QuotaKit config precedence (#1562). Thanks @kiranmagic7!

### Fixed

- Mac updates: package customer builds with the main Sparkle appcast URL and
  add a release lint guard so future updates do not point at a branch feed.
- Menu bar: preserve native AppKit image-row alignment when returning to cached provider content in the open merged menu (#1560). Thanks @Zihao-Qi!
- Menu bar: defer hosted submenu reconstruction until an active refresh finishes so partial provider data cannot replace the visible menu (#1556). Thanks @Yuxin-Qiao!
- Weekly pace: suppress the “Lasts until reset” label when the projected run-out risk is nonzero (#1561). Thanks @kiranmagic7!
- Antigravity: retry transient `Text file busy` launch failures while the CLI executable is being replaced.
- Antigravity: fall back to loopback HTTP for local CLI and language-server probes on Linux, where self-signed localhost TLS cannot be trusted (fixes #1508). Thanks @zodiacfireworks!
- Codebuff: enforce the optional subscription grace period even when the transport ignores cancellation.
- Copilot: show the shared quota reset date for limited premium and chat usage windows. Thanks @Zihao-Qi!
- Codex: keep managed login timeouts bounded while preserving captured output when detached helpers retain stdout or stderr.
- Claude: keep segmented multi-account menus scoped to the selected account while its refresh is in flight (fixes #1527).
- Command Code: keep showing available credits after the bounded optional subscription grace, including when the transport ignores cancellation (fixes #1131).
- DeepSeek: keep balance refreshes responsive when optional usage-summary work ignores cancellation.
- OpenRouter: keep credit refreshes responsive when optional key-quota enrichment ignores cancellation.
- Provider probes: stop waiting indefinitely for inherited output pipes after subprocesses or CLI version checks exit (fixes #1531).
- Menu bar: update visible usage values in place when a manual refresh completes instead of leaving the open provider card stale until the menu is reopened (fixes #1516).
- Gemini: recognize the current `gemini-api-key` CLI auth setting so API-key sessions show the supported OAuth guidance instead of a misleading not-logged-in error (fixes #1511).
- Kiro: keep usage refreshes bounded and clean up CLI helpers when they retain output pipes, ignore termination, or are cancelled (fixes #1533). Thanks @kiranmagic7!
- Gemini: keep fnm package discovery bounded when helper descendants retain output pipes or ignore termination (fixes #1534). Thanks @kiranmagic7!
- Xiaomi MiMo: cancel optional token-plan requests when the required balance request fails instead of delaying the error for up to 30 seconds.
- Settings: make the cost history window directly editable by keyboard while preserving the existing stepper and 1–365 day bounds (fixes #1499). Thanks @kiranmagic7!
- OpenCode Go: show Zen balances for accounts without subscription usage windows, including when the balance request takes longer than optional enrichment (fixes #1476). Thanks @kiranmagic7!
- Website: replace the remaining Devin, LiteLLM, and T3 Chat provider letter tiles with logo assets.

## 0.32.4.5 / iOS 1.11.1 — 2026-06-11

### Changed

- Synced trusted upstream CodexBar Mac improvements after `v0.32.4`, including
  Codex account/auth hardening, MiniMax quota fixes, menu performance updates,
  merged provider-switching hang fixes, Claude probe cleanup,
  Antigravity/Alibaba/Cursor fixes, and additional Mac localizations.
- Synced upstream CodexBar Mac improvements through `0.33.1` development,
  including a security fix that blocks credentialed provider redirects leaving
  the original HTTPS origin, a new Devin usage provider, Cursor legacy
  request-quota and Full Disk Access hint fixes, Copilot unlimited chat quota
  display, Codex cost visibility without quotas, updated Claude usage pricing
  and web session recovery, Doubao false-exhaustion fixes, cost scanner
  threading and cancellation overhauls, broad menu performance and
  width-stability work, a configurable terminal app for Open Terminal, expanded
  MiMo browser support, and Japanese localization.

## 0.32.4.4 / iOS 1.11.1 — 2026-06-08

### Fixed

- Show the QuotaKit app symbol in the Mac menu bar before the first quota
  snapshot is available, instead of rendering an empty initial status item.
- Updated the menu bar visibility guidance to use QuotaKit product naming.

## 0.32.4.3 / iOS 1.11.1 — 2026-06-08

### Fixed

- Renamed the shipped Mac app bundle, executable, widget extension, and bundled
  CLI helper to QuotaKit-branded runtime names.
- Added a signed Mac disk image with a drag-to-Applications install window for
  direct downloads.

### Notes

- Sparkle updates continue to use the signed ZIP enclosure for compatibility;
  direct website downloads use the new DMG installer.

## 0.32.4.2 / iOS 1.11.1 — 2026-06-07

### New

- Published the first Columbus Labs Mac download for QuotaKit.
- Added a signed and notarized universal macOS build for Apple silicon and Intel Macs.
- Added the Mac setup page at `https://columbus-labs.com/quotakit/mac`.

### How it works

- Install QuotaKit on your Mac, move it to Applications, and turn on iCloud Sync.
- The iPhone app reads synced AI quota, usage, cost, history, widget, and alert
  summaries from iCloud after the Mac app is set up.
- Provider credentials and browser sessions stay local to the Mac. QuotaKit syncs
  sanitized usage summaries, not provider secrets.

### Notes

- Mac updates are distributed through GitHub Releases and Sparkle.
- This release pairs the Mac app with iOS 1.11.1.

## 0.32.4.1 / iOS 1.11.0 — 2026-06-03

### Changed

- Paired the Mac app with iOS 1.11.0.
- Improved synced provider data quality and iPhone navigation with provider search.
- Kept CloudKit and sync wire formats compatible across mixed Mac and iPhone versions.

## 0.31.0.2 / iOS 1.10.0 — 2026-06-02

### Fixed

- Forced cost caches to re-scan after the parser update so Codex and Claude cost
  cards report fresh values instead of stale cached attribution.

## 0.31.0.1 / iOS 1.10.0 — 2026-05-30

### Added

- Added DeepSeek web-session usage and cost summaries on iOS.
- Added synced Codex Spark and Antigravity quota lanes.
- Improved cost cards with request counts and synced currency display.

## 0.29.0.1 / iOS 1.9.0 — 2026-05-27

### Added

- Added synced support for Azure OpenAI, Alibaba Token Plan, and T3 Chat.
- Added cost-history improvements, model breakdowns, and provider detail updates.

### Notes

- Older product and upstream release details remain available in repository history.
