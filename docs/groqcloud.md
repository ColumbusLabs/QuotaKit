---
summary: "Groq Enterprise Prometheus source; see groq.md for the default console source."
read_when:
  - Configuring GroqCloud usage tracking
  - Debugging GroqCloud request or token-rate display
---

# Groq Enterprise metrics

This page covers the Enterprise Prometheus source of the [Groq provider](groq.md), separate from xAI Grok. The default
console session source and its spend/usage history are documented in the Groq guide. `groqcloud` and `groq` select the
same provider; use `--source api` to select Prometheus explicitly.

## Setup

Store the key in the shared app/CLI config:

```bash
printf '%s' "$GROQ_API_KEY" | quotakit config set-api-key --provider groq --stdin
```

Or set `GROQ_API_KEY` in the process environment. `GROQ_API_URL` can override the default `https://api.groq.com/v1`
base URL for private gateways.

## Menu display

- Primary: requests per minute.
- Secondary: tokens per minute.
- Tertiary: prompt cache hits per minute when the metric exists.
- Dashboard link: Groq console usage dashboard.

If the key lacks Prometheus metrics access, QuotaKit shows the API error instead of guessing from unrelated endpoints.
