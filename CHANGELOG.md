# Changelog

## Upstream sync — 2026-07-17

- Integrated upstream through `63215da42`, including ClinePass and LongCat providers, the unified usage and spend dashboard, external quota/provider hooks, safer background credential discovery, account-scoped quota and cost fixes, and hardened CLI/dashboard serving.
- Retired the unverified Kimi K2 and CrossModel Mac relays while preserving historical mobile sync decoding, and added ClinePass/LongCat mobile notification and presentation parity.
- Preserved QuotaKit and Columbus Labs public identity, release and appcast ownership, CloudKit configuration, shipped upstream version tracking, and all Mac/iOS build numbers.

## Upstream sync — 2026-07-16

- Integrated upstream through `6d71af30`, including hardened Cursor account switching, corrected Codex restarted-subagent and fork-baseline accounting, thread-safe browser/keychain helpers, isolated Claude OAuth rate-limit recovery, no-prompt Claude credential recovery, unlimited Copilot quota suppression, status-item reuse, and ZenMux Management API support.
- Preserved QuotaKit's public identity, release metadata, CloudKit configuration, account-scoped sync behavior, and build numbers.

## Upstream sync — 2026-07-15

- Integrated upstream through `aea62e047`, including suppression of duplicate Claude all-model quota rows, clearer Ollama Cloud-quota guidance, and a more reliable shell cleanup timeout test.
- Preserved QuotaKit's public identity, release metadata, CloudKit configuration, and build numbers.

## Upstream sync — 2026-07-14

- Integrated upstream through `c61e01e77`, including account-scoped quota warnings, reliable PTY deadline output draining, inherited signal-mask cleanup, process cleanup, provider-version probe caching, temporary-session lifetime fixes, and headless Tailscale session discovery hardening.
- Preserved QuotaKit's account-scoped depletion/restoration state, iOS quota-transition writes, public identity, release metadata, CloudKit configuration, and build numbers.

## Upstream sync — 2026-07-12

- Integrated upstream through `fd1b6c780`, including safer provider refresh ownership, asynchronous plan-history loading, Factory API-key usage, Sub2API support, and Codex quota recovery hardening.
- Preserved QuotaKit release metadata and added Sub2API parity for iOS colors and CloudKit quota notifications.

Notable QuotaKit Mac and cross-platform release changes are documented here.

Older upstream history is intentionally preserved in Git, but this file now focuses
on Columbus Labs QuotaKit releases and product-facing changes.

## 0.32.4.12 / iOS 1.11.1 — Unreleased

### Added
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
