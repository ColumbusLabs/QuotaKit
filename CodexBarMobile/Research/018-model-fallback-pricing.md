# 018 · Generic Model Fallback Pricing — Research

**Status:** Phase 0 design input for Mac 0.23 fallback subsystem (P0 of 10-step plan).
**Author:** Architect role.
**Date:** 2026-04-27.
**Drives:** P1 (resolver protocol) → P9 (TestFlight respin).

---

## 1. Why this exists

Mac 0.20.3 shipped with `claude-opus-4-7` traffic in users' JSONL logs but no row in `CostUsagePricing.claude`. `CostUsagePricing.claudeCostUSD()` returned `nil` → `CostUsageScanner+Claude.swift:120` substituted `0` → Daily Spend chart showed `$0`. Same shape will recur for every future model release we don't ship pricing for: Claude 4.8, Sonnet 5, GPT-5.6, GPT-6, hypothetical `gpt-5.5-codex-turbo`, etc.

User mandate: "any provider could suddenly ship several new model names" — we need a generic fallback, not Claude-only patching.

---

## 2. The 27-provider cost-source matrix

| Provider | Cost source | Token-pricing fallback applies? | Notes |
|---|---|---|---|
| **Claude** | Local table (`CostUsagePricing.claude`) | **YES** | JSONL → pricing → CloudKit |
| **Codex** | Local table (`CostUsagePricing.codex`) | **YES** | JSONL → pricing → CloudKit |
| **VertexAI** | Local table (Claude pricing reused) | **YES** | Same JSONL pipeline, vertex-filter |
| Cursor | API-returned | No | `providerCost` from HTTP body |
| Mistral | API-returned (`totalCost` field) | No | Spend-based, no per-token |
| Synthetic | API-returned (per-quota cost) | No | Cost is in the quota object itself |
| Antigravity | API-returned (quota-only, no $) | No | Model IDs leak to UI but no pricing |
| Gemini | API-returned (quota-only, no $) | No | `GeminiModelQuota.modelId` for UI |
| Factory | API-returned (quota-only, no $) | No | Model IDs from `statusJSON` |
| Zai | API-returned (`modelCode` opaque) | No | Already opaque code, no readable name |
| Abacus | API-returned (no $) | No | Single credit pool |
| Alibaba, Amp, Augment, Copilot | API quota only | No | No cost concept |
| JetBrains, Kilo, Kimi, KimiK2 | API quota only | No | No cost concept |
| Kiro, MiniMax, Ollama | API quota only | No | No cost concept |
| OpenCode, OpenCodeGo, OpenRouter | API quota only | No | No cost concept |
| Perplexity | Credit-based (3 pools) | No | `SyncPerplexityCreditSummary` |
| Warp | API quota only | No | No cost concept |

**Conclusion:** Token-cost fallback is **strictly a Tier-A problem** (Codex + Claude + VertexAI). 24 other providers have no local pricing table to miss against — their cost arrives pre-computed by the upstream API, or doesn't exist.

This is good news: the algorithmic surface area is small. The investment is in **making the fallback robust enough that future Tier-A pricing churn never silently zeros out**, not in instrumenting 27 paths.

---

## 3. Secondary leakage surface (Tier B model name leakage)

Six providers expose model IDs in UI snapshots but **don't** depend on local pricing:

| Provider | Where model name leaks | Risk |
|---|---|---|
| Antigravity | `modelId` (`pro-low`, `lite`, `autocomplete`) → UI rate-window labels | Low — no $ implication |
| Cursor | `case gpt4 = "gpt-4"` enum → potentially in cost row | Low — small enum, hard to grow |
| Factory | Quota model IDs from `statusJSON` | Low — server-driven |
| Gemini | `GeminiModelQuota.modelId` (`gemini-2.0-flash`, etc.) | Low — server-driven, no $ |
| Synthetic | Cost-per-quota line items | Low — already paired with $ |
| Zai | Opaque `modelCode` from API | None — opaque, not a model family string |

**Decision:** Tier B is **out of scope for the fallback resolver**. If Gemini ships `gemini-2.5-flash` tomorrow, the iOS UI just shows `gemini-2.5-flash` raw — no $0 bug, no broken row. We can revisit Tier B in a future iteration if user-visible label mapping becomes a problem.

---

## 4. Family-pattern dissection (Tier A)

### 4.1 Claude

Pattern: `claude-{family}-{major}-{minor}[-{YYYYMMDD}]`

| family | example versions known to pricing | inferred extension space |
|---|---|---|
| `opus` | `4`/`4-1`/`4-5`/`4-6`/`4-7` | `4-8`, `5`, `5-1`, … |
| `sonnet` | `4` (date-suffixed)/`4-5`/`4-6` | `4-7`, `5`, `5-1`, … |
| `haiku` | `4-5` | `4-6`, `5`, … |
| `design`, `routines` | (gate IDs, not real models) | not real models — **excluded from resolver** |

Vertex AI variant: same string with `@` instead of last `-` between version and date (`claude-opus-4-5@20251101`). `normalizeClaudeModel` already strips both date forms.

### 4.2 Codex (GPT-5 family)

Pattern: `gpt-{major}.{minor}[-{variant}][-{tier}]`

| variant | tiers seen | extension space |
|---|---|---|
| (none, base) | `gpt-5.X` | new minor versions |
| `codex` | `gpt-5.X-codex`, `gpt-5.X-codex-max`, `gpt-5.X-codex-mini`, `gpt-5.X-codex-spark` | new tiers, e.g. `codex-turbo` |
| `mini`, `nano`, `pro` | `gpt-5.X-mini` etc. | same |
| Also: `openai/` prefix gets stripped by `normalizeCodexModel` |

Notable special case: `gpt-5.3-codex-spark` has price `0` with `displayLabel: "Research Preview"` — the resolver must respect "intentionally-zero" rows and not treat them as missing pricing.

---

## 5. Resolver protocol (concept, full design lives in P1)

```swift
protocol ModelFamilyResolver {
    associatedtype Pricing
    /// Parse a raw model name into a structured (family, version) pair.
    /// Returns nil if the name doesn't match this provider's grammar.
    func parse(_ raw: String) -> ParsedModel?
    /// Walk the table backward (or by some priority) to find a usable entry
    /// matching the same family but a known version.
    func fallback(for parsed: ParsedModel, in table: [String: Pricing]) -> (key: String, pricing: Pricing)?
}

struct ParsedModel: Equatable {
    let family: String              // "opus" | "codex" | "codex-mini" | …
    let majorVersion: Int           // 4 | 5 | 5
    let minorVersion: Int?          // 7 | nil | 1
    let dateSuffix: String?         // "20251101" | nil
    let raw: String                 // for logging
}
```

**Fallback strategy** (per provider, locked by tests):

1. Same family, same major, **closest minor ≤ requested** (e.g. `opus-4-8` → `opus-4-7` → `opus-4-6`).
2. If no smaller minor: **closest minor in same major ≥ requested** (e.g. `opus-4-3` → `opus-4-5` because we don't have `4-3`).
3. If no same-major match: **closest major-1 entry, top minor of that major** (e.g. `opus-5-0` falls back to `opus-4-7`).
4. If still nothing: **family-default** (Claude → `opus-4-7`; Codex → `gpt-5`).
5. If even family lookup fails (unknown family): **provider-default** (Claude → `claude-opus-4-7`; Codex → `gpt-5`).
6. Result is **always returned with `isEstimated: true`** — never silently treated as authoritative.

Open question for P1: should "closest minor" prefer ≤ requested or just absolute distance? Test matrix in P7 will pin this.

---

## 6. Wire-format impact

`SyncCostBreakdown` and `SyncDailyPoint` are non-optional `costUSD: Double` today. To carry the "estimated" flag to iOS we need either:

- **Option A:** Add `isEstimated: Bool?` via `decodeIfPresent` on `SyncCostBreakdown`, `SyncDailyPoint`, and `SyncCostSummary` (aggregate). Old Mac → new iOS: `nil` decodes to `false`, no badge shown. New Mac → old iOS: field ignored. **Forward-compat invariant** matches the existing `?? []` precedent set by `modelBreakdowns` / `serviceBreakdowns` (`UsageSnapshot.swift:78–87`).
- **Option B:** Add a separate `estimatedCostUSD: Double?` field. Cleaner but doubles UI mapping logic.

**Recommendation:** Option A. P4 will spec the exact codable additions and the upward aggregation rule (a daily total is `isEstimated` iff *any* model in that day used a fallback). P5 covers iOS UI badge.

---

## 7. Diagnostic surface (P6)

The fallback path is invisible to users until the next time Anthropic ships a model name. To shorten the next discovery cycle:

- **Mac log category** `pricing` (new). Every fallback emits `unknown-model {raw} → matched {key} via {strategy}`.
- **Mac Diagnostic panel** lists top-10 unknown-model rows seen in the current 30-day window with a copy-friendly format. So when user reports a billing surprise we can ask them to send the panel.
- **Telemetry** stays opt-in / off by default — purely user-facing diagnostic.

---

## 8. Backward compatibility constraints

- `decodeIfPresent` for every new wire field (Build 79 regression test still applies).
- `claudeCostUSD()` and `codexCostUSD()` keep their existing nullable return so call sites that explicitly check `nil` (none today, but possible in upstream merges) don't break.
- Resolver lookup is a **wrapper** around the existing dictionary, never replaces it. Known-model lookup takes the fast path; only unknowns walk family fallback.
- Vertex variant of Claude (`@`-separator) keeps going through `normalizeClaudeModel` first; resolver only sees normalized strings.

---

## 9. Out of scope (recorded so we don't accidentally do it)

- Tier B label mapping (Antigravity / Cursor / Factory / Gemini / Synthetic / Zai).
- Provider-side pricing churn for non-Tier-A providers (none have local tables to drift).
- Cost back-calculation for missing tokens (we never had raw tokens for non-Tier-A; nothing to recompute).
- iOS-side fallback computation (cost is computed Mac-side; iOS just renders).
- Upstream PR (per user direction; fork-only enhancement).

---

## 10. Provider table — handoff to P1

Resolvers to implement in P2:

1. `ClaudeFamilyResolver` — covers `.claude` and `.vertexai` (same dictionary).
2. `CodexFamilyResolver` — covers `.codex`.

Both register through a shared `CostUsagePricing.resolve(model:tableKey:)` entry point. Adding a third resolver later (if any provider grows a local pricing table) is one new type + one switch case.

P3 adapters for "other local-pricing providers" turns out to be **empty** — survey found none. P3 collapses to a documentation pass confirming "no other providers need a resolver as of 2026-04-27".

---

## 11. Acceptance for P0

- [x] All 27 providers' cost path classified.
- [x] Tier A locked to Codex/Claude/VertexAI.
- [x] Family grammar documented for both Tier A providers.
- [x] Fallback rules drafted (precedence + estimated-flag invariant).
- [x] Wire-format approach chosen (Option A: `decodeIfPresent isEstimated`).
- [x] Out-of-scope list pinned.
- [ ] User review (you).
