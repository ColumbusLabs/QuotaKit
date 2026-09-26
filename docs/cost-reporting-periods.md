# Cost reporting periods

The menu's **History window** supports rolling days, **Month to date**, and **Available year**. Usage & Spend uses the same period model and keeps its own range selection. Existing saved day counts retain their rolling windows; the dashboard's former 365-day selection migrates to Available year.

Month to date starts at midnight on the first day of the current month and includes today. It uses the pinned cost-bucketing time zone from Settings, falling back to the current local zone. Calendar arithmetic handles leap years and 23/25-hour daylight-saving days. Each operation resolves its window again, and cache identities include the selection, dates, and time zone.

The menu selection also supplies the default for `quotakit cost`, the HTTP `/cost` endpoint, and widget cost summaries. The widget metric is named **Cost**; its displayed period comes from the app's snapshot. Explicit CLI options override the saved selection:

```sh
quotakit cost --period month-to-date --json
quotakit cost --period all --json
quotakit cost --days 7 --json
```

`--days N` always selects a rolling window, even alongside `--period`. Rolling windows accept 1–365 days and default to 30 on installations without a saved selection. JSON includes `reportingPeriod`, `historyLabel`, and period totals under `totals`; the existing `last30DaysTokens` and `last30DaysCostUSD` compatibility fields retain their documented meaning.

Available year reads at most the last 365 calendar days. QuotaKit retains this bound to protect its 30-day routine background scan and 365-day visible dashboard demand policy. Missing or deleted logs cannot be recovered, provider APIs can impose shorter limits, and incomplete scans remain marked as incomplete. This is not a permanent ledger or a lifetime bill since installation.

Cursor's quota bars keep the billing-cycle dates reported by Cursor. Calendar-month cost is a complementary view of dated usage events; it does not reinterpret a mid-month billing-cycle allowance as a calendar-month quota.
