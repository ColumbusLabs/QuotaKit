# Upstream config safety, runtime and quota selection

Status: done — implemented behavior verified in hosted CI; final merge qualification is tracked in [PR #249](https://github.com/ColumbusLabs/QuotaKit/pull/249).

Integrate the 2026-10-16 frozen upstream range through `f50cd6cee` into QuotaKit. The complete immutable commit accounting and fork decisions are in [the integration ledger](../../docs/upstream-sync-2026-10-16.md).

Preserve all 104 provider IDs, persisted settings, shared/iPhone data, additive widget quota slots and account ownership. Adapt credential/config safety and opt-in Claude desktop cookies with no background Keychain UI; adopt bounded cost-history/PTY and Mac settings/menu behavior. Release metadata, build numbers, appcast and distribution are outside this source integration.

Independent source review covers the credential/config/runtime and shared-contract adaptations. Hosted run `38893652427` verifies the implemented behavior on `31f47553b`: all four Mac shards, the Mac/widget compatibility build, Linux x86 and iOS checks pass. Mac discovery and execution retain the complete 15,119-method inventory. No local builds, tests, apps or live account probes were used.

That run still fails a stale shell mock count and an unchanged Linux ARM ownership fixture timeout. The two count assertions are corrected without changing test gates; the final PR head must pass every applicable hosted check, including ARM, before merge. The integration ledger records these qualification findings and the PR retains the final CI and merge receipts.
