# OpenAI live usage and provider balance sync

Status: done.

The implemented behavior is verified in [hosted run 38562031134](https://github.com/ColumbusLabs/QuotaKit/actions/runs/38562031134) on `fb05ca054`: credential isolation, three-state shared sync, compatible decoding, provider balance eligibility and both plugin engines passed. The run’s remaining failures were static Cursor argument formatting and an unrelated Italian credential-placeholder expectation; both are corrected by the qualification follow-up. All applicable checks still gate the exact final head of [PR #245](https://github.com/ColumbusLabs/QuotaKit/pull/245), which records the final CI and merge receipt.

OpenAI tokens-per-minute charts are a Mac presentation of one-minute organization usage buckets. QuotaKit counts all input tokens (including cached input) plus output, excludes Batch traffic, pools models sharing a configured limit and keeps project limits as context. Manual limits belong to the selected credential; a token account never inherits the provider-key list.

Provider configuration and encrypted token-account sync use three states: omitted fields from old peers preserve local values; explicit empty arrays clear limits; nonempty validated arrays replace them. Preserve existing CloudKit record types and encrypted secret field names. The iPhone usage payload remains compatible; no throughput quota or notification is fabricated on mobile.

Parallel joins fal and FLORA as a default-disabled balance-only provider. Append provider identifiers and generated manifests; retain every prior ID. Export billing values through existing display-only wire fields, colors and assets, excluding quota widgets and transition subscriptions. Provider config secrets, browser consent/manual/off rules and no-UI background access remain intact.

Regression coverage must establish credential isolation, older-peer preservation/explicit clear, compatible shared snapshot decoding and balance-only mobile eligibility in hosted CI. Existing Mac/Linux/iOS/golden/architecture gates remain required. No build numbers, release metadata, appcast, signing, entitlements or CloudKit schema are changed.
