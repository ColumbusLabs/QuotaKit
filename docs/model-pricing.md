---
summary: "models.dev pricing metadata pipeline, custom-pricing overlay, cache, lookup rules, and token-cost units."
read_when:
  - Updating models.dev pricing metadata support
  - Debugging model-pricing cache refresh or lookup behavior
  - Routing provider cost calculations through shared pricing metadata
  - Adding or documenting custom-pricing.json overlays
---

# Model pricing metadata

QuotaKit uses models.dev as an additive pricing source alongside bundled fallback rates.

## Source and cache

- Source API: `https://models.dev/api.json`
- No API key is required.
- Local cache: `~/Library/Caches/CodexBar/model-pricing/models-dev-v1.json`
- TTL: 24 hours

The pipeline lets future scanner code read the last valid cache synchronously with `ModelsDevPricingPipeline.lookup` and refresh stale metadata separately with `ModelsDevPricingPipeline.refreshIfNeeded`. If a refresh fails, the last valid cache remains usable.

Changed catalogs are atomically replaced. When a refreshed catalog has identical rates and identities,
`models-dev-v1.json.refresh` records successful fetch freshness without rewriting the catalog or invalidating
compatible Claude cost reports. Its metadata is bound to the catalog's full file identity. Missing, corrupt,
or mismatched sidecars fall back to the embedded fetch time. Existing catalogs stay readable by older versions.

Fallback pricing merges use a provider-local stable-identity index. Model-ID normalization is memoized only
within the current merge or lookup; provider boundaries, alias precedence and dated rates remain unchanged.

## Lookup rules

Pricing is scoped by provider id and model id. This prevents two providers with the same model id or display name from sharing pricing accidentally.

Local cost scanners preserve that scope when selecting a catalog:

- Bare Codex/OpenAI model IDs use provider id `openai`; approved provider-qualified routes stay on their route, and unknown prefixes remain unpriced.
- Recognizable bare Claude-session model families use their first-party vendor catalog, including Anthropic, OpenAI, Google, Moonshot/Kimi, MiniMax, and DeepSeek.
- Claude's documented Kimi Code `k3[1m]` alias may use the `kimi-for-coding/k3` rate only after exact Kimi Code lookups fail. It never borrows another provider's rate.
- Other bare Claude-session IDs are priced only when exactly one selected first-party catalog matches. Ambiguous cross-vendor matches remain unpriced.
- Provider-qualified Claude-session IDs stay on an approved explicit route and never fall through to another vendor.
- Antigravity's exact recorded `gpt-oss-120b-medium` name falls back to `google-vertex` / `openai/gpt-oss-120b-maas` after existing model lookups. [Google's Vertex list price](https://cloud.google.com/vertex-ai/generative-ai/pricing) is $0.09 input and $0.36 output per million tokens (verified October 5, 2026); QuotaKit reads the rates from [models.dev's catalog entry](https://github.com/anomalyco/models.dev/blob/8ce27fe1f811a0f63100826e9a7965af0afd96d9/providers/google-vertex/models/openai/gpt-oss-120b-maas.toml). Missing cache rates use the input rate, as in the existing Claude resolver. Unknown-price refresh includes this exact entry; other effort suffixes and reseller prices are not inferred. The displayed name stays unchanged, and dollars remain public API estimates rather than Antigravity charges.
- Vertex AI Claude logs: models.dev provider id `google-vertex-anthropic`
- OpenCodex log entries use their recorded provider for pricing. Only legacy `openai` transport rows may take an explicit known route from the model prefix; a router's `openai/...` model namespace does not make the row OpenAI usage. A missing provider retains the legacy OpenAI fallback for unqualified model IDs, while an unknown recorded provider does not borrow OpenAI rates.
- OpenCodex models.dev lookups are exact within the recorded provider. Cache-read and cache-write usage stays unpriced when that provider has no corresponding cache rate, and missing input/output counts stay unknown. A fresh dashboard or CLI load can refresh stale pricing and check unknown exact models; cached snapshots do not start network requests.

## Units

models.dev publishes costs as USD per 1M tokens. QuotaKit converts those to USD per token in the metadata layer:

```text
perToken = modelsDevCost / 1_000_000
```

When models.dev includes `cost.context_over_200k`, QuotaKit converts those rates with the same per-1M-token rule.
The legacy field name does not establish the threshold: a matching `cost.tiers` entry with `tier.type = "context"`
supplies its explicit `tier.size`. Only the tier matching the legacy lane's rates is used; this does not add
arbitrary multi-tier pricing. Older catalogs without that metadata use the bundled OpenAI model threshold,
or 200,000 tokens when no provider-specific contract is known. Other providers never inherit OpenAI thresholds.

OpenAI's [pricing table](https://developers.openai.com/api/docs/pricing) defines short context as **at most 272,000
input tokens**, and long context as **more than 272,000**, including cached input. This applies to GPT-6 Astra,
GPT-6.1 Sol, GPT-6 Sol, GPT-6 Luna, GPT-5.6 Sol/Terra/Luna, GPT-5.4/5.5, and their Pro variants where listed.
The bundled table preserves that boundary for old catalogs, including the GPT-5.6 and Daybreak Blue aliases.
For example, GPT-6.1 Sol with 210,000 input tokens (200,000 cached) and 1,000 output tokens costs **$0.050** at
Standard rates. At 272,001 input tokens the full request uses long-context rates, not just the excess tokens.
Catalog thresholds and bundled rates participate in the native Codex pricing fingerprint, so affected cached
estimates are repriced. Existing native rows and scan checkpoints remain compatible; recorded authoritative costs
and explicit custom-pricing overrides retain their existing precedence.

## Custom pricing overlay

Exact-match list-price overrides live in the platform Application Support directory:

```text
macOS: ~/Library/Application Support/CodexBar/custom-pricing.json
Linux: ${XDG_DATA_HOME:-~/.local/share}/CodexBar/custom-pricing.json
```

The Linux CLI uses `FileManager`’s Application Support directory (XDG data home), not `~/.config`. Putting the file only under XDG config will be ignored.

Values are USD per million tokens. For native Codex session scans, resolution order is **overlay > models.dev > builtin**. Changing the file invalidates the Codex pricing fingerprint so the next native Codex scan reloads rates.

Native Codex/OpenAI-compatible session scans resolve exact overlay rates before models.dev and bundled pricing. OpenCodex snapshots also read this overlay and check the recorded provider/model identity before models.dev; OpenAI bundled and historical rates remain limited to OpenAI usage. Claude's local scanner and Cursor do not read this file. A key such as `anthropic/claude-…` does not change Claude list prices.

Keys are case-insensitive and may be a bare model id (`gpt-5.4`) or `provider/model` (`openai/gpt-5.4`). Only an exact normalized key matches; there is no prefix or family glob. If both forms exist for the same model, the **bare key wins** and the provider-qualified row is ignored. Do not define both unless the bare override is the one you want.

```json
{
  "gpt-5.4": {
    "input": 1.25,
    "output": 10,
    "cacheRead": 0.125,
    "cacheWrite": 1.25
  },
  "openai/gpt-5.4-mini": {
    "input": 0,
    "output": 0
  }
}
```

Field rules:

- `0` is a free rate for that token class.
- A missing field stays unknown. QuotaKit does not fill it from models.dev or bundled tables, so a partial overlay row is unpriced rather than a mix of overlay and catalog rates.
- Negative and non-finite numbers are ignored.
- Alternate spellings `cache_read`, `cache_write`, `cacheCreation`, and `cache_creation` are accepted for cache fields.

Tests never read this file from the developer Application Support directory; they use fixtures or an empty overlay.
