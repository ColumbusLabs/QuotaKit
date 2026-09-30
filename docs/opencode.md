---
summary: "OpenCode provider notes: browser cookies, local SQLite usage, and parsing."
read_when:
  - Adding or modifying the OpenCode provider
  - Debugging OpenCode usage parsing or cookie import
---

# OpenCode provider

## Data sources
- Browser cookies from `opencode.ai`. The legacy `auth` cookie serves the older workspace pages and the
  `__Host-console_session` cookie authenticates Console requests. Both pass through the cookie filter, and a
  Console-only session is valid for a migrated workspace.
- OpenCode Go usage API at `GET https://opencode.ai/zen/go/v1/usage`, authenticated by `OPENCODE_API_KEY` or
  `providers[].apiKey`, or a selected API-key token account.
- OpenCode Console JSON, used first for OpenCode Go web reads:
  - `GET https://opencode.ai/console/api/orgs` lists workspaces without a workspace header.
  - `GET https://opencode.ai/console/api/go/status` returns Go subscription meters and requires the workspace ID in
    the `x-org-id` header.
  - `GET https://opencode.ai/console/api/billing/status` reads the workspace's prepaid PAYG Zen balance with the
    same header. `balanceMicroCents` is converted to USD by dividing by 100,000,000; `availableMicroCents` is a
    separate value and is not substituted for the balance.
- OpenCode Go local history from `~/.local/share/opencode/opencode.db` on macOS and Linux.
  Device-local quota estimates retain their values and reset dates, but QuotaKit omits pace
  forecasts until an account-scoped source reports authoritative usage.
- `POST https://opencode.ai/_server` with server function IDs, used for workspaces that have not migrated to Console:
  - `workspaces` (`def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f`)
  - `subscription.get` (`7abeebee372f304e050aaaf92be863f4a86490e382f8c79db68fd94040d691b4`)

## Usage mapping
- Console meter `usedMicroCents` and `limitMicroCents` values become percentages as `100 * used / limit`.
- A missing Console meter reset remains unknown, with no countdown. A missing monthly reset uses the billing-period
  end at `access.endsAt`.
- Primary window: rolling 5-hour usage (`rollingUsage.usagePercent`, `rollingUsage.resetInSec`).
- Secondary window: optional weekly usage (`weeklyUsage.usagePercent`, `weeklyUsage.resetInSec`).
- Resets computed as `now + resetInSec`.
- The menu layout editor offers the Monthly tertiary percentage before a usage snapshot arrives.

## Using OpenCode with Codex or OpenAI

Codex quota and local token/cost history are separate sources. The Codex provider reads session and weekly quota
from the signed-in account's remote endpoint; these percentages do not come from local session logs.

When OpenCode holds a Codex OAuth session, explicitly enabling **External Codex OAuth sources** can reuse its
`openai` OAuth entry for remote quota. Native Codex credentials take precedence, and an explicit `CODEX_HOME`
prevents external fallback. External credentials remain read-only; stale credentials fail closed, and API-key
entries are ignored.

This does not import ordinary OpenCode sessions into Codex token or spend totals. The OpenCode Go SQLite reader
selects only `opencode-go` assistant records. OpenAI API usage is separate from Codex subscription quota.

## Notes
- OpenCode Go accounts accept labeled API keys or Cookie headers. In Auto mode, a selected API-key account uses the
  usage API with that key, isolated from provider-wide and ambient `OPENCODE_API_KEY` values. A selected Cookie
  account clears those API credentials and uses manual web cookies. Explicit API and Web source choices remain
  authoritative; a single configured API key still works without token accounts.
- API-key accounts preserve the saved browser-cookie preference when added, selected, edited, or removed. Cookie
  accounts select Manual, including when an API-key account is changed to a Cookie header. Keys cannot contain
  whitespace, `=`, or `:`; surrounding quotes and whitespace are removed before validation.
- Legacy workspace responses are `text/javascript` with serialized objects; Console responses are JSON.
- OpenCode Go web reads try Console first. They use the legacy workspace page only when legacy auth is available;
  legacy and Console sessions can expire independently. Console HTTP 401 means signed out. Console status and
  permission errors remain API errors if the legacy route cannot supply a valid response. Cancellation and
  certificate failures do not trigger fallback.
- A Console Go response of `null` or `access: null` means there are no subscription windows. Prepaid pay-as-you-go
  accounts can still report a Zen balance, including zero or negative values. Other Console billing modes are not
  mapped. A failed optional balance read does not discard valid Go usage.
- Missing workspace ID or rolling usage fields should raise parse errors; omitted weekly usage stays absent.
- OpenCode web Auto imports Chrome first, then Dia when their cookie stores exist; Keychain preflight stays scoped
  to each candidate browser. Other browsers stay on Manual Cookie import until QuotaKit has an explicit browser
  selector.
- Set `CODEXBAR_OPENCODE_WORKSPACE_ID` to skip workspace lookup and force a specific workspace.
- Workspace override accepts a raw `wrk_…` or `org_…` ID, a full legacy `https://opencode.ai/workspace/...` URL, or
  a Console `https://opencode.ai/console/...` URL.
- Cached cookies: Keychain cache `com.steipete.codexbar.cache` (account `cookie.opencode`, source + timestamp). Browser
  import only runs when the cached cookie fails.
- OpenCode Go unscoped Auto mode tries daily cost history derived from local `opencode-go` assistant costs first,
  overlays authoritative API windows when an API key is configured, then falls back through the API and legacy web
  sources when local history is unavailable. A selected API-key account uses API mode. Auto stays web-first when a
  cookie token account, manual cookie, or workspace override scopes the request, because local history is device-wide.
- The local monthly window is an estimate anchored at the earliest local row and can drift from the real billing
  cycle. The local strategy prefers API-reported rolling/weekly/monthly percentages and reset timestamps. When no API
  key is configured, a cached or manual session cookie can still overlay the legacy web values (plus Zen balance).
  Both paths keep local daily cost history and never trigger a fresh browser import. When no authoritative overlay is
  available, the menu and text CLI label the quota as estimated, and JSON includes `dataConfidence: "estimated"`.
- OpenCode Go cost history chart: `opencode.ai` has no daily-granularity endpoint, so per-day cost/request buckets
  come from local `opencode-go` assistant costs in `opencode.db`, keyed by device-local calendar day. Successful web
  usage remains workspace-scoped and is never blended with device-wide local costs, so it does not show cost history.
  Explicit Web mode never reads the local database either.
- Each day's bucket also carries a per-model cost breakdown, read from each local assistant message's `modelID`
  (the real model behind the constant `opencode-go` Zen proxy `providerID`). This lets the shared Cost history
  chart show a per-model breakdown for OpenCode Go the same way it already does for Claude (see the "Cost usage"
  section in [docs/claude.md](claude.md)). Rows with no `modelID` are grouped under an "unknown" bucket instead of
  being dropped.
- Local history also includes recorded input, output, reasoning, cache-read, cache-write, and total tokens per day
  and model. Step-finish parts take precedence over their parent message so multi-step sessions are not counted
  twice. Explicit totals are used as recorded; older rows without a total sum the five complete token components.
  Missing, malformed, negative, or overflowing counts remain unknown rather than becoming zero. A day containing
  a row without usable tokens has no complete token total. These device-local counts add history detail only:
  they do not change account quota, and costs still come from the recorded `cost` field, never token pricing.
