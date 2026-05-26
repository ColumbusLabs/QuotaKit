# 023 — v0.29.0 Upstream Sync + iOS 1.9.0

**Status:** in-progress
**Date:** 2026-05-25
**Target release tag:** `v0.29.0-mobile.1.9.0`
**Branch:** `upstream-sync/v0.29.0-mobile.1.9.0`
**Tracking issue:** [#10](https://github.com/o1xhack/CodexBar-Mobile/issues/10)

---

## Goal

1. Sync Mac fork to upstream **v0.29.0** with full feature parity.
2. Build iOS **1.9.0** with bridge support for every new v0.28/v0.29 feature
   that surfaces a user-visible signal.
3. Ship **one combined release** — do not split Mac/iOS.

**Scope boundary:** merge the **`v0.29.0` tag**, NOT `upstream/main` (which is at
0.29.1). The 0.29.1 fixes (Claude OAuth extra-usage 100× currency fix #1114,
Grok reset-window labels #1148, Groq icon #1112, workday markers #1102,
zh-Hant Mac strings, Codex fork-overcount #1143) are **deferred to a future
sync** — they are explicitly out of scope here.

---

## Upstream delta v0.27.0 → v0.29.0

- 79 commits.
- `Shared/` and `CodexBarMobile/` untouched by upstream (fork-owned) — zero
  conflicts there.
- Conflict surface: 16 files, all fork-owned (resolved in Phase A).

---

## v0.28.0 + v0.29.0 features

### A. New providers (3)

| Provider | UsageProvider case | Descriptor id | Credential | Data shape | iOS surface |
|---|---|---|---|---|---|
| **Alibaba Token Plan** (Bailian) | `.alibabatokenplan` | `alibaba-token-plan.web` | Browser / manual cookies | **Generic** `UsageSnapshot` — single `primary` RateWindow (30-day quota %, resetsAt, "X / Y credits") | Register + color + name + icon + mock. Generic bar rendering. |
| **T3 Chat** | `.t3chat` | `t3chat.web` | Web session (cURL paste on 429) | **Generic** — `primary` (4-hour %) + `secondary` (month/overage %) | Same. Generic bars. |
| **Azure OpenAI** | `.azureopenai` | `azureopenai.api` | API key + endpoint + deployment | Deployment-status **validation** only (no usage snapshot type) | Register + name + color; likely status-only card. Confirm in Phase F whether it emits a usable snapshot. |

**Key architectural finding:** unlike the v0.27.0 batch (5 dedicated rich cards
needing `SyncGrokBilling`-style envelope blocks), all three v0.29 providers map
to the **generic `UsageSnapshot`** (`primary`/`secondary` `RateWindow`s) via
`toUsageSnapshot()`. They flow through the existing `ProviderUsageSnapshot`
generic fields — **no new per-provider envelope blocks required.** iOS work is
therefore registration + cosmetics + mock, not new view templates.

### B. Existing-provider extensions

| Provider | New surface | iOS impact |
|---|---|---|
| **Ollama** | API-key auth as alternative to browser cookies (#1044) | Mac-side auth path; no new iOS data. Verify existing Ollama card unaffected. |
| **Codex** | Standard vs Fast spend/token splits in model breakdowns (#1070) | Lives in cost-history (`SyncCostSummary`/`SyncDailyCost`/`SyncCostBreakdown`). **Decision (Phase C):** does iOS surface the split, or keep the combined total? Default: keep combined for 1.9.0 (the split is a Mac menu detail); revisit if a V029 field is cheap. |
| **OpenCode / OpenCode Go** | Workspace renewal dates (#1099) | `renewalAt: Date?` already exists in the OpenCode credits envelope block. Confirm Mac populates it for the workspace renewal; likely zero new schema. |
| **MiniMax** | Exclude failed billing-history records (#1089) | Data-correctness; flows through existing `SyncMiniMaxBillingHistory`. No schema change. |

### C. Mac-only / no iOS impact

- Spanish + Catalan Mac language packs (#1041) — Mac `.lproj` only. iOS keeps
  its 4-language policy (en/zh-Hans/zh-Hant/ja); es/ca **not** added to iOS.
- Peak-hours indicator removed (#1023) — fork dropped the `off_peak` strings.
- Menu-bar status-item recovery, Codex per-account snapshot persistence,
  Antigravity discovery, libxml2 Linux, PTY child-process cleanup, etc. —
  Mac/Linux internals.

---

## Version targets (per `docs/versioning.md`)

| Variable | From | To | Rule |
|---|---|---|---|
| `MARKETING_VERSION` (Mac) | `0.27.0` | **`0.29.0`** | Match upstream tag; no extra fork Mac UI |
| `BUILD_NUMBER` (Mac) | `65.5` | **`68.1`** | upstream v0.29.0 BUILD=68; fork patch `.1` |
| `MOBILE_VERSION` | `1.8.0` | **`1.9.0`** | iOS ships provider batch → minor bump |
| `UPSTREAM_VERSION` | `v0.26.1` | **`v0.29.0`** | aligned tag after this sync |
| `UPSTREAM_SYNC_DATE` | `2026-05-19` | **`2026-05-25`** | today |
| iOS `MARKETING_VERSION` | `1.8.0` | **`1.9.0`** | = MOBILE_VERSION |
| iOS `CURRENT_PROJECT_VERSION` | `137` | **`138`+** | +1 per commit |
| `sparkle:version` | `65.5.1.8.0` | **`68.1.1.9.0`** | `BUILD_NUMBER.MOBILE_VERSION` |
| Release tag | `v0.27.0-mobile.1.8.0` | **`v0.29.0-mobile.1.9.0`** | `v{MARKETING}-mobile.{MOBILE}` |

---

## Workflow phases

### Phase A — Mac merge v0.29.0 ✅ DONE (commit `f336d892`)
- `git merge v0.29.0`; resolved 16 fork-owned conflicts.
- CostUsageCache: combined fork `pricingFingerprint` + upstream `producerKey`.
- 2 fork switches + 1 test adapted for new enum cases.
- `swift build` clean; `CostUsageCacheTests` 15/15.

### Phase B — iOS surface decisions ← THIS DOC
- Locked above: 3 new providers via generic snapshot; extensions mostly
  schema-free. Open decision: Codex std/fast split on iOS (default: defer).

### Phase C — Mac → iOS bridge plumbing
- Confirm `SyncCoordinator` maps the 3 new providers generically (no
  per-provider allow-list gate) — add to any gate if present.
- Register `.alibabatokenplan` / `.t3chat` / `.azureopenai` in iOS
  `QuotaProviderList` and the Mac→iOS provider id set.
- Confirm OpenCode `renewalAt` is populated for workspace renewal.
- (Optional) V029 field for Codex std/fast split if cheap + worth it.
- Cross-version envelope round-trip tests (old iOS ⇄ new Mac, new iOS ⇄ old Mac).

### Phase D — Mac draft release
- version.env already bumped. Run `docs/cloudkit-deploy-audit.md` audit (new
  fields? likely none → no Production deploy, but verify).
- `Scripts/sign-and-notarize.sh` → `make_appcast.sh` (sparkle `68.1.1.9.0`).
- `gh release create --draft v0.29.0-mobile.1.9.0` on o1xhack/CodexBar-Mobile.
- **Needs user Mac + Developer ID + Sparkle key + App Store Connect key.**

### Phase E — Mac end-to-end test + regression
- Full `swift test`. Walk every provider/menu/Settings pane.
- CloudKit Mac→iOS sim sync. Sparkle update path. Multi-account / quota / mock.
- Verify no old-feature breakage from the 79-commit merge.

### Phase F — iOS 1.9.0 implementation
- `project.yml` MARKETING 1.9.0 + BUILD 138; `xcodegen generate`.
- `ProviderColorPalette` — 3 new colors.
- `MockProviderInjector` — 3 new mock entries (generic snapshots).
- `Localizable.xcstrings` — provider display names ×4 languages.
- `MobileReleaseNotesCatalog` — `1.9.0` entry; `CHANGELOG.md` fork section.
- Provider icons for the 3 (reuse upstream `ProviderIcon-t3chat.svg` etc.).
- `xcodebuild build` + simulator smoke + `Scripts/lint.sh` i18n audit.

### Phase G — iOS test + combined ship
- iOS unit tests + simulator + real device (needs user device).
- TestFlight upload (needs user credentials).
- Re-bundle Mac release with MOBILE 1.9.0; publish appcast on mobile-dev;
  publish GitHub release; merge sync branch → mobile-dev.

### CR gate — Opus 4.7 agent review after Phase A (merge), Phase C (bridge),
Phase F (iOS). Loop until clean.

---

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | New providers don't flow to iOS because a per-provider sync gate exists | Phase C: audit SyncCoordinator envelope builder for allow-lists |
| R2 | Azure OpenAI emits no usable snapshot (validation-only) → empty iOS card | Confirm in Phase F; show status-only card or skip from iOS if no data |
| R3 | Codex std/fast split omitted disappoints power users | Documented decision: combined total for 1.9.0; fast-follow if requested |
| R4 | CloudKit schema needs new field → Production deploy | Run audit in Phase D; generic snapshot path adds no CK fields |
| R5 | Real-credential testing for 3 new providers unavailable | Mock-only coverage; flag in test checklist |
| R6 | 0.29.1 deferral confuses users expecting the Claude 100× fix | Out of scope by design; will land in next sync |
