---
summary: "OpenRouter provider: account balance, API-key spending caps, PAYG spend, and optional Activity history."
read_when:
  - Debugging OpenRouter balance, key-limit, or Activity parsing
  - Updating OpenRouter spend presentation or settings
  - Explaining OpenRouter setup and environment variables
---

# OpenRouter Provider

[OpenRouter](https://openrouter.ai) is a unified API that provides access to models from multiple providers through one endpoint.

## Authentication

Get an API key from [OpenRouter Settings](https://openrouter.ai/settings/keys), then configure it in QuotaKit Settings → Providers → OpenRouter or through the environment:

```bash
export OPENROUTER_API_KEY="sk-or-v1-..."
```

The optional `OPENROUTER_MANAGEMENT_API_KEY` is a separate credential used only for the account Activity API. It is sent only to `openrouter.ai`; it is never forwarded to a configured API proxy. A management key configured as `OPENROUTER_API_KEY` can also access Activity when the official Current Key response identifies it as a management key. A separately configured management key takes precedence for Activity; the selected API key continues to provide account credits and current-key usage.

CLI configuration:

```bash
printf '%s' "$OPENROUTER_API_KEY" | quotakit config set-api-key --provider openrouter --stdin
```

## Data sources and display

QuotaKit reads three API surfaces:

- `/api/v1/credits` supplies account-wide credits purchased, used, and remaining. Remaining balance is `max(0, total_credits - total_usage)`.
- `/api/v1/key` supplies the standard API key's spending cap and daily, weekly, monthly, and cumulative usage.
- `/api/v1/activity` is optional and uses the separate management key when configured, otherwise the primary key only when the official Current Key response identifies it as a management key. QuotaKit summarizes the last 30 completed UTC days and uses the same history for spend reporting.

An **API key limit** is a spending cap, not account balance. It is shown as a quota meter only when the key reports a positive limit; its detail row is explicitly disclosed as a cap. A missing or zero limit means no spending cap is configured. This never substitutes the cap for account balance.

When there is no configured key cap, the inline PAYG summary uses the most specific available spend counter in this order: monthly usage for the current API key, cumulative usage for that key, then cumulative account usage. The remaining account balance stays a separate figure. When a counter is unavailable, its detail stays visible; inline summaries only replace the matching detail row to avoid showing the same amount twice. Disabling the inline cost summary restores the detail rows.

Activity history includes aggregate token, request, and distinct model counts. Reasoning-token counts are kept separate from completion tokens, while total tokens remain prompt plus completion. Invalid, negative, non-finite, unsafe-integer, or overflowing values do not publish partial history. Deprecated `rate_limit` metadata is ignored.

The dashboard action opens [OpenRouter Activity](https://openrouter.ai/activity). If optional credits or Activity data cannot be fetched, available key usage is preserved and the affected detail shows an unavailable diagnostic. If all usable data sources fail, the provider fetch reports an error.

## CLI usage

```bash
quotakit --provider openrouter
quotakit -p or  # alias
```

## Environment variables

| Variable | Description |
|----------|-------------|
| `OPENROUTER_API_KEY` | API key used for credits and current-key usage; an official management key can also access Activity (required) |
| `OPENROUTER_MANAGEMENT_API_KEY` | Optional management key used only for Activity; takes precedence over a management key in `OPENROUTER_API_KEY` |
| `OPENROUTER_API_URL` | HTTPS API base URL override (optional; defaults to `https://openrouter.ai/api/v1`) |
| `OPENROUTER_HTTP_REFERER` | Optional `HTTP-Referer` sent to the configured API base |
| `OPENROUTER_X_TITLE` | Optional client title sent to the configured API base (defaults to `QuotaKit`) |

## Notes

- OpenRouter may cache credit values, so account balance can lag recent activity.
- The standard key's usage counters and the account's remaining credit balance are separate quantities.
- Management-key settings remain distinct from the API key and are never used as a substitute for current-key quota data. A primary key is promoted to Activity access only when the configured API base is exactly the official `https://openrouter.ai/api/v1` endpoint.
