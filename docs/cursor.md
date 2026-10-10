---
summary: "Cursor provider data sources, external-browser account switching, and cursor.com APIs."
read_when:
  - Debugging Cursor usage parsing
  - Updating Cursor cookie import or session storage
  - Adjusting Cursor provider UI/menu behavior
---

# Cursor provider

QuotaKit fetches Cursor usage with a first-party session from Cursor.app or `cursor-agent login`, or with a cursor.com
cookie. Automatic mode prefers a valid Cursor.app token on macOS. On Linux, it tries cached and stored cookies before
Cursor.app and cursor-agent local logins; browser cookie import is unavailable.

## Data sources + fallback order

Manual cookie configuration is always the explicit override. Automatic mode follows app token → cached cookie → browser
cookie import → stored session on macOS, and cached cookie → stored session → local Cursor.app / cursor-agent login on
Linux. Explicit `web` mode never reads app credentials; Linux requires a configured manual cookie.

1) **Cached cookie header** (after app auth on macOS; first automatic source on Linux)
   - Stored after successful browser import.
   - Keychain cache: `com.steipete.codexbar.cache` (account `cookie.cursor`).

2) **Browser cookie import**
   - Cookie order follows provider metadata; the default browser catalog includes Aside, Opera, and Opera Neon with SweetCookieKit 0.5.5.
   - Domain filters: `cursor.com`, `cursor.sh`.
   - Cookie names required (any one counts):
     - `WorkosCursorSessionToken`
     - `__Secure-next-auth.session-token`
     - `next-auth.session-token`

3) **Stored session cookies** (fallback)
   - Legacy sessions captured by older CodexBar releases remain readable.
   - Stored at: `~/Library/Application Support/CodexBar/cursor-session.json`.

4) **Cursor local auth** (first automatic source on macOS; last fallback on Linux)
   - Reads Cursor.app's VS Code-style global state DB for the local app bearer token.
   - Files consulted by read-only SQLite:
     - macOS: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
     - Linux: absolute `$XDG_CONFIG_HOME/Cursor/User/globalStorage/state.vscdb`; otherwise absolute `$HOME/.config/Cursor/User/globalStorage/state.vscdb`, then the account home's `.config` directory.
     - Active WAL sidecars, when present: `state.vscdb-wal` and `state.vscdb-shm`.
   - Linux also reads the `cursor-agent login` file at `$XDG_CONFIG_HOME/cursor/auth.json`, or `$HOME/.config/cursor/auth.json` when XDG is unset or relative. If Cursor.app auth is absent, expired, unreadable, or rejected, QuotaKit tries the cursor-agent session.
   - A token is usable only when its JWT expiry is more than 60 seconds away. QuotaKit never refreshes it.
   - Linux reads both local sources without refreshing, rewriting, or persisting their tokens.
   - Derives Cursor's first-party web-session cookie, then uses the same usage and account endpoints as browser sessions.
   - Account identity comes from that authenticated session; cached app profile fields are not mixed across accounts.

Manual option:
- Preferences → Providers → Cursor → Cookie source → Manual.
- Paste the `Cookie:` header from a cursor.com request.

## Add and switch account
- **Add Account** opens `https://authenticator.cursor.sh/` in a supported browser.
- Aside, Opera, and Opera Neon are supported with SweetCookieKit 0.5.5. QuotaKit maps the selected app's bundle identifier to its cookie store; unknown or ambiguous identifiers fail closed.
- **Switch Account** opens the same authenticator and waits for a different stable account ID when available, falling back to normalized email when IDs are unavailable.
- When the system's HTTPS handler is a supported browser, QuotaKit opens the route there automatically. When the handler is an intermediary app, QuotaKit asks the user to choose a concrete supported browser before opening the route.
- QuotaKit pins the original HTTPS route to that concrete browser and polls cookies only from the same application. Interactive login never falls back to another browser, a stored session, or Cursor.app; cancelling browser selection or the absence of a supported browser stops before login opens.
- An installed non-Safari browser remains eligible before its first profile or cookie database exists, and QuotaKit detects the store created during login. Browsers with access-blocked profile data remain unavailable, while Safari still requires an existing readable cookie source.
- QuotaKit preserves its cached and legacy stored Cursor sessions while login is in progress. An accepted browser session must be durably cached before the legacy session is cleared, so cancellation or failure leaves the previous session intact. Add completes only after the authenticated response includes a Cursor account identity. Switch compares stable account IDs when both sides provide them and otherwise compares normalized email.
- QuotaKit checks all available profiles in the selected browser. Add accepts a sole unambiguous account automatically, while Switch always asks for confirmation before replacing the current account, even when only one eligible alternative is found. Multiple eligible accounts always require an explicit choice, and QuotaKit caches only the chosen session.
- A successful add or switch selects the Automatic cookie source. Saved manual headers and token accounts remain
  stored but passive: they do not override browser fetching, cached usage, quota warnings, or utilization/reset
  ownership. Explicitly selecting a saved token account switches Cursor back to Manual and reactivates it.

## API endpoints
- `GET https://cursor.com/api/usage-summary`
  - Plan usage (included), on-demand usage, billing cycle window.
- `GET https://cursor.com/api/auth/me`
  - Stable user ID, email, and name.
- `GET https://cursor.com/api/usage?user=ID`
  - Legacy request-based plan usage (request counts + limits).
- `POST https://cursor.com/api/dashboard/get-sand-usage-status`
  - Grok Bot weekly included usage (`usagePercent`, `nextResetTimestampUtc`). Same session cookie;
    requires `Origin: https://cursor.com`. Best-effort: a failure leaves Cursor's monthly bars intact.

## Cookie file paths
- Safari: `~/Library/Cookies/Cookies.binarycookies`
- Chrome/Chromium forks: `~/Library/Application Support/Google/Chrome/*/Cookies`
- Firefox: `~/Library/Application Support/Firefox/Profiles/*/cookies.sqlite`

## Linux CLI
- `quotakit usage --provider cursor` reads the signed-in Cursor.app token from the Linux global state DB or a `cursor-agent login` token from its auth file, then uses the same `cursor.com` usage endpoints as macOS.
- Long-running CLI requests disable automatic cookie storage, so cookies set by a previous response cannot replace the selected account on a later refresh.
- Automatic browser cookie import and the external-browser Add/Switch flow remain macOS app features.
- Manual cookie headers from `~/.config/quotakit/config.json`, `~/.quotakit/config.json`, or legacy `~/.codexbar/config.json` work on Linux.

## Local storage footprint
When **Settings -> Advanced -> Track provider local storage** is enabled on macOS, QuotaKit measures:
- `~/Library/Application Support/Cursor`
- `~/Library/Application Support/Caches/cursor-updater`
- `~/.cursor`
- `~/Library/Caches/Cursor`
- `~/Library/Caches/com.todesktop.230313mzl4w4u92`
- `~/Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt`
- `~/Library/Caches/cursor-compile-cache`
- `~/Library/HTTPStorages/com.todesktop.230313mzl4w4u92`

The storage detail lists measured paths and their sizes. QuotaKit does not delete Cursor data.

## Token cost (dashboard API)
The cost summary's Cursor section is opt-in: it only fetches when **Show cost summary** is enabled and the Cursor provider is on.
Unlike Claude and Codex cost (scanned from local session logs on this machine), Cursor cost is remote, account-wide data from the cursor.com dashboard, so it covers usage from every machine on the account.

Auth reuses the exact status-probe session resolution and cookie-source policy:
- **Auto**: Cursor.app token → cached cookie → browser cookie import → stored session in the macOS cost dashboard.
- **Manual**: a non-empty pasted cookie header is required and forwarded as-is, so cost and status share the same session; an empty header fails closed instead of falling back to another account.
- **Off**: the fetch is skipped in the app; `quotakit cost --provider cursor` fails explicitly and `/cost` returns a provider error row.

Fetch behavior:
- An unchanged auto-source credential that cannot be confirmed against the fetched result does not trigger an immediate retry loop. Accepted usage is retained; changed credentials or cost settings can refresh normally.
- `POST https://cursor.com/api/dashboard/get-filtered-usage-events` (cookie-authenticated; requires a matching `Origin` for CSRF).
- Pages of 1000 events (up to 200 pages), with exact page-boundary overlap removed before aggregation. Reaching the safety cap or otherwise receiving fewer events than Cursor reports fails the refresh instead of publishing a partial total.
- The window start is snapped to the local day boundary so a 1-day window covers all of today and wider windows keep their full first day.
- Pre-1970 window starts are clamped to the Unix epoch at the request boundary because Cursor rejects negative start timestamps. Unbounded and modern windows retain their existing request dates.

Two totals are reported from the same events:
- **API-rate estimate**: reported `tokenUsage.totalCents`, with an API-list-price fallback only when the field is missing or null. Fallbacks use the existing cached models.dev catalog or bundled rates at the event date, preserve Cursor's disjoint input/cache counters, and do not read native Codex custom pricing or refresh prices over the network. Reported zero remains zero; malformed, negative, nonfinite, or otherwise invalid costs stay unpriced and fail the same-model sum closed. Unknown models remain unpriced. Reported, estimated, and unpriced request counts remain visible even when a rejected cost invalidates a model total.
- **Cursor-metered** (`meteredCostUSD`): what Cursor's plan actually deducts over the window, shown as its own "Cursor-metered:" line.
- Metered-only request events remain visible even when Cursor does not include token details; cookie/config resolution failures stop the fetch instead of falling back to another session.

API-list-price estimates are not estimates of actual Cursor charges: they do not apply plan-specific Cursor Token Rates, regional adjustments, or legacy billing rules. `chargedCents` and Cursor-metered totals remain separate and unchanged. In Overview, history coverage describes the included sources' established history; a selected subscription without spend still makes amounts partial and remains disclosed in the subscription count, without erasing another source's known history days.

Caching: the app holds the snapshot for an in-memory hourly TTL, keyed by the history window plus the cookie source and resolved account (manual-cookie hash or auto-mode account fingerprint), so switching accounts or pasting a new cookie invalidates it immediately.
When Cursor rejects a cost request with HTTP 403, ordinary menu and spend-dashboard cost refreshes pause for at least six hours for that account and configuration, including when refresh cadence is Manual. Explicit refresh, account or cookie changes, and clearing the cost cache retry immediately. Cursor quota refreshes continue normally.

## Snapshot mapping
- Primary/secondary: QuotaKit's explicit Cursor layout stores request, Auto, API, or plan-fallback lanes according to the `cursorRateWindowLayout` discriminator.
- Tertiary: unused for current QuotaKit Cursor snapshots; older synced snapshots remain backward-compatible.
- Extra: Grok Bot usage from `get-sand-usage-status` when the account has a paid allowance or an unexpired trial. The current `includedLimitZero` field takes precedence over the older allowance flag. Exhausted active trials remain visible; missing, malformed, or expired trial dates do not grant an allowance. Grok Bot is not the semantic weekly window, so monthly Auto pace stays on its own bar. A paid Grok Bot allowance with a reset timestamp always uses a seven-day pace, even if Cursor reports a midweek, missing, or inconsistent period start; trial extras and allowances without a reset remain unpaced.
- Menu bar: when Grok Bot usage is known, its percentage can be pinned as a separate token in a custom Cursor layout; unknown or synthetic placeholder windows are not offered as tokens.
- Provider cost: Extra usage USD. A capped individual budget wins; team accounts without a user cap use the shared team on-demand budget.
- Reset: billing cycle end date for monthly bars; paid Grok Bot uses `nextResetTimestampUtc`, even if a trial-expiry field is also present. Trial-only allowances have no recurring reset or duration because trial expiration does not replenish quota.

## Key files
- `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift`
- `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe+UsageSummary.swift` (summary projection)
- `Sources/CodexBarCore/Providers/Cursor/CursorTeamSpend.swift` (verified member budget)
- `Sources/CodexBarCore/Providers/Cursor/CursorSandUsage.swift` (Grok Bot weekly included usage)
- `Sources/CodexBar/CursorLoginRunner.swift` (login flow)
- `Sources/CodexBar/Providers/Cursor/CursorLoginFlow.swift` (menu integration)
- `Sources/CodexBar/CursorLoginBrowserRouter.swift` (browser routing and selection)

### Enterprise and Business member budgets

For team plans with a fresh nonempty email from `/api/auth/me`, the usage probe also checks `/api/dashboard/teams` and
`/api/dashboard/get-team-spend`. It prefers `portal-selected-team-id` over `team_id`,
verifies the selection against the authenticated account's teams, and uses a sole
team when no selection cookie is present (including Cursor.app authentication).
Multiple teams without a selection remain on the usage-summary fallback.

The authenticated member's `overallSpendCents` and `effectivePerUserLimitDollars`
(or `monthlyLimitDollars` when the effective limit is absent) drive the primary
percentage and plan dollars. Missing spend or non-positive limits are not treated
as a zero-usage budget. Other members' data is not included in debug output.
The optional lookup shares a ten-second deadline and the configured request timeout, with at most twenty pages of
fifty members. It requires consistent page-count metadata, full intermediate pages, and the complete page set before accepting one
matching member. Missing completion metadata, duplicate matches, or unavailable, invalid, or incomplete responses
preserve usage-summary behavior. Billing dates and extra/on-demand charges remain sourced from usage-summary;
team response dates and other members' details are not retained. Caller cancellation still stops the fetch.
