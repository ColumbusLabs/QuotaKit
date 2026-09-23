# Hugging Face provider integration

Status: done

## Goal

Add Hugging Face Inference Providers billing to QuotaKit while preserving its distinct spend semantics, optional ZeroGPU quota, existing provider catalog, and Mac-to-iPhone compatibility.

## Contract and adaptation

- Register `huggingface` additively as a first-party provider; keep every existing provider ID and generated manifest entry.
- Store tokens through QuotaKit settings/token accounts and support the official Hugging Face environment variables and `hf auth login` token file without reading live credentials in tests.
- Treat current-month billable inference charges as spend, subtracting included usage from gross usage. Do not invent a primary quota percentage or reset from the billing report cutoff.
- Map ZeroGPU to the optional secondary window and keep its reset distinct from billing dates. Identity cache entries are keyed by token.
- Carry the additive provider ID, presentation metadata, icon, and alert-subscription catalog entry across the existing generic sync contract; do not change shared record schemas or existing CloudKit subscription identifiers.
- Preserve QuotaKit naming, paths, release ownership, build metadata, and signing configuration.

## Verification

- Parser, billing, ZeroGPU, identity-cache, and token-file behavior use fixtures and stubs only.
- Focused Mac tests cover provider behavior, settings discovery, credentials, and architecture registration.
- Focused mobile tests cover provider ID/color/icon and quota-alert catalog compatibility; locale lint covers in-app release-note translations.
- Full repository and full iOS suites are not required for this scoped provider addition unless a focused check exposes a cross-cutting failure.
