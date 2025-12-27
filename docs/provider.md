---
summary: "Provider authoring guide: shared host APIs, provider boundaries, and how to add a new provider."
read_when:
  - Adding a new provider (usage + status + identity)
  - Refactoring provider architecture or shared host APIs
  - Reviewing provider boundaries (no identity leakage)
---

# Provider authoring guide

Goal: adding a provider should feel like:
- add one folder
- implement one fetcher
- register one descriptor
- done (tests + docs)

This doc is both:
- **how it works today** (CodexBar 2025-12)
- **target shape** (what we should refactor towards)

## Terms
- **Provider**: a source of usage/quota/status data (Codex, Claude, Gemini, Antigravity, Cursor, …).
- **Host APIs**: shared capabilities we provide to providers (Keychain, browser cookies, PTY, HTTP, WebView scrape, token-cost).
- **Identity fields**: email/org/plan/loginMethod. Must stay **siloed per provider**.

## Current architecture (today)
- `Sources/CodexBarCore`: probes + fetchers + parsing + shared utilities.
- `Sources/CodexBar`: registry + settings + UI.
- Provider IDs are compile-time: `UsageProvider` enum.
- Provider wiring:
  - metadata: `ProviderDefaults.metadata`
  - fetching: `ProviderRegistry.specs(...)` → `ProviderSpec.fetch` producing `UsageSnapshot`

Common building blocks already exist:
- PTY: `TTYCommandRunner`
- subprocess: `SubprocessRunner`
- cookie import: `BrowserCookieImporter` (Safari/Chrome/Firefox adapters)
- OpenAI dashboard web scrape: `OpenAIDashboardFetcher` (WKWebView + JS)
- token cost: `CCUsageFetcher`

Pain today:
- adding a provider requires touching many `switch provider` sites (UI + icon + settings + menu actions).
- shared primitives exist, but not presented as a clear “host API surface”.

## Target architecture (what we should refactor towards)

### 1) “Provider descriptor” is the source of truth
Introduce a single descriptor per provider:
- `id` (stable string or enum wrapper)
- display/labels/URLs
- capabilities (supportsCredits, supportsStatusPolling, supportsTokenCost, supportsWebLogin, etc.)
- status strategy (Statuspage vs Workspace product feed vs link-only)
- icon/branding metadata

UI and settings should become descriptor-driven:
- no provider-specific branching for labels/links/toggle titles
- minimal provider-specific UI (only when a provider truly needs bespoke UX)

### 2) Host APIs are explicit, small, testable
Expose a narrow set of protocols/structs that provider implementations can use:
- `KeychainAPI`: read-only, allowlisted service/account pairs
- `BrowserCookieAPI`: import cookies by domain list; returns cookie header + diagnostics
- `PTYAPI`: run CLI interactions with timeouts + “send on substring” + stop rules
- `HTTPAPI`: URLSession wrapper with domain allowlist + standard headers + tracing
- `WebViewScrapeAPI`: WKWebView lease + `evaluateJavaScript` + snapshot dumping
- `TokenCostAPI`: `ccusage` integration (Codex/Claude today; extend later)
- `StatusAPI`: status polling helpers (Statuspage + Workspace incidents)
- `LoggerAPI`: scoped logger + redaction helpers

Rule: providers do not talk to `FileManager`, `Security`, or “browser internals” directly unless they *are* the host API implementation.

### 3) Provider-specific code lives in one place
Organize provider code by folder, so it’s obvious what is “provider” vs “host”:
- `Sources/CodexBarCore/Host/*` (shared host APIs + implementations)
- `Sources/CodexBarCore/Providers/<ProviderID>/*` (provider-specific probes/parsers/models)
- `Sources/CodexBar/Providers/*` (provider-specific UI bits only; prefer generic UI)

## Guardrails (non-negotiable)
- Identity silo: never display identity/plan fields from provider A inside provider B UI.
- Privacy: default to on-device parsing; browser cookies are opt-in and never persisted by us beyond WebKit stores.
- Reliability: providers must be timeout-bounded; no unbounded waits on network/PTY/UI.
- Degradation: prefer cached data over flapping; show clear errors when stale.

## Adding a new provider (today)

Checklist:
- Add `UsageProvider` case in `Sources/CodexBarCore/Providers/Providers.swift`.
- Add `ProviderMetadata` entry in `ProviderDefaults.metadata` (app-side defaults/labels).
- Implement probe/fetcher in `Sources/CodexBarCore/Providers/<ProviderID>/` returning `UsageSnapshot`.
  - Prefer a small `*Probe` struct with `fetch() async throws -> <Snapshot>`.
  - Add `<Snapshot>.toUsageSnapshot()` mapping.
- Add app implementation in `Sources/CodexBar/Providers/<ProviderID>/` conforming to `ProviderImplementation`.
- Register it in `Sources/CodexBar/Providers/Shared/ProviderCatalog.swift`.
- Optional: expose shared settings toggles via `ProviderImplementation.settingsToggles(context:)` (no custom views).
- UI touchpoints should be rare now: icon style + login flow + any truly unique UX.
- Status: add status URL/product ID in metadata; `UsageStore.refreshStatus` uses this.
- Tests: add or extend tests in `Tests/CodexBarTests` for parsing + registry/metadata.
- Docs: update `docs/provider.md` with auth story + quirks.

## Adding a new provider (target shape)
(Once refactor lands.)
- Create `Sources/CodexBarCore/Providers/<id>/`:
  - `<id>Provider.swift` (descriptor)
  - `<id>Probe.swift` / `<id>Fetcher.swift`
  - `<id>Models.swift` (snapshot types)
  - `<id>Parser.swift` (if text/HTML parsing)
- Implement `ProviderImplementation` using injected Host APIs (no direct Keychain/cookie/WKWebView calls).
- Register descriptor in a single `ProviderCatalog` list.
- UI + settings auto-populate from the catalog; no additional switches.
- Add tests for:
  - snapshot mapping → `UsageSnapshot`
  - error mapping / timeout behavior
  - identity silo (provider can’t write into other provider state)

## UI notes (Providers settings)
Current: checkboxes per provider.

Preferred direction: table/list rows (like a “sessions” table):
- Provider (name + short auth hint)
- Enabled toggle
- Status (ok/stale/error + last updated)
- Auth source (CLI / cookies / web / oauth) when applicable
- Actions (Login / Diagnose / Copy debug log)

This keeps the pane scannable once we have >5 providers.
