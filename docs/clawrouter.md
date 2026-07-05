---
summary: "ClawRouter setup for monthly budget, spend, and routed-provider usage."
read_when:
  - Configuring ClawRouter usage tracking
  - Debugging ClawRouter budget or provider breakdown display
  - Explaining ClawRouter API key and base URL settings
---

# ClawRouter

QuotaKit reads the policy attached to a ClawRouter API key. The menu card shows its monthly budget, spend, requests,
tokens, and provider breakdown. Provider rows come directly from ClawRouter, so the integration works with any routed
model provider configured there; QuotaKit does not need a separate provider plugin for each route.

## Setup

Create a ClawRouter key with access to the routes you want, then store it in QuotaKit:

```bash
printf '%s' "$CLAWROUTER_API_KEY" | quotakit config set-api-key --provider clawrouter --stdin
```

You can also paste the key in QuotaKit Settings → Providers → ClawRouter. The hosted service is used by default:

```text
https://clawrouter.openclaw.ai
```

For another deployment, set the Base URL in Settings or use `CLAWROUTER_BASE_URL`. The value may point to the service
root or `/v1`; QuotaKit normalizes both to `/v1/usage`. Overrides must be HTTPS URLs or bare hosts normalized to HTTPS.

## Display

- Monthly budget meter and reset date when the policy has a budget.
- This-month spend against the configured limit.
- Request count and total token usage.
- Up to five routed-provider rows, ordered by spend and request count.
- Unmetered policy status and spend when no monthly limit is configured.

ClawRouter usage is policy-wide. If one key can route OpenAI, Anthropic, Google, OpenRouter, or non-model services, the
same QuotaKit card aggregates them and lists the provider identifiers returned by `/v1/usage`.

## Environment variables

| Variable | Description |
| --- | --- |
| `CLAWROUTER_API_KEY` | ClawRouter API key. |
| `CLAWROUTER_BASE_URL` | Optional HTTPS service root or `/v1` URL. |

QuotaKit sends the key only to the validated ClawRouter endpoint. `/v1/usage` returns accounting metadata; QuotaKit
never receives routed prompts or model responses.
