---
summary: "Replicate monthly billing spend and optional prepaid credit through a browser session."
read_when:
  - Configuring or troubleshooting Replicate usage
---

# Replicate

Enable Replicate in **Settings → Providers**. QuotaKit reports the selected account's current-month spend and, when available, prepaid credit balance. Replicate does not expose a quota denominator here, so QuotaKit does not infer a percentage, limit, or remaining quota. Spend still syncs by the stable `replicate` provider ID, but Replicate is intentionally excluded from CloudKit quota-transition subscriptions because it cannot emit quota thresholds.

Automatic cookie mode imports existing Chrome cookies for exactly `replicate.com`. QuotaKit caches a successful session in Keychain and retries browser candidates only after an authentication failure. A manually pinned session does not fall back to another account. Manual mode accepts a Cookie header captured from a request to `https://replicate.com/account/billing`; it bypasses browser import and the automatic cache. The header must contain a nonempty `sessionid` cookie. A Replicate API token is not interchangeable with this website session.

The bundled provider reads the billing page to identify the selected user or organization, then requests that account's invoice summary and optional unused-credit balance. Required spend must be present and valid; malformed billing data is an error rather than a fabricated zero. Optional credit failures omit only the balance. QuotaKit does not mutate Replicate account data or scan local cost history for this provider.
