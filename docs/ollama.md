---
summary: "Ollama provider notes: API key credit balances, settings scrape, and cookie auth."
read_when:
  - Adding or modifying the Ollama provider
  - Debugging Ollama cookie import or settings parsing
  - Adjusting Ollama menu labels or usage mapping
---

# Ollama Provider

The Ollama provider reads included usage and purchased credits through an API key or usage-related data from the
authenticated settings page. Current Usage settings can expose a **credit balance**, **monthly credits used**, and a
**refill target**, but not a quota percentage; QuotaKit shows those as details instead of inventing a quota bar.
Older settings pages that report monthly included usage, session/hourly, or weekly meters remain supported.

## Features

- **Plan badge**: Reads the plan tier (Free/Pro/Max) from the Cloud Usage header.
- **Included usage**: Parses the monthly credits meter labeled `Monthly usage` on paid plans or `Free usage` on free plans.
- **Legacy session + weekly usage**: Parses older session, hourly, and weekly meters when present.
- **Reset timestamps**: Uses the `data-time` attribute on the “Resets in …” elements.
- **API key auth**: Reads `https://ollama.com/api/balance` with `OLLAMA_API_KEY` or a configured key. Included usage
  supplies the primary **Monthly** bar; purchased credits appear as **Credit balance** in the existing **Credits**
  details section.
- **Browser cookie auth**: Reads the settings page without an API key, including older session/hourly and weekly meters.

## Setup

1. Open **Settings → Providers**.
2. Enable **Ollama**.
3. For API-key mode, select **API key** as the usage source and paste an API key from
   `https://ollama.com/settings/keys` or set `OLLAMA_API_KEY`.
4. For browser-cookie mode, leave **Cookie source** on **Auto**, or paste a manual header below.

Ollama API keys currently do not expire, but they can be revoked from the key settings page.

### Manual cookie import (optional)

1. Open `https://ollama.com/settings` in your browser.
2. Copy a `Cookie:` header from the Network tab.
3. Paste it into **Ollama → Cookie source → Manual**.

## How it works

- API-key mode uses the bundled `ollama-api.ts` plugin for one bearer-authenticated GET to
  `https://ollama.com/api/balance`; refresh no longer probes search or fetches the public model catalog.
- `included.allowance_usd - included.balance_usd` supplies **Monthly credits used** and the primary utilization
  percentage. `included.period.until` supplies its reset. The existing monthly-window sentinel preserves the
  cookie path's calendar-based pace. The shared window model does not store `period.from` as a separate start date.
- `purchased.balance_usd` supplies **Credit balance** and is never added to the included allowance. Numeric and
  decimal-string amounts are supported; absent purchased credits stay absent. Purchased-only accounts show balance
  details without a quota bar, and a zero allowance does not create a percentage.
- HTTP 401 and 403 invalidate the API key. Malformed balances fail parsing without exposing the response body;
  missing reset timestamps remain unavailable.
- Cookie mode fetches `https://ollama.com/settings` using browser cookies.
- Cookie discovery recognizes the current WorkOS AuthKit `wos-session` cookie alongside legacy Ollama and NextAuth
  session names.
- Redirects from settings to `/signin` or the WorkOS AuthKit authorization page are treated as expired sessions, so
  QuotaKit can try the next cookie candidate and show sign-in guidance instead of a parser error.
- Parses:
  - Plan badge under **Included usage** or **Cloud Usage**.
  - The monthly included-credit meter for both Free and paid plans.
  - Legacy **Session usage**, **Hourly usage**, and **Weekly usage** percentages.
  - `data-time` ISO timestamps for reset times.
- API balance's purchased credits are reported separately from included usage. No percentage is inferred when Ollama
  reports only a credit balance.

## Troubleshooting

### “No Ollama session cookie found”

Sign in at `https://ollama.com/signin` in Chrome, then refresh QuotaKit.
If your active session is only in Safari (or another browser), use **Cookie source → Manual** and paste a cookie header.

### “Ollama session cookie expired”

Sign out and back in at `https://ollama.com/signin`, then refresh.

### “Could not parse Ollama usage”

The settings page HTML may have changed. Capture the latest page HTML and update `OllamaUsageParser`.

### Manual source without a cookie header

An empty Manual cookie source has a separate error with instructions to paste a Cookie header from the settings page or choose Auto. The settings picker shows **No cookie header pasted.** and offers **Use automatic cookies** when browser usage is selected, no saved cookie account supplies a value, and Keychain access is enabled. The action changes the cookie source explicitly; it is hidden in API mode or when Keychain access is disabled.
