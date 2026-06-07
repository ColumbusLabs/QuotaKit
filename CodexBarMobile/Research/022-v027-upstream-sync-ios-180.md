# 022 — v0.27.0 Upstream Sync + iOS 1.8.0

**Status:** draft (in-progress)
**Date:** 2026-05-19
**Target release tag:** `v0.27.0-mobile.1.8.0`

---

## Goal

1. Sync Mac fork to upstream **v0.27.0** with full feature parity.
2. Build iOS **1.8.0** with bridge support for every new v0.27.0 feature
   that surfaces a user-visible signal (provider tile, usage card,
   notification copy).
3. Ship **one combined release** — do not split Mac/iOS.

---

## Upstream delta v0.26.1 → v0.27.0

- 90+ commits
- 363 files changed (+23,596 / −2,780)
- `Shared/` and `CodexBarMobile/` untouched by upstream (fork-owned)

### Conflict surface (dry-run)

12 conflict points, all expected:

| File | Reason |
|---|---|
| `.github/workflows/ci.yml` | Fork has iOS jobs + audit_localized_keys |
| `.gitignore` | Fork adds `*.xcarchive`, `/build/`, etc. |
| `CHANGELOG.md` | Fork keeps Mobile section on top of upstream entries |
| `README.md` | Fork header |
| `Scripts/compile_and_run.sh` | Fork iOS bridge |
| `Scripts/package_app.sh` | Fork notarize flow |
| `Scripts/sign-and-notarize.sh` | Fork Developer ID `3TUERHN53E` |
| `Sources/CodexBarCore/Vendored/CostUsage/CostUsageCache.swift` | Fork patches |
| `Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift` | Fork patches |
| `Tests/CodexBarTests/CostUsageCacheTests.swift` | Fork test changes |
| `appcast.xml` | Fork mobile entries |
| `version.env` | Fork subdecimal BUILD_NUMBER scheme |

Resolution strategy per file recorded inline in Phase A below.

---

## v0.27.0 features

### A. New providers (7)

| # | Provider | Upstream credential | iOS support | iOS view template |
|---|---|---|---|---|
| 1 | **Grok (xAI)** | Local CLI + web billing fallback | YES | Cost/balance card |
| 2 | **ElevenLabs** | API key | YES | Credit/voice-slot card |
| 3 | **Deepgram** | API key | YES | Project breakdown |
| 4 | **GroqCloud** | API key (Prometheus) | YES | Enterprise metrics |
| 5 | **LLM Proxy** | API key | YES | Quota stats + key health |
| 6 | **MiniMax** (extends v0.26) | Web session | YES | Billing history (30-day) |
| 7 | **OpenCode Go Zen** (extends OpenCode Go) | Workspace dashboard | YES | Pay-as-you-go balance |

### B. Existing provider extensions

| Provider | New surface | iOS impact |
|---|---|---|
| **Claude** | Anthropic Admin API source (`sk-ant-admin…`) | New data path → extend existing Claude tile |
| **Claude** | Spend-limit metric on Enterprise plan | New metric in Claude card |
| **Claude** | Plan-utilization history separated Team vs Personal Max | Existing chart, no schema change |
| **Codex** | Workspace grouping + per-account snapshot + weekly pace detail | Extend existing Codex tile |
| **Kiro** | Overage credit + overage cost menu bar modes | Extend Kiro tile with overage badge |
| **OpenAI** | Cost history window 1–365 days configurable | Existing chart, add window picker |

### C. Notifications + UX

- **Quota warnings include triggering account.** Builds on fork-private
  V026 envelope. May require new envelope field for account identity.
- **Permission prompts notify user.** Mac-only (browser/keychain consent).

### D. Architectural refactors (Mac-only, no iOS impact)

- Shared provider HTTP transport seam (#892)
- Centralize provider HTTP responses (`ad33b327`)
- Reuse inline usage dashboards (extends OpenAI pattern to Claude/Codex/Vertex/Bedrock/OpenRouter/z.ai/Mistral)
- Codex multi-account: workspace grouping, persisted per-account snapshots, auth fingerprint matching

### E. CLI additions (Mac CLI binary, no iOS impact)

- `codexbar config set-api-key`
- `codexbar config providers / enable / disable`
- `--all-accounts` exports every Codex account
- `codexbar serve` rejects non-loopback `Host` headers

---

## Version targets

| Variable | Current | Target | Rule |
|---|---|---|---|
| `MARKETING_VERSION` (Mac) | `0.26.4` | **`0.27.0`** | Upstream is 0.27.0; no extra fork Mac UI yet → match upstream |
| `BUILD_NUMBER` (Mac) | `63.4` | **`65.1`** | Upstream tag v0.27.0 BUILD=65; fork's first patch → `.1` |
| `MOBILE_VERSION` | `1.7.0` | **`1.8.0`** | iOS ships major feature batch (7 providers) → minor bump |
| `UPSTREAM_VERSION` | `v0.26.1` | **`v0.27.0`** | After release is shipped to users |
| `UPSTREAM_SYNC_DATE` | `2026-05-17` | **`2026-05-19`** | Today |
| iOS `MARKETING_VERSION` | `1.7.0` | **`1.8.0`** | Same as MOBILE_VERSION |
| iOS `CURRENT_PROJECT_VERSION` | `131` | **`132+`** | Increment per commit |
| `sparkle:version` | `63.4.1.7.0` | **`65.1.1.8.0`** | `BUILD_NUMBER.MOBILE_VERSION` |
| Release tag | `v0.26.2-mobile.1.7.0` | **`v0.27.0-mobile.1.8.0`** | `v{MARKETING}-mobile.{MOBILE}` |

---

## Workflow phases

### Phase A — Mac merge upstream v0.27.0  ← STARTING NOW
- `git merge v0.27.0` into `mobile-dev`
- Resolve 12 conflicts per table above
- `swift build` smoke compile
- Single merge commit on `mobile-dev`

### Phase B — iOS surface decisions matrix
- Lock per-provider view templates and color choices in this doc
- Confirm Shared/ envelope shape extensions

### Phase C — Mac → iOS bridge plumbing
- Add `Shared/Models/V027Snapshots.swift` (or extend V026) with new fields:
  - Grok / ElevenLabs / Deepgram / GroqCloud / LLM Proxy snapshots
  - OpenCode Go Zen balance
  - Kiro overage credit + overage cost
  - Quota warning account identity
- Extend `Shared/Notifications/QuotaProviderList.swift` push IDs
- Mac fetcher → envelope wiring (one fetcher at a time)

### Phase D — Mac draft release
- Bump `version.env` (table above)
- Run `docs/cloudkit-deploy-audit.md` audit
- `Scripts/sign-and-notarize.sh`
- `Scripts/make_appcast.sh`
- `gh release create --draft v0.27.0-mobile.1.8.0`

### Phase E — Mac end-to-end test
- Launch signed app, walk every provider, every menu, every Settings pane
- CloudKit sync test (Mac → iOS sim)
- Sparkle update path test
- Regression checklist: G1-G6 multi-account, quota warnings, mock injector
- Block release until all pass

### Phase F — iOS 1.8.0 implementation
- `CodexBarMobile/project.yml` — bump MARKETING + BUILD
- `xcodegen generate`
- `ProviderColorPalette` — 5 new colors (Grok, ElevenLabs, Deepgram, GroqCloud, LLM Proxy)
- `MockProviderInjector` — 7 new mock entries (5 new + Kiro overage + OpenCode Zen)
- `Views/ProviderDetail/` — new view templates
- `Localizable.xcstrings` — 4-language strings
- `MobileReleaseNotesCatalog` — `1.8.0` entry
- `CHANGELOG.md` — Added/Changed/Fixed sections
- `xcodebuild build`, simulator smoke test

### Phase G — iOS test + combined ship
- Real device test
- TestFlight upload
- Re-bundle Mac release with MOBILE_VERSION=1.8.0 → sparkle:version `65.1.1.8.0`
- Publish appcast on `mobile-dev`
- Publish GitHub release on `ColumbusLabs/QuotaKit`

---

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Large merge may break Mac build | Resolve incrementally; `swift build` after every conflict batch |
| R2 | Shared HTTP transport refactor may move provider HTTP call sites | Re-run Shared envelope tests after Phase A |
| R3 | v0.27.0 Codex multi-account changes may conflict with our G1-G6 work | Compare diff before merge; preserve G1-G6 envelope fields |
| R4 | CloudKit schema may need new fields → Production deploy required | Run audit in `docs/cloudkit-deploy-audit.md` before Phase D |
| R5 | 7 new provider tiles need real credentials to test | Most will be mock-only; flag in test checklist |
| R6 | Many open upstream issues post-v0.27.0 (e.g. #1031 Claude usage never loads, #1037 OpenAI broken) | These are pre-existing; do NOT block release on them; track separately |

---

## Open upstream issues — fix in this release?

Not blocking, but worth scanning:

| # | Issue | Decision |
|---|---|---|
| #1048 | Codex OAuth-only setups | Out of scope (upstream still designing) |
| #1047 | Claude probe creates `.app` in Launchpad | Defer to upstream fix |
| #1046 | Linux libxml2.so.2 | Not us (Linux only) |
| #1044 | Ollama doesn't work | Defer to upstream |
| #1043 | Kimi usage progress bar | Verify in Mac testing |
| #1037 | OpenAI connection broken | Verify with credentials |
| #1035 | Claude Enterprise decimal point | Verify in Mac testing |
| #1033 | OpenAI web refresh high CPU | Defer |
| #1031 | Claude usage never loads | Verify in Mac testing |
| #1028 | Codex not required for startup | Verify |
| #1023 | Peak hours | Out of scope (fork removed in #1025) |
| #1020 | Auto-invalidate Codex cost cache | PR #1042 — upstream may merge before release |

Reviewed during Phase E testing; any reproducible regressions become
their own hotfix on top of `v0.27.0-mobile.1.8.0`.

---

## Open questions

1. **iOS view template per provider** — locked when Phase B starts; default is "API key card with reset+limit", reset window per provider.
2. **CloudKit schema deploy** — answered after Phase C; if any new field, deploy Production via Dashboard.
3. **Test depth on Mac** — user runs signed app for end-to-end pass; agent provides smoke build + xcodebuild compile only.
