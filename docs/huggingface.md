---
summary: "Hugging Face Inference Providers billing, ZeroGPU quota, and authentication."
read_when:
  - Configuring or troubleshooting Hugging Face in QuotaKit
  - Changing Hugging Face usage or identity parsing
---

# Hugging Face

QuotaKit reports current-month Inference Providers charges and, when available, the account's separate ZeroGPU GPU-time quota. It does not infer a remaining billing allowance or a reset date from spend-report boundaries.

## Authentication

Add a token in Settings → Providers, create a labeled token account, or authenticate with the `hf` CLI. Token discovery checks the QuotaKit setting/override first, followed by `HF_TOKEN`, `HUGGING_FACE_HUB_TOKEN`, and the token file used by `hf auth login`:

- `HF_TOKEN_PATH`, when set;
- `$HF_HOME/token`, when `HF_HOME` is set;
- `$XDG_CACHE_HOME/huggingface/token`, when `XDG_CACHE_HOME` is set;
- `~/.cache/huggingface/token` otherwise.

Classic read tokens can access billing. Fine-grained tokens need the **Billing read** permission. A 403 response is reported as a permission error with this guidance.

## Data and interpretation

- Billable usage is `max(0, usedNanoUsd - includedNanoUsd)`, matching the provider's distinction between gross inference and the included amount.
- Gross usage, included amount, request count, and configured spending limit are shown as details when the API provides them.
- Spend is not converted into a primary quota percentage. A reporting interval's end date is not treated as a reset.
- ZeroGPU quota is an optional secondary window. When returned, GPU time used/remaining and its reported reset are shown; a failure to fetch this optional endpoint does not discard billing data.
- Username and plan are optional identity details cached for up to 12 hours under a token-specific cache key.

The billing response is parsed defensively. Missing required values, malformed JSON, or invalid numbers fail closed with a response-format error rather than silently reporting an incomplete or overstated charge.
