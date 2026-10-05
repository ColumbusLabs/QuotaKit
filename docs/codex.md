---
summary: "Codex provider data sources: OpenAI web dashboard, Codex CLI RPC, credits, and local cost usage."
read_when:
  - Debugging Codex usage/credits parsing
  - Updating OpenAI dashboard scraping or cookie import
  - Changing Codex CLI RPC or diagnostic PTY behavior
  - Reviewing local cost usage scanning
---

# Codex provider

Codex has three automatic usage data paths (OAuth API, web dashboard, CLI RPC) plus a manual CLI PTY diagnostic parser and a local cost-usage scanner.
The OAuth API is the default app source when credentials are available; web access is optional for dashboard extras.

## Data sources + fallback order

### App default selection (debug menu disabled)
1) OAuth API (auth.json credentials).
2) CLI RPC through `codex app-server`.
3) If OpenAI web extras are enabled and a matching OpenAI web session is available (Automatic or Manual cookies),
   dashboard extras load as a separate follow-up refresh and the source label becomes `primary + openai-web`.

Usage source picker:
- Preferences → Providers → Codex → Usage source (Auto/OAuth/CLI).

### CLI default selection (`--source auto`)
1) OpenAI web dashboard (when available).
2) Codex CLI RPC through `codex app-server`.

### OAuth API (preferred for the app)
- Reads OAuth tokens from `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`).
- Refreshes access tokens when `last_refresh` is older than 8 days.
- Calls `GET https://chatgpt.com/backend-api/wham/usage` (default) with `Authorization: Bearer <token>`.
- The app reads reset-credit inventory once per refresh with a best-effort
  `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits` using the same account-scoped OAuth context;
  the CLI requests it only when optional credits are included.
- The menu and provider settings list every still-available expiry, while the optional credits setting controls
  nearing-expiry notifications. QuotaKit does not redeem or modify reset credits.
- `rate_limit.primary_window` / `secondary_window` map to the session/weekly lanes.
- `additional_rate_limits[]` (model-specific limits such as GPT-5.3-Codex-Spark) map to named
  `UsageSnapshot.extraRateWindows` entries. Spark uses stable `codex-spark` / `codex-spark-weekly` ids and
  `Codex Spark 5-hour` / `Codex Spark Weekly` titles. When the field is absent, the snapshot is unchanged.
- Preferences → Providers → Codex → Visible usage items lets you hide individual Spark rows in menus, the Settings
  preview, and Overview. It does not change fetching, history, notifications, widgets, credits, or other extra limits.
- Explicitly enabling **External Codex OAuth sources** can reuse OpenCode's `openai` OAuth entry for remote
  quota when native Codex credentials are absent. It does not import OpenCode session token or cost history; see
  [OpenCode with Codex or OpenAI](opencode.md#using-opencode-with-codex-or-openai).
- Stacked account refreshes retain each managed account's selected workspace through usage publication and menu
  matching, even when its auth file names a different default workspace. Changing the selected workspace while a
  refresh is running discards the old workspace's result.
- System Account promotion fails closed when a managed selection differs from the auth file's default workspace.
  QuotaKit keeps that selection managed rather than silently promoting the default or rewriting Codex-owned auth.

### Managed account CLI (macOS)

Use `quotakit codex-accounts list --json` to find managed UUIDs and the current system-identity match,
then `quotakit codex-accounts promote <exact-uuid-or-email>` to promote an account explicitly. Duplicate
emails require the UUID. The app and CLI share the same preservation and workspace checks: displaced
live credentials are saved before an owner-only atomic replacement, and detected changes to either
auth file abort the replacement. A nonblocking process lock serializes participating account writers
and is released automatically after a crash. External Codex processes do not share that lock.

CLI promotion reads local files only and never requests Keychain access or starts login. It leaves
the app's display selection and running Codex processes alone; `CODEX_HOME` selects the live destination.
That destination must not alias a managed home, because the swap would overwrite its preserved credentials.
It does not renew expired credentials or enable unscoped fallback for managed workspaces. Continue to
use the affected row's **Reauthenticate** action or ordinary `codex login` scoped to that managed home
and intended workspace. A future CLI renewal command needs staged login and identity/workspace
validation before committing; `promote` is not a renewal workaround. See [CLI details](cli.md#managed-codex-accounts-macos).

### Advanced profile-home accounts
- Managed Codex accounts remain the default multi-account path.
- Advanced users can add existing Codex homes to `~/.quotakit/config.json` with
  `providers[].codexProfileHomePaths`.
- Each configured path must be absolute or start with `~/`, and point at a Codex home that contains `auth.json`.
- QuotaKit reads identity from the configured home, exposes it in the Codex account switcher, and scopes
  remote Codex fetches with `CODEX_HOME`.
- Profile homes are not copied, reauthenticated, or removed by QuotaKit.

Example:

```json
{
  "id": "codex",
  "codexProfileHomePaths": [
    "~/.codex-work",
    "~/.codex-personal"
  ]
}
```

### Same-email workspace labels

Account settings, the System Account picker, and the menu switcher retain the workspace name when it is available and personal information is visible.
With **Hide Personal Info** enabled, System Account submenu titles use stable numbered account labels; promotion targets, checked state, and availability are unchanged.
If the same email and workspace label would appear more than once (including missing names or the “Personal” fallback),
QuotaKit adds a stable eight-character hash of the workspace identity. The hash stays the same when selecting or promoting
that workspace and never exposes the full provider identifier. This is display-only; stored account metadata and
credential selection are unchanged. Separate profile homes for the same workspace also include a hashed source identity,
so their labels stay distinct without exposing paths. Compact switcher buttons keep the discriminator visible when space
is limited, using additional rows when needed.

### OpenAI web dashboard (optional, off by default)
- Enable it in Preferences -> Providers -> Codex -> OpenAI web extras.
- It exists for dashboard-only extras such as code review remaining, usage breakdown, and credits history.
- It is intentionally opt-in because it loads `chatgpt.com` in a hidden WebView and can materially increase battery or network usage.
- OpenAI web battery saver is a separate toggle. When enabled, routine background/settings-driven refreshes are reduced, but explicit manual refreshes still run.
- OpenAI web battery saver currently defaults to off.
- Preferences → Providers → Codex → OpenAI cookies (Automatic or Manual).
- URL: `https://chatgpt.com/codex/cloud/settings/analytics#usage`.
- Uses an off-screen `WKWebView` with a per-account `WKWebsiteDataStore`.
  - Store key: deterministic UUID from the normalized email.
- WebKit store can hold multiple accounts concurrently.
- Cookie import (Automatic mode, when WebKit store has no matching session or login required):
  1) Safari: `~/Library/Cookies/Cookies.binarycookies`
  2) Chrome/Chromium forks: `~/Library/Application Support/Google/Chrome/*/Cookies`
  3) Firefox: `~/Library/Application Support/Firefox/Profiles/*/cookies.sqlite`
  - Domains loaded: `chatgpt.com`, `openai.com`.
  - No cookie-name filter; we import all matching domain cookies.
- Cached cookies: Keychain cache `com.steipete.quotakit.cache` (account `cookie.codex`, source + timestamp).
  Reused before re-importing from browsers.
- Manual cookie header:
  - Paste the `Cookie:` header from a `chatgpt.com` request in Preferences → Providers → Codex.
  - Used when OpenAI cookies are set to Manual.
- Account match:
  - Signed-in email extracted from `client-bootstrap` JSON in HTML (or `__NEXT_DATA__`).
  - If Codex email is known and does not match, the web path is rejected.
- Web scrape payload (via `OpenAIDashboardScrapeScript` + `OpenAIDashboardParser`):
  - Rate limits (5h + weekly) parsed from body text.
  - Credits remaining parsed from body text.
  - Code review remaining (%).
  - Usage breakdown chart (Recharts bar data + legend colors).
  - Credits usage history table rows.
  - Credits purchase URL (best-effort).
- Errors surfaced:
  - Login required or Cloudflare interstitial.

### Codex CLI RPC (automatic CLI source)
- Launches local RPC server: `codex -s read-only -a never app-server`.
- On fully enforcing macOS hosts, standalone hardened-runtime CLI Gatekeeper verdicts are reused for at most five minutes while stat
  metadata and every architecture’s complete embedded signature remain unchanged. Page-protection opt-outs,
  unsigned or malformed files, and app bundles use fresh assessments. A process-wide host check requires full SIP,
  system code-signing enforcement, and readable boot arguments without enforcement overrides; failed or unknown
  checks retain fresh assessment. Malware/quarantine checks run per lookup. npm payload selection also runs on
  every lookup using the launch environment; only the selected standalone native file's assessment can be reused.
  Selected payloads inside app bundles stay uncached, including when reached through symlinks.
  Each identity read binds metadata and signature bytes to one open descriptor, then rechecks the pathname and
  resolved app ancestry after hashing before storing or returning a verdict.
- JSON-RPC over stdin/stdout:
  - `initialize` (client name/version)
  - `account/read`
  - `account/rateLimits/read`
- RPC reads are bounded: initialization has a longer startup budget, and normal requests have a shorter per-method
  timeout. On timeout, QuotaKit terminates the child `codex app-server` process so the stdout reader unwinds instead
  of leaving refresh stuck indefinitely.
- Provides:
  - Usage windows (primary + secondary) with reset timestamps.
  - Credits snapshot (balance, hasCredits, unlimited).
  - Account identity (email + plan type) when available.
- The plan from the fresh rate-limit response takes precedence over the account's cached plan after a subscription
  change. A missing or blank rate-limit plan falls back to the account response; email still comes from that account.
- App-server errors are terminal for the CLI strategy, except when Codex includes a recoverable `wham/usage` JSON body in the error text.
- If macOS blocks or quarantines the `codex` executable, QuotaKit records the launch failure and skips background CLI
  launches for 30 minutes. Use a manual refresh after reinstalling or unblocking `codex` to retry immediately.
- QuotaKit also discovers the Codex CLI bundled with current ChatGPT and legacy Codex desktop apps, even when `codex`
  is absent from the shell PATH. Discovery includes the current `codex-cli/bin/codex` launcher and skips known
  npm launchers whose selected native payload is unavailable, with a diagnostic to reinstall `@openai/codex`.
  The launcher's Node interpreter resolves the architecture and optional package location without evaluating `codex.js`;
  the recognized current `bin/codex` or legacy `codex/codex` layout selects the one payload to assess. Transitional
  launchers such as Codex 0.136 fall back to the legacy path only when the current path is absent, matching npm.
  Stale payloads cannot substitute for an existing but unusable selected binary, or a current-only launcher's missing
  binary. Other architectures cannot substitute either. Unknown layouts fail closed. RPC and PTY discovery
  preserve locator rejection instead of repeating an unfiltered `which` lookup. PTY discovery and status diagnostics
  use the caller's environment for preflight, so a rejected Node runtime cannot be rediscovered under the host environment.
  Healthy npm launchers retain
  PATH precedence; bundled fallbacks still require the existing app trust checks.
  Runtime inspection uses the shared executable finder, ignoring relative and empty PATH entries while retaining absolute
  install paths. Nonempty `NODE_OPTIONS` still prevents inspection, so discovery cannot run a working-directory interpreter
  or preload hook before assessing the payload; bundled fallbacks remain available.
- If managed Codex account login still reports a missing executable, turn on **Show debug settings** in
  **Settings > Advanced**, then check **Settings > Debug > CLI Paths**. When no Codex binary appears there, confirm
  `codex --version` works in Terminal, check `which -a codex` for stale duplicate installs, then run
  `npm install -g --include=optional @openai/codex@latest` before retrying Add Account.

### Codex CLI PTY diagnostics (`/status`)
- Manual/debug parser only; automatic background refresh and `QuotaKitCLI usage --source cli` do not launch bare Codex TUI.
- Kept for explicit diagnostics/parser coverage because bare `codex` TUI can start interactive auth and open browser tabs.
- Parses rendered `/status` output:
  - `Credits:` line
  - `5h limit` line → percent + reset text
  - `Weekly limit` line → percent + reset text
- Detects update prompts and surfaces a "CLI update needed" error.

## Account identity resolution (for web matching)
1) Latest Codex usage snapshot (from RPC, if available).
2) `~/.codex/auth.json` (JWT claims: email + plan).
3) OpenAI dashboard signed-in email (cached).
4) Last imported browser cookie email (cached).

## Credits
- Web dashboard fills credits only when OAuth/CLI do not provide them. Account-matched extra usage reconciles monthly caps and purchased balances separately.
- When usage reports workspace credits without an amount, an optional authenticated `remaining_balance` read uses the selected account's OAuth or browser session. Missing permission leaves usage and monthly-limit data available.
- A workspace balance attaches and persists only when the response account ID matches the selected account. An explicit unavailable observation suppresses an older cached balance; a later positive or zero read restores visibility. Usage-only refreshes preserve the account's prior observation. An account-scoped API result omits page-only history, plan detail, and code-review fields because the page exposes an email but no workspace ID.
- Workspace balances have no known total capacity, so the Mac credits card shows the amount without a monthly-cap progress bar. The iPhone sync keeps the separate monthly cap and omits a standalone workspace balance from budget rows.
- CLI RPC: `account/rateLimits/read` → credits balance.
- CLI PTY diagnostics can still parse `Credits:` from saved/manual `/status` output.
- When a balance has no reported monthly cap, the menu chooses the next power-of-ten token scale for its bar and label.
  Reported caps keep their own scale.

## Weekly reset publication
- A suspicious drop from above 1% to 1% or lower is confirmed before publication. If the previous quota snapshot has no reset-credit inventory, two compatible exact OAuth reads may corroborate the reset when they show the same complete positive inventory with timestamps newer than that snapshot. Existing inventory still has to remain stable and fully explained; incomplete, stale, changed, or incompatible evidence keeps the prior quota published.
- If confirmation remains ambiguous, QuotaKit may retain a delayed candidate only for exact OAuth observations with compatible account and known plan identity, matching reset boundaries, and a stable complete positive reset-credit inventory. A later compatible exact observation can publish the reset after the 60-second minimum delay. Candidates expire after 30 minutes, and stale or incompatible evidence discards them.
- Reset diagnostics use fixed reason codes for candidate creation, delayed evaluation, and persistence decisions. They do not include account emails, workspace names, plan labels, credit IDs, or provider payloads. A persistence decision of `storeRequested` means the configured store API was called; it does not claim that durable storage succeeded.

## Cost usage (local log scan)

For a manual comparison with another development machine, run `quotakit cost --provider codex --remote <ssh-host>`.
Both hosts scan their own native Codex logs once and return separate summaries, retaining their own day boundaries,
pricing provenance, missing values, and incomplete-request counts. Only bounded totals cross SSH. A remote error keeps
the local result and returns a nonzero exit code. See [CLI host reporting](cli.md) for the versioned summary contract.

- A queued refresh does not restart a cost-history worker after it exits paused. A later explicit refresh can retry.
- Menu source selection:
  - By default, a selected managed account keeps its own `CODEX_HOME` session history.
  - **Local session cost estimates** is a Codex-only opt-in that instead scans this Mac's ambient `$CODEX_HOME`
    (or `~/.codex`) independently of quota, OAuth, web-dashboard, and administrator access.
  - Multi-account menus show an ambient ledger once under **This Mac**, honoring inline, submenu, or combined display.
    Managed-account and profile-home history is never promoted to this shared section.
  - Regular menu cost refreshes publish local session estimates even when global cost tracking is off. This does not
    enable other providers' cost scans; results still require the same provider configuration and history/account scope.
  - The local-only mode never makes a network request or uploads session content. It uses an existing local models.dev
    cache when available, then the bundled `CostUsagePricing` rates.
- Usage & Spend also includes the ambient Codex home when file-backed account discovery has no live identity, including keyring logins. A normalized ambient home already represented by an account is not added twice; named-account credential and cache ownership checks still apply.
- Source files:
  - Native Codex logs:
    - `~/.codex/sessions/YYYY/MM/DD/*.jsonl`
    - `~/.codex/archived_sessions/*.jsonl` (flat; date inferred from filename when present)
    - Or `$CODEX_HOME/sessions/...` + `$CODEX_HOME/archived_sessions/...` if `CODEX_HOME` is set.
  - Supported pi sessions:
    - `~/.pi/agent/sessions/**/*.jsonl`
- Scanner:
  - Native Codex logs parse `event_msg` token_count entries and `turn_context` model markers; when both are present,
    `turn_context` is authoritative for the model bucket.
  - Paginated continuation files count only their owned usage when `history_base.thread_id` identifies an earlier
    page. Bounded scans retain the validated fork baseline and exact request index across restarts.
  - Direct forks inherit the parent's cumulative token counter at the fork timestamp, including inherited totals
    from earlier ancestors. A changed ancestor invalidates descendant baselines; unresolved parents keep child
    events buffered until the parent can be scanned within the refresh budget. A first post-boundary event whose
    cumulative and last totals match at or above an inherited counter stays unbilled and pending because the same
    observation can represent copied history or a new child turn.
  - Excess cached request rows are replayed from unchanged source files. The previous ledger stays available during
    bounded recovery; pricing is retained only for validated source requests and byte boundaries.
  - pi sessions count assistant-message usage rows and attribute `openai-codex` assistant usage to Codex.
  - pi assistant usage is bucketed by assistant-turn timestamp, so mixed-model pi sessions can contribute to multiple
    days/models correctly.
  - Conversation rows retain their canonical project folder and use the rollout's original working directory when
    resolving a relative `CODEX_SQLITE_HOME`. Thread names come from the matching Codex state database or session
    index, so projects sharing one Git root keep their own session metadata.
  - Project rows use the account source and full directory path as their identity, so equal folder names stay
    separate and saved-name changes do not split usage. Project and session labels use the closest matching saved
    project root from each relevant Codex state database; missing, ambiguous, or unreadable metadata keeps the
    folder name. Fresh scans and cached loads refresh these labels without rebuilding or changing usage totals.
  - Duplicate project labels include their paths for clarity. **Hide personal information** also hides those paths,
    and widget cost summaries contain aggregate values only.
  - Native conversation rows reuse the corrected cached per-file totals and existing pricing tables. They are hidden
    when pi usage joins the aggregate because the native-only rows would not reconcile with the merged total.

Independent desktop chats appear in a separate **Independent chats** section, using saved thread titles or a
neutral chat label instead of generated workspace folder names. Every contributing thread, including older files
from moved threads, must have an explicit marker in the selected Codex home's desktop state. Registered project
roots and current or legacy assignments veto stale markers; missing, malformed, or conflicting ownership keeps
the Projects fallback. A null project ID or an unregistered CLI folder alone never establishes chat ownership.
Project names and ownership share a bounded SQLite snapshot per database per refresh (1,024 roots and 4,096
candidate threads); desktop state reads are capped at 8 MiB. This leaves identities, totals, caches, and dashboard
and widget schemas unchanged. Privacy mode uses numbered chat labels and hides titles and paths through the
existing display identity projection.

- Cache:
  - Native Codex session store: `~/Library/Caches/CodexBar/cost-usage/cost-usage.sqlite`
  - pi-compatible session cache: `~/Library/Caches/CodexBar/cost-usage/pi-sessions-v7.json`
- Warm Codex scans reuse decoded history only when the locked SQLite baseline still certifies the same content.
  Freshness and priority-cursor updates share one checked metadata write; unexpected writes request a rescan.
  Hydrating an empty token history avoids rewriting content only when no snapshot rows exist, while clearing a
  non-empty history still removes those rows.
- Window: a visible rolling history of up to 365 days; routine background work scans 30 days.
- Timer-driven local-history refreshes have a 15-minute minimum (30 minutes in Low Power Mode). Manual disables
  that recurring timer, while startup refreshes, explicit refreshes, and pending Codex catch-up may still scan.
  The scanner's 60-second debounce is an internal limit, not the app refresh cadence.
- Pending local-history files receive bounded turns alongside fresh sessions. Unfinished files that received a turn
  rotate behind waiting files, and the queue persists across refreshes. Rotation alone does not count as scan progress;
  byte and time limits still bound each refresh.
- Automatic catch-up starts without assumed scan-time debt, then continues cheap discovery pages within a two-second
  burst capped at eight passes. Each pass receives the remaining scan time, and current-day publication continues
  through QuotaKit's validated-window and snapshot safeguards. The later duty-cycle delay uses cumulative active scan
  time, excluding shared account/provider queue waits, with a two-second minimum when the pass cap ends a shorter
  burst. Returning to automatic mode counts only the in-flight accelerated pass. App Low Power Mode still floors each
  scheduled delay; physical low-power and thermal pauses, no-progress detection, cancellation, and complete-history
  publication rules still apply.
- Parent discovery continues within those bounds after requesting forks leave the scan roots. Once discovery confirms
  a missing parent, fully read forks and their orphaned descendants stop keeping catch-up pending. Unresolved usage
  remains buffered and unmetered; a changed dependency retries accounting when parent history returns.
- Reporting windows overlapping the orphan fork's observed event span remain incomplete; independent dates may publish
  normally. A session start date alone cannot establish independence. Existing stored rows, replay buffers, and scan
  checkpoints remain intact because this change settles scheduling and checks coverage from existing metadata.

### Usage & Spend account rows

Settings → Usage & Spend performs a separate fixed 30-day scan for every visible Codex account. Each request freezes
the account source, exact Codex home, authentication fingerprint, and cache identity before scanning. A missing or
invalid home is omitted; it never falls back to ambient `~/.codex` or to the global Codex token snapshot.

These account rows intentionally exclude pi sessions because pi history is machine-local rather than owned by one
Codex account. The normal Codex cost menu and CLI scan continue to include supported pi history. The dashboard labels
its values as local estimates and keeps currencies separate.

## Managed account promotion and background tasks

After a managed account is promoted to the system Codex home, QuotaKit restarts an already running Codex app-server daemon for that same home. It first checks a recognized daemon PID and the CLI's `version` response against the resolved control socket, including socket and home symlinks. If the CLI probe or restart fails, the account switch remains complete and the app displays a manual-restart note. Credits and plan-history background tasks keep ownership tokens so an older cancelled task cannot clear a replacement task's handle.

## Key files

- Web: `Sources/QuotaKitCore/OpenAIWeb/*`
- CLI RPC + diagnostic PTY parser: `Sources/QuotaKitCore/UsageFetcher.swift`,
  `Sources/QuotaKitCore/Providers/Codex/CodexStatusProbe.swift`
- Cost usage: `Sources/QuotaKitCore/CostUsageFetcher.swift`,
  `Sources/QuotaKitCore/PiSessionCostScanner.swift`,
  `Sources/QuotaKitCore/PiSessionCostCache.swift`,
  `Sources/QuotaKitCore/Vendored/CostUsage/*`

### Recorded quota burndown

Plan Usage shows remaining quota from recorded samples in the active reset window alongside the existing utilization history chart. It labels the capture age and does not project a stale observation forward. Legacy 30-day Codex lanes use the same monthly normalization in both charts.

### Pricing aliases and historical reports

Codex `gpt-reserve` telemetry falls back to GPT-5.6 Luna pricing after an exact provider-qualified catalog lookup. Known historical Sol rates use each recorded event’s timestamp. Compatible parsed rows and scan checkpoints survive the pricing migration; derived report payloads are recalculated so stale estimates do not hide the alias correction.
