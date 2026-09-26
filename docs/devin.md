---
summary: "Devin provider auth, quota endpoint, and setup."
read_when:
  - Adding or modifying the Devin provider
  - Debugging Devin localStorage import or quota parsing
  - Explaining Devin setup
---

# Devin Provider

The Devin provider tracks included daily and weekly usage quotas from
[app.devin.ai](https://app.devin.ai).

## Setup

1. Sign in to Devin in Google Chrome.
2. Open the organization Usage & Limits page once.
3. Enable **Devin** in **Settings → Providers**.

Automatic mode reads only the Devin session and organization metadata from Chrome localStorage. It does not scan other
browsers. QuotaKit sends the session token only to `https://app.devin.ai`.

## Manual Auth

Set **Auth source** to **Manual**, then paste either the bare token or the full `Authorization: Bearer ...` header value
from an app.devin.ai API request. The organization field accepts a slug, an internal `org-...` or `org_...` ID, or the
full organization URL. Manual mode does not import a browser session.

Some Auth1 sessions need the internal organization ID even when the same token works in the browser. If Devin returns
`No organizations found for auth1 user`, CodexBar reports organization guidance rather than treating the token as expired:

1. Open the organization's **Usage & Limits** page in the browser where you are signed in.
2. In Developer Tools → Network, inspect a successful `/billing/quota/usage` request.
3. Copy its `x-cog-org-id` request-header value into CodexBar's **Organization** field, then refresh.

The internal-ID path is already supported; manual mode does not discover IDs from public slugs. Other 401/403 responses
still report invalid or expired credentials. For automatic auth with missing organization metadata, open the
organization's Usage page in Chrome and refresh.

Environment overrides:

- `DEVIN_BEARER_TOKEN` or `DEVIN_AUTHORIZATION`
- `DEVIN_ORGANIZATION` or `DEVIN_ORG`

## Data Source

QuotaKit requests:

```text
GET https://app.devin.ai/api/<internal-org-id>/billing/quota/usage
```

The response supplies daily and weekly usage percentages plus reset timestamps. QuotaKit omits the daily quota when Devin sets `hide_daily_quota` to `true`, while retaining weekly usage and extra balance.
If Devin changes or expires the browser
session, sign in again and refresh QuotaKit.
