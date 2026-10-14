---
summary: "Parallel prepaid balance and pending debits from the signed-in platform.parallel.ai browser session."
provider_id: parallel
provider_name: Parallel
provider_source: Consent-gated browser cookies or a manually supplied Cookie header for platform.parallel.ai.
plugin_scope: Fixed-origin session-cookie POST to the dashboard's internal balance endpoint; no API key, quota, usage history, or reset.
read_when:
  - Configuring Parallel
  - Debugging Parallel balance fetching
---

# Parallel

Enable **Parallel** in Settings → Providers and sign in to
[platform.parallel.ai](https://platform.parallel.ai/login) in a supported browser. Automatic imports use the shared
browser order and require the existing browser-cookie consent. To avoid browser import, choose **Manual** and paste a
`Cookie` header from a signed-in `platform.parallel.ai` request. **Off** disables Parallel cookie access.

## What QuotaKit reads

The bundled plugin calls the same billing refresh endpoint used by the dashboard:

```http
POST https://platform.parallel.ai/api/rpc/billing/payments/refresh-balance
Content-Type: application/json
Origin: https://platform.parallel.ai

{}
```

For a successful response, QuotaKit shows `data.balance` as the **Balance** in dollars. It shows
`data.pendingDebitBalanceCents` as **Pending debit** only when the field is a finite nonzero number. Both amounts are
reported in cents. The balance also appears in supported menu-bar balance layouts. The provider returns display-only
details and does not create quota windows or quota alerts.

This dashboard endpoint is internal and undocumented, so Parallel can change its response at any time. The plugin
checks the status and response shape and fails closed: an invalid response never becomes a zero balance. Signed-out
responses ask you to refresh the browser session; rate limits honor `Retry-After` up to ten seconds; server errors
are reported as temporary provider failures.

```sh
quotakit usage --provider parallel --source web --json
```

The monochrome provider icon is bundled with QuotaKit. Tests exercise synthetic responses on both supported plugin
engines; no signed-in account was accessed.
