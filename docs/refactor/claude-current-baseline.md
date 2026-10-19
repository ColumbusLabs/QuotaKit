---
summary: "Current Claude behavior baseline before vNext refactor work."
read_when:
  - Planning Claude refactor tickets
  - Changing Claude runtime/source selection
  - Changing Claude OAuth prompt or cooldown behavior
  - Changing Claude token-account routing
---

# Claude current baseline

This document is the current-state parity reference for Claude behavior in CodexBar.

Use it when later tickets need to preserve or intentionally change Claude behavior. When the refactor plan,
summary docs, and running code disagree, treat current code plus characterization coverage as authoritative, and use
this document as the human-readable summary of that current state.

## Scope of this baseline

This baseline captures the current behavior surface that later refactor work must preserve unless a future ticket
changes it intentionally:

- runtime/source-mode selection,
- prompt and cooldown behavior that affects Claude OAuth repair flows,
- token-account routing at the app and CLI edges,
- provider siloing and web-enrichment rules,
- the current relationship between the public Claude doc and the vNext refactor plan.

## Active behavior owners

Current Claude behavior is defined by several active owners, not one central planner:

- `Sources/CodexBarCore/Providers/Claude/ClaudeProviderDescriptor.swift`
  owns the main provider-pipeline strategy order and fallback rules.
- `Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift`
  still owns a separate direct `.auto` path, delegated refresh, prompt/cooldown handling, and web-extra enrichment.
- `Sources/CodexBar/Providers/Claude/ClaudeSettingsStore.swift`
  owns app-side token-account routing into cookie or OAuth behavior.
- `Sources/CodexBarCLI/TokenAccountCLI.swift`
  owns CLI-side token-account routing and effective source-mode overrides.
- `Sources/CodexBarCLI/CLIUsageCommand.swift`
  adds one-shot Claude CLI Auto precedence for the configured claude-swap active slot before the generic pipeline.
- `Sources/CodexBarCore/TokenAccountSupport.swift`
  owns the current string heuristics that distinguish Claude OAuth access tokens from cookie/session-key inputs.

## Current runtime and source-mode behavior

### Main provider pipeline

The generic provider pipeline currently resolves Claude strategies in this order:

| Runtime | Selected mode | Ordered strategies | Fallback behavior |
| --- | --- | --- | --- |
| app | auto | `oauth -> cli -> web` | OAuth can fall through to CLI/Web. CLI can fall through to Web only when Web is available. Web is terminal. |
| app | oauth | `oauth` | No fallback. |
| app | cli | `cli` | No fallback. |
| app | web | `web` | No fallback. |
| cli (macOS) | auto | `web -> cli` | Web can fall through to CLI. CLI is terminal. |
| cli (Linux) | auto | `web -> oauth -> cli` | OAuth is attempted when available after Web; Web/OAuth can fall through to CLI. CLI is terminal. |
| cli | oauth | `oauth` | No fallback. |
| cli | cli | `cli` | No fallback. |
| cli | web | `web` | No fallback. |

This behavior is owned by `Sources/CodexBarCore/Providers/Claude/ClaudeProviderDescriptor.swift`
through `ProviderFetchPlan` and `ProviderFetchPipeline`.

On Linux CLI Auto, OAuth is a fallback between Web and the Claude PTY. macOS CLI Auto keeps Web before CLI and does
not add the OAuth step.

### One-shot CLI active-slot behavior

For `quotakit usage --provider claude`, enabled claude-swap takes precedence only in Auto mode when there is no
explicit token-account selection. QuotaKit reads the active slot's projected snapshot, including its measurement
time and stale retained usage where available. If listing fails or the active slot has no usable snapshot, the
ordinary configured source continues and its label includes `(claude-swap fallback)`; adapter cancellation stops
the command. Explicit non-auto sources and account selection bypass this path. Cards, dashboard, app-auto verification,
and long-lived serve usage keep their own existing routes.

### Other active `.auto` decision sites

The codebase still contains multiple active `.auto` decision sites:

| Owner | Current behavior |
| --- | --- |
| `ClaudeProviderDescriptor.resolveUsageStrategy(...)` | Compatibility helper builds the app Auto plan: `oauth`, then `cli`, then `web`; if none are available it returns `.auto` for the caller to resolve. |
| `ClaudeUsageFetcher.loadLatestUsage(.auto)` | Chooses `oauth`, then `web`, then `cli`, with final `oauth` fallback. |

The compatibility helper does not represent the runtime-specific provider pipeline above. The separate direct-fetcher
order remains intentionally recorded here. RAT-107 directly characterizes the active direct-fetcher branches it can
reach cleanly in tests and records the remaining current-state behavior without reconciling it.

## Prompt and cooldown baseline

Current behavior that later refactor work must preserve:

- The default Claude keychain prompt mode is `onlyOnUserAction`.
- Prompt policy is only applicable when the Claude OAuth read strategy is `securityFramework`.
- User-initiated interaction clears a prior Claude keychain cooldown denial before retrying availability or repair.
- Launch and background refresh never show Claude OAuth Keychain prompts, including `always` mode.
- Promptable Claude CLI keychain reads are limited to explicit user actions such as menu/manual/provider actions.
- Background delegated refresh is blocked when prompt policy is `onlyOnUserAction` and the caller did not explicitly
  allow background delegated refresh.
- Prompt mode `never` blocks delegated refresh attempts.
- Expired credential owner behavior remains owner-specific:
  - `.claudeCLI`: delegated refresh path,
  - `.codexbar`: direct refresh path,
  - `.environment`: no auto-refresh.

## Token-account routing baseline

Accepted Claude token-account input shapes today:

- raw OAuth access token with `sk-ant-oat...` prefix,
- `Bearer sk-ant-oat...` input,
- raw session key,
- full cookie header.

Current routing rules:

- OAuth-token-shaped inputs are not treated as cookies.
- Cookie/header-shaped inputs are any value that already contains `Cookie:` or `=`.
- App-side Claude snapshot behavior:
  - OAuth token account keeps the usage source setting as-is, disables cookie mode (`.off`), clears the manual cookie
    header, and relies on environment-token injection.
  - Session-key or cookie-header account keeps the usage source setting as-is, forces manual cookie mode, and
    normalizes raw session keys into `sessionKey=<value>`.
- CLI-side Claude token-account behavior:
  - OAuth token account changes the effective source mode from `auto` to `oauth`, disables cookie mode, omits a
    manual cookie header, and injects `CODEXBAR_CLAUDE_OAUTH_TOKEN`.
  - Session-key or cookie-header account stays in cookie/manual mode.

## Siloing and web-enrichment baseline

Claude Web enrichment is usage-extra-only when the primary source is OAuth or CLI:

- Web extras may add optional rate windows and may populate `providerCost` when it is missing.
- A matching prepaid balance may enrich an existing `providerCost` without replacing its spend/limit values.
- OAuth enrichment calls `GET /api/oauth/profile`; Web data is merged only when the email or organization UUID
  matches the primary Claude account.
- Web extras must not replace `accountEmail`, `accountOrganization`, or `loginMethod` from the primary source.
- Snapshot identity remains provider-scoped to Claude.

This behavior is implemented in `Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift`
inside `applyWebExtrasIfNeeded`.

## Documentation contract

- [docs/claude.md](../claude.md) is the summary doc for contributors who want an overview.
- This file is the exact current-state baseline for contributor and refactor parity work.
- [claude-provider-vnext-locked.md](claude-provider-vnext-locked.md)
  is the future refactor plan and should cite this file for present behavior.

## Characterization coverage

Stable automated coverage for this baseline lives in:

- `Tests/CodexBarTests/ClaudeBaselineCharacterizationTests.swift`
- `Tests/CodexBarTests/ClaudeOAuthFetchStrategyAvailabilityTests.swift`
- `Tests/CodexBarTests/ClaudeUsageTests.swift`
- `Tests/CodexBarTests/TokenAccountEnvironmentPrecedenceTests.swift`
- `Tests/CodexBarTests/SettingsStoreCoverageTests.swift`

`ClaudeUsageTests.swift` now directly characterizes the reachable `ClaudeUsageFetcher(.auto)` branches for:

- OAuth when OAuth, Web, and CLI all appear available,
- Web before CLI when OAuth is unavailable,

The successful CLI-selected branch and the CLI-failure-to-OAuth fallback remain documented from code inspection plus
surrounding Claude probe/regression coverage, because the current CLI-availability decision is sourced from process-wide
binary discovery with no stable test seam that would keep RAT-107 in scope.
