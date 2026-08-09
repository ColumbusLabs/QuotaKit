---
summary: "Provider status checks, sources, and indicator mapping."
read_when:
  - Changing status sources or status UI
  - Debugging status polling or incident parsing
---

# Status checks

## Sources

- Codex: OpenAI Statuspage.io feed.
- Claude: Anthropic Statuspage.io feed.
- Cursor: Cursor Statuspage.io feed.
- Grok: browser-only link to `https://status.x.ai`; QuotaKit does not poll it for an in-app incident indicator.

## Behavior
- Toggle: Settings → General → “Check provider status”.
- `UsageStore` polls the three configured feeds and stores `ProviderStatus` for indicator/description.
- Menu shows incident summary + freshness; icon overlays indicator.

## Links
- Codex, Claude, and Cursor set `statusPageURL`; status polling appends `api/v2/status.json`, and the menu action opens
  the provider's status site.
- Grok sets only `statusLinkURL`, so its menu action opens xAI Status without polling.

See also: `docs/providers.md`.
