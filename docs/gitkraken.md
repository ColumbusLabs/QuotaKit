---
summary: "Configure GitKraken AI usage in QuotaKit."
read_when:
  - Setting up the GitKraken AI provider
  - Troubleshooting GitKraken API usage
---

# GitKraken AI

QuotaKit reads GitKraken AI's weekly usage endpoint with an account access token. The provider is off by default.

## Setup

1. In QuotaKit, open Settings → Providers → GitKraken AI.
2. Add a GitKraken access token. Paste the token value only, without a `Bearer` prefix.
3. Optionally enter an organization ID to request the organization's shared pool.

You can also set `GITKRAKEN_API_TOKEN` and, optionally, `GITKRAKEN_ORG_ID` in the environment that launches QuotaKit.
Configured values are stored in `~/.quotakit/config.json`.

## Data shown

The personal weekly window and reset time come from GitKraken's usage response. When an organization pool is returned,
QuotaKit shows it as a secondary weekly window and lists the user's shared usage separately from the remainder of the
pool. The shared amount is already included in the organization total, so QuotaKit does not add it again.

GitKraken does not provide token cost history through this endpoint. The provider makes a GET request to
`https://api.gitkraken.dev/v1/ai-tasks/usage`; the optional organization ID is sent in the `gk-org-id` header.
