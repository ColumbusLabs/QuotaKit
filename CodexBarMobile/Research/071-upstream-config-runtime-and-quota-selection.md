# Upstream config safety, runtime and quota selection

Status: implementation and hosted verification in progress.

Integrate the 2026-10-16 frozen upstream range through `f50cd6cee` into QuotaKit. The complete immutable commit accounting and fork decisions are in [the integration ledger](../../docs/upstream-sync-2026-10-16.md).

Preserve all 104 provider IDs, persisted settings, shared/iPhone data, additive widget quota slots and account ownership. Adapt credential/config safety and opt-in Claude desktop cookies with no background Keychain UI; adopt bounded cost-history/PTY and Mac settings/menu behavior. Release metadata, build numbers, appcast and distribution are outside this source integration.

Use independent source review and exact-head hosted CI. Shared/mobile-consuming paths receive hosted iOS checks; do not run local builds, tests, apps or live account probes. Mark this record done only after the implemented behavior is verified by the applicable hosted gates.
