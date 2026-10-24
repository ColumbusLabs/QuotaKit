---
summary: "abliteration.ai API credit balance and usage."
provider_id: abliteration
provider_name: abliteration.ai
provider_source: API key for reported credit totals.
plugin_scope: Read-only credits endpoint.
read_when:
  - Setting up or modifying the abliteration.ai provider
---

# abliteration.ai

Enable **abliteration.ai** in Settings → Providers and enter an API key, or set `ABLITERATION_API_KEY` for the CLI.
The key is stored in QuotaKit's local config when entered in Settings. The plugin makes a read-only request to
`https://api.abliteration.ai/v1/credits` and reads `total_credits` and `total_usage` from the response.

QuotaKit displays the remaining balance, total credits, and usage as USD values. A positive total also provides a
usage meter; the endpoint does not supply a reset schedule, so QuotaKit does not infer one. Malformed or negative
credit totals fail the refresh rather than becoming zero. The provider does not expose quota alerts or burn-down
widgets. iPhone sync includes the billing detail and excludes rate-window reset fields.
