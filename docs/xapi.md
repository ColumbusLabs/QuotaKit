---
summary: "X API prepaid credit balances from the X developer console."
provider_id: xapi
provider_name: X API
provider_source: Chrome or manual console.x.com session cookies for purchased and free credits.
plugin_scope: Same-session account discovery and prepaid USD balance through QuotaKit's host-owned cookie runtime.
read_when:
  - Setting up X API balance tracking
  - Diagnosing X developer console authentication
---

# X API

X API reports the prepaid wallet used for API calls. It is separate from xAI inference billing and Grok subscription
quotas. It is disabled by default; enable **X API** under Settings → Providers.

Sign in to the [X developer console](https://console.x.com) in Chrome and select Automatic cookies, or use Manual mode
with a Cookie header from the same signed-in session. The header must contain both `auth_token` and `ct0`. The X API
bearer token is not a replacement for a console session. Manual mode is available on Linux, where browser-cookie
import is unavailable.

QuotaKit makes two read-only console requests: `/api/me` discovers the signed-in account, then
`/api/accounts/{account.id}/credits` retrieves its purchased and free-credit balances. The console reports both values
in USD. QuotaKit adds them for the Balance display and keeps separate detail rows for purchased and free credits. A
missing free-credit value counts as zero; malformed balances remain an error. Negative balances retain their sign.

The result has no quota percentage, reset time, token count, or inferred spend. It is exported with provider details and
a prepaid-credit status to the iPhone through the existing QuotaKit sync model. X API has no rate window, so it is not
offered for a quota burn-down widget.

Imported cookie values remain host-owned. The plugin can only request `console.x.com`; QuotaKit selects cookies for the
request URL and echoes the session's `ct0` value as `X-CSRF-Token` on that origin. Automatic imports are limited to
Chrome and are not persisted by this provider. Manual mode stays pinned to the supplied header, and Off mode makes no
requests. HTTP 429 is surfaced as a rate-limit error without an immediate retry.
