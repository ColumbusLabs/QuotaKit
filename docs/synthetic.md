---
summary: "Synthetic provider data sources: API key quota endpoint and usage lanes."
read_when:
  - Debugging Synthetic API key usage
  - Updating Synthetic quota parsing
  - Explaining Synthetic setup and environment variables
---

# Synthetic provider

Synthetic is API-key only. QuotaKit reads the quota endpoint and maps the
known Synthetic quota lanes into the shared provider card.

## Authentication

Create an API key using [Synthetic's API guide](https://dev.synthetic.new/docs/api/getting-started), then add it in
Settings -> Providers -> Synthetic, or set:

```bash
export SYNTHETIC_API_KEY="..."
```

You can also store the key through the CLI:

```bash
printf '%s' "$SYNTHETIC_API_KEY" | quotakit config set-api-key --provider synthetic --stdin
```

## Data source

QuotaKit sends a read-only request to [Synthetic's quota API](https://dev.synthetic.new/docs/synthetic/quotas):

```http
GET https://api.synthetic.new/v2/quotas
Authorization: Bearer <api key>
Accept: application/json
```

The parser first looks for Synthetic's known quota slots, either at the root
of the response or under `data`:

- `planWeeklyLimit` (or the older `weeklyTokenLimit`) -> Weekly quota
- `search.hourly` -> Search hourly

The current weekly plan reports percentages in percentage points, including values below 1%. Its
regeneration timestamp and percentage do not require credit amounts. Known quota lanes suppress the
retired subscription counter; subscription-only responses remain supported. Older plans may also
return a rolling five-hour lane.

If those keys are absent, QuotaKit falls back to generic quota payloads such as
`quotas`, `quota`, `limits`, `usage`, `entries`, or `subscription`.

## Display

- The menu card shows weekly credit usage and search-hourly usage for current plans. The compact menu bar metric
  can use the weekly lane; automatic selection may choose search when it is more constrained.
  Older responses can also show a five-hour lane.
- Usage is normalized from percent fields when present, or computed from used/remaining/limit values.
- Reset timestamps are shown when Synthetic returns one. When no timestamp is available, QuotaKit uses the returned
  or inferred window duration when present.
- Plan name, when returned, is displayed as provider identity context.
- Synthetic does not currently provide QuotaKit cost history.
- External status page: [status.synthetic.new](https://status.synthetic.new) (not linked or auto-polled by QuotaKit).

## CLI usage

```bash
quotakit usage --provider synthetic
quotakit usage --provider synthetic.new
```

## Key files

- `Sources/CodexBarCore/Providers/Synthetic/SyntheticProviderDescriptor.swift` (descriptor and fetch strategy)
- `Sources/CodexBarCore/Providers/Synthetic/SyntheticUsageStats.swift` (HTTP client and parser)
- `Sources/CodexBarCore/Providers/Synthetic/SyntheticSettingsReader.swift` (environment variable parsing)
- `Sources/CodexBar/Providers/Shared/PluginAPIKeyProviderImplementation.swift` (spec-built settings and availability)
