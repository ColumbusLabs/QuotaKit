---
summary: "Moonshot / Kimi API provider data sources: API key + balance endpoint."
read_when:
  - Adding or tweaking Moonshot balance parsing
  - Updating Moonshot / Kimi API key handling
  - Documenting Moonshot / Kimi API provider behavior
---

# Moonshot / Kimi API provider

Moonshot / Kimi API is API-only. Balance is reported by `GET /v1/users/me/balance`,
so QuotaKit only needs a valid API key to show the current account balance.

## Rationale

Kimi API docs use the Moonshot API surface for current Kimi models: examples read
`MOONSHOT_API_KEY` and call `https://api.moonshot.ai/v1`, including the Kimi K2.6
quickstart. This provider is therefore named after the account and billing surface,
not a specific Kimi model version.

QuotaKit uses the official Moonshot account and billing surface rather than unofficial
third-party Kimi relays.

## Data sources

1. **API key** stored in `~/.quotakit/config.json` or supplied via `MOONSHOT_API_KEY` / `MOONSHOT_KEY`.
   QuotaKit stores the key in config after you paste it in Settings → Providers → Moonshot / Kimi API.
2. **Region**
   - International: `https://api.moonshot.ai/v1/users/me/balance`
   - China mainland: `https://api.moonshot.cn/v1/users/me/balance`
   - Configure with Settings → Providers → Moonshot → API region or `MOONSHOT_REGION`.
3. **Balance endpoint**
   - Request headers: `Authorization: Bearer <api key>`, `Accept: application/json`
   - Response contains `available_balance`, `voucher_balance`, and `cash_balance`.

## Usage details

- The menu card shows the available balance.
- If `cash_balance` is negative, the card also surfaces the deficit.
- There is no session or weekly window — Moonshot / Kimi API does not expose per-window quota via API.
- Settings config takes precedence over environment variables when both are present.

## Key files

- `Sources/QuotaKitCore/Providers/Moonshot/MoonshotProviderDescriptor.swift` (descriptor + fetch strategy)
- `Sources/QuotaKitCore/Providers/Moonshot/MoonshotUsageFetcher.swift` (HTTP client + JSON parser)
- `Sources/QuotaKitCore/Providers/Moonshot/MoonshotSettingsReader.swift` (env var resolution)
- `Sources/QuotaKit/Providers/Moonshot/MoonshotProviderImplementation.swift` (settings field + activation logic)
- `Sources/QuotaKit/Providers/Moonshot/MoonshotSettingsStore.swift` (SettingsStore extension)
