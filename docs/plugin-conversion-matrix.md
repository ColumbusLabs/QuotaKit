---
summary: "All-provider conversion matrix for the bundled JavaScriptCore prototype capability set."
read_when:
  - Choosing another provider to convert to JavaScript
  - Planning the next plugin host capability
---

# Provider plugin conversion matrix

This matrix evaluates all 67 providers in the 2026-08-02 capability audit against the prototype documented in
[`plugin-prototype.md`](plugin-prototype.md). The current checkout has 66 `UsageProvider` cases; Notion is retained here
because it is the 67th audited provider explicitly requested by this work order. Each provider has one primary blocker.

`convertible-now` means the canonical first-party flow is GET-only, uses a fixed HTTPS origin and header secret, and fits
the generic snapshot. Optional canonical-origin endpoint overrides do not change that bucket; user-selected origins
require a provider-specific endpoint policy and are assessed in their matrix rows. The convertible rows were checked
against the current Swift request methods and snapshot projections; Azure OpenAI, StepFun, and Warp were removed from the audit's
earlier “fully expressible” baseline because their current implementations issue POST requests.

`converted` means the bundled JavaScript conversion is present behind `CODEXBAR_JS_PROVIDERS=1`. `cut-over` means the
bundled script is the only JavaScriptCore implementation, with any retained native core serving Linux only. The Converted column
makes implementation state explicit and the totals are mutually exclusive: `convertible-now` counts only providers
that remain cheap to convert. Remaining buckets name the next blocker after this host-extension slice.

## Totals

| Status | Count |
|---|---:|
| `cut-over` | 9 |
| `converted` | 9 |
| `convertible-now` | 6 |
| `needs-cookie-import` | 19 |
| `needs-files/subprocess/oauth-broker` | 15 |
| `needs-pty/webview/native` | 9 |
| **Total** | **67** |

## Matrix

| Provider | Status | Converted | Reason |
|---|---|:---:|---|
| codex | `needs-pty/webview/native` | No | PTY CLI, OAuth files/refresh, browser cookies, WKWebView scraping, local logs, and reset-credit details exceed this host. |
| openai | `converted` | Yes | Converted: fixed-origin bearer GET pagination with daily spend, model, line-item, and token details. |
| azureopenai | `needs-pty/webview/native` | No | The current quota probe is a POST chat completion against a user-configured deployment origin. |
| claude | `needs-files/subprocess/oauth-broker` | No | Full parity needs credential files/Keychain, OAuth refresh, CLI/PTY, cookies, local logs, and admin details. |
| clinepass | `convertible-now` | No | Verified fixed-origin bearer GET; limits and identity map to generic windows. |
| cursor | `needs-cookie-import` | No | Browser cookies/app database provide auth, and integer request history also has bespoke detail. |
| opencode | `needs-cookie-import` | No | Skipped: React server-function response parsing needs a protocol-specific text decoder beyond `matchFirst`. |
| opencodego | `needs-files/subprocess/oauth-broker` | No | Local auth/SQLite state and browser sessions are required, with an additional bespoke usage model. |
| alibaba | `needs-host-extension` | No | Console auth still requires form-encoded POST and CSRF/sec-token discovery; the host only sends JSON POST. |
| alibabatokenplan | `needs-host-extension` | No | Console requests require form-encoded POST and redirect-aware cookie forwarding, which domain-scoped headers do not supply. |
| qwencloud | `needs-host-extension` | No | CSRF plus form-encoded POST and redirect-aware routing remain outside the JSON-only POST broker. |
| factory | `needs-files/subprocess/oauth-broker` | No | The canonical fallback recovers WorkOS tokens from browser localStorage and persists sessions; cookie headers cover only part of auth. |
| gemini | `needs-files/subprocess/oauth-broker` | No | Gemini CLI credential/config files, Google OAuth refresh, and a curl fallback own the current flow. |
| antigravity | `needs-pty/webview/native` | No | Process/port discovery, localhost IDE RPC, OAuth files, and a persistent PTY make this a native integration. |
| copilot | `needs-files/subprocess/oauth-broker` | No | Full parity includes stored token discovery and interactive device authorization with form-encoded POST; billing cookies alone are insufficient. |
| devin | `needs-files/subprocess/oauth-broker` | No | Full auth discovery reads Chromium localStorage and organization state; manual bearer alone is partial. |
| zai | `converted` | Yes | Converted: both fixed regional origins, personal/team settings, quota lanes, model totals, and hourly/daily token charts. |
| minimax | `needs-cookie-import` | No | Browser cookies/storage and group discovery feed a large service/billing/history-specific payload. |
| manus | `converted` | Yes | Converted: declared-domain cookie import, session-token extraction, JSON POST, and generic credit windows. |
| kimi | `needs-files/subprocess/oauth-broker` | No | Credential/device files and desktop token discovery remain native; domain cookies cover only the web account path. |
| kilo | `needs-files/subprocess/oauth-broker` | No | The default source reads Kilo's local auth file and organization metadata. |
| kiro | `needs-pty/webview/native` | No | Usage exists only through bounded CLI pipe/PTY automation and a bespoke credit/overage model. |
| vertexai | `needs-files/subprocess/oauth-broker` | No | ADC/gcloud files, OAuth refresh, optional subprocess fallback, and local cost logs are required. |
| augment | `needs-files/subprocess/oauth-broker` | No | The preferred strategy spawns `auggie`; the alternative imports browser cookies and maintains sessions. |
| jetbrains | `needs-pty/webview/native` | No | There is no HTTP strategy; native IDE discovery and local XML parsing are the provider. |
| moonshot | `convertible-now` | No | Verified bearer GET against two fixed regional origins; balances project into generic windows. |
| amp | `needs-files/subprocess/oauth-broker` | No | CLI subprocess and browser-cookie strategies plus workspace credit details are outside this host. |
| t3chat | `converted` | Yes | Converted: declared-domain cookie import, JSONL text parsing, and generic base/overage windows. |
| ollama | `needs-cookie-import` | No | Skipped: hosted parity requires HTML bootstrap/state extraction plus API-key fallback arbitration. |
| synthetic | `converted` | Yes | Converted: fixed-origin bearer GET with generic windows, cost, dates, and identity. |
| warp | `needs-pty/webview/native` | No | Warp sends a POST GraphQL operation, which the GET-only HTTP broker cannot express. |
| openrouter | `cut-over` | Yes | Cut over on JavaScriptCore: endpoint and client-header overrides plus one-second best-effort key enrichment match native behavior; the native fetch core is Linux-only. |
| elevenlabs | `convertible-now` | No | Verified `xi-api-key` GET; heterogeneous character/minute quotas map to named generic windows. |
| windsurf | `needs-files/subprocess/oauth-broker` | No | Chromium localStorage, IDE databases, and binary protobuf decoding supply the current session. |
| zed | `needs-files/subprocess/oauth-broker` | No | Zed server settings and a named Keychain credential must be read locally. |
| perplexity | `converted` | Yes | Converted: declared-domain cookie import and generic recurring, bonus, and purchased credit windows. |
| mimo | `needs-files/subprocess/oauth-broker` | No | The canonical pipeline includes the file-based local usage fallback as well as browser sessions; cookies alone cannot preserve it. |
| doubao | `needs-files/subprocess/oauth-broker` | No | Full parity needs a CLI subprocess or Volcengine HMAC signing and POST-based plan calls. |
| sakana | `convertible-now` | No | Manual cookie credentials already enter through the core descriptor; two fixed-origin HTML GETs and generic quota/PAYG detail projection fit the host. |
| abacus | `needs-host-extension` | No | Billing duration subtracts one Calendar.current month; the host exposes daily resets but no calendar/month subtraction with timezone parity. |
| mistral | `needs-cookie-import` | No | CSRF extraction and dependent GETs fit scripts, but auth rejection iterates alternate browser profiles and preserves session selection. |
| deepseek | `needs-files/subprocess/oauth-broker` | No | Platform auth/profile selection reads Chromium localStorage, and the result has a bespoke history model. |
| deepinfra | `cut-over` | Yes | Both engines use fixed-origin bearer GETs for required billing data, preserving cents conversion, balance deductions, suspension, spending limits, and bounded retries. The native fetcher and parser are deleted. |
| codebuff | `needs-files/subprocess/oauth-broker` | No | Full credential parity reads a local Manicode credential file; environment-key mode is partial. |
| crof | `cut-over` | Yes | Cut over on JavaScriptCore: fixed-origin bearer GET with exact credit formatting and America/Chicago daily reset; native fetch code is Linux-only. |
| venice | `cut-over` | Yes | Cut over on JavaScriptCore: fixed-origin bearer GET with DIEM/USD allocation projection; native fetch code is Linux-only. |
| commandcode | `needs-host-extension` | No | Optional subscription enrichment races a two-second grace after required credits finish; per-request timeouts cannot preserve that join boundary. |
| qoder | `converted` | Yes | Converted: declared global/China cookie domains, browser headers, and merged generic quota window. |
| stepfun | `needs-files/subprocess/oauth-broker` | No | Device registration, password login, refresh, quota, and plan operations are POST-based token-broker work. |
| bedrock | `needs-files/subprocess/oauth-broker` | No | AWS profiles/CLI credentials, SigV4 signing, pagination, and two services need host-owned credential/signing APIs. |
| grok | `needs-pty/webview/native` | No | Persistent stdio JSON-RPC, auth/session files, cookies, logs, and binary gRPC-web are strongly native. |
| groq | `needs-cookie-import` | No | Skipped: Stytch session exchange and console history remain a multi-step auth flow. |
| llmproxy | `needs-pty/webview/native` | No | Its origin is user-selected and may be private HTTP, conflicting with the manifest's fixed HTTPS origins. |
| litellm | `cut-over` | Yes | Bundled on both plugin engines with configured HTTPS/private-network HTTP origins, key-bound user/team budgets, and self-scoped spend-only fallback. |
| deepgram | `cut-over` | Yes | Cut over on JavaScriptCore: project discovery, aggregation, configured origins, numeric validation, and classified auth/permission/rate/network/API/parse failures match native behavior; the native fetch core is Linux-only. |
| poe | `converted` | Yes | Converted: fixed-origin bearer GET balance/history pagination with daily points and model/type summaries. |
| chutes | `cut-over` | Yes | Bundled plugin owns subscription usage and optional quota detail requests. |
| neuralwatt | `convertible-now` | No | Verified canonical bearer GET; quota lanes and prepaid cost/energy project generically. |
| clawrouter | `cut-over` | Yes | Cut over on JavaScriptCore: validated configured origins, classified failures, exact confidence, budget/ledger details, and provider charts match native behavior; the native fetch core is Linux-only. |
| longcat | `needs-cookie-import` | No | Still needs path/domain-aware cookie selection and retries across imported profiles; per-domain cache isolation does not expose those candidates. |
| sub2api | `cut-over` | Yes | Cut over on JavaScriptCore: configured HTTPS/loopback origins, a hard 15-second request deadline, strict parsing, exact confidence, and classified failures match native behavior; the native fetch core is Linux-only. |
| wayfinder | `needs-pty/webview/native` | No | The local unauthenticated HTTP gateway, metrics text, and routing/savings model violate HTTPS-only generic scope. |
| zenmux | `convertible-now` | No | Verified fixed-origin bearer GET pair; subscription and optional PAYG balance map generically. |
| aiand | `cut-over` | Yes | Verified fixed-origin bearer GET pagination; 30-day spend maps to generic cost. |
| zoommate | `needs-cookie-import` | No | Skipped: cookie-to-JWT exchange plus paginated history requires provider-specific retry state. |
| xai | `converted` | Yes | Converted: bearer GET balance plus best-effort JSON POST history and billing details. |
| notion | `needs-cookie-import` | No | Workspace selection and AI allowance calls require imported Notion cookies and forwarded session headers. |
