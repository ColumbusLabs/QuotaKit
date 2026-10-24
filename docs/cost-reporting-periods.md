# Cost reporting periods

## Conversation usage details

In a cost-history menu, click a conversation to open its session inspector in Usage & Spend. The
search control opens the same inspector for conversations retained in the current account snapshot.
Usage & Spend groups sessions by source so identical session IDs from different accounts remain
separate. Search matches the visible conversation name or session ID; hidden names are not searched
when **Hide personal information** is enabled. Sessions sort by activity, tokens, or cost, with
unavailable values remaining last.

The inspector shows input, cached input, uncached input, output, reasoning, requests, estimated spend,
and per-model totals. Expand a turn to see its request records and local Codex tool activity when
available. Tools have no separate recorded token or monetary cost. Requests without a known turn are
shown as unattributed usage; requests outside the selected reporting period are not included.
Cached input is a subset of input, and reasoning is a subset of output. Missing counters and prices
remain unavailable rather than being displayed as zero.

Ordinary refreshes retain the existing session summaries without building request-detail arrays.
Selecting one native Codex session reads only that file's existing SQLite rows in a read-only
transaction. The loader enforces limits of 5,000 requests, 8 MiB of request payload, 1 MiB of file
metadata, 5,000 day/model aggregates, and 1 MiB of aggregate model names. If the session exceeds a
limit, or its modification time, parsed byte checkpoint, or store schema no longer matches the
summary, the summary remains available and request details are unavailable; no partial totals are
presented. Detail reads use the session's existing cached pricing metadata and fork-accounting
lineage. Closing the inspector releases its selected request details. No additional history store is
created.

Spend charts use the same reporting calendar for grouped bars, scoped day/hour inspection, day navigation, and source isolation. Recorded zero sources remain selectable; absent coverage is unavailable rather than a fabricated zero. Totals and chart selections preserve the selected reporting dates across daylight-saving boundaries.

The menu's **History window** supports rolling days, **Month to date**, and **Available year**. Usage & Spend uses the same period model and keeps its own range selection. Existing saved day counts retain their rolling windows; the dashboard's former 365-day selection migrates to Available year.

Month to date starts at midnight on the first day of the current month and includes today. It uses the pinned cost-bucketing time zone from Settings, falling back to the current local zone. Calendar arithmetic handles leap years and 23/25-hour daylight-saving days. A bounded, time-zone-keyed Gregorian day memo avoids rebuilding the same day key for every event while retaining those boundaries. Each operation resolves its window again, and cache identities include the selection, dates, and time zone.

Menu cost and token charts retain a slot for every calendar day in the selected window. A missing day is shown as zero only after the history scan covers that window; incomplete scans and recorded unpriced costs remain unknown. OpenAI and Mistral use their fixed UTC billing-day calendars; local history follows the selected bucket time zone.

The menu selection also supplies the default for `quotakit cost`, the HTTP `/cost` endpoint, and widget cost summaries. The widget metric is named **Cost**; its displayed period comes from the app's snapshot. Explicit CLI options override the saved selection:

```sh
quotakit cost --period month-to-date --json
quotakit cost --period all --json
quotakit cost --days 7 --json
```

`--days N` always selects a rolling window, even alongside `--period`. Rolling windows accept 1–365 days and default to 30 on installations without a saved selection. JSON includes `reportingPeriod`, `historyLabel`, and period totals under `totals`; the existing `last30DaysTokens` and `last30DaysCostUSD` compatibility fields retain their documented meaning.

Available year reads at most the last 365 calendar days. QuotaKit retains this bound to protect its 30-day routine background scan and 365-day visible dashboard demand policy. Missing or deleted logs cannot be recovered, provider APIs can impose shorter limits, and incomplete scans remain marked as incomplete. This is not a permanent ledger or a lifetime bill since installation.

Cursor's quota bars keep the billing-cycle dates reported by Cursor. Calendar-month cost is a complementary view of dated usage events; it does not reinterpret a mid-month billing-cycle allowance as a calendar-month quota.

Claude cache updates reconcile transcript rows once per load and reuse that ordered result for cached daily totals and the report. Duplicate winners reference the existing transcript rows until the final ordered result is assembled, reducing temporary memory use for large histories. Winner precedence, report ordering, and cache invalidation remain unchanged; separate reporting windows still retain their own rows.

Within each transcript scan or cache decode, repeated session IDs and model names share string storage without changing their UTF-8 spelling or the saved JSON.

Claude and Vertex reserve the final transcript row count during cache decoding and parsed-row assembly, reducing retained spare capacity without changing cache bytes or report ordering.

Claude and Vertex cache saves reuse encoded transcript fragments when their metadata bytes and row contents are unchanged. The bounded memo retains byte ranges in the previous artifact instead of encoded values; saves stream those ranges and newly encoded files into a replacement artifact. Reuse requires the same device, inode, size, and nanosecond modification time. Each cache URL has independent fragments; removed files are discarded and the memo can be evicted without changing saved JSON or report results. Transcript-cache loads use mapped input that is released after decoding. Key ordering and escaping still come from the JSON encoder.

Archived Codex forks with missing parent logs stay out of billed totals and remain visible as unmetered activity. Their full observed event span is considered when deciding whether a requested history window is complete; restoring a missing parent lets the scanner reconcile the fork baseline.
