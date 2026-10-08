---
summary: "All-provider conversion matrix for the bundled JavaScriptCore prototype capability set."
read_when:
  - Choosing another provider to convert to JavaScript
  - Planning the next plugin host capability
---

# Provider plugin conversion matrix

This is the historical 67-row capability audit from 2026-08-02, retained as provenance; it is not the current provider
catalog. The current checkout registers 92 `UsageProvider` cases. Notion remains in the audit because it was explicitly
requested by that work order, and Crof remains only as a retired historical row. See [`plugin-prototype.md`](plugin-prototype.md)
for the prototype context.

`convertible-now` means the canonical first-party flow is GET-only, uses a fixed HTTPS origin and header secret, and fits
the generic snapshot. Optional canonical-origin endpoint overrides do not change that bucket; user-selected origins
require a provider-specific endpoint policy and are assessed in their matrix rows. The convertible rows were checked
against the current Swift request methods and snapshot projections; Azure OpenAI, StepFun, and Warp were removed from the audit's
earlier “fully expressible” baseline because their current implementations issue POST requests.

`converted` and `cut-over` describe the audited implementation state, not a guarantee of current provider support.
`cut-over` meant the bundled script was the only JavaScriptCore implementation, with any retained native core serving
Linux only. The Crof row is now marked `retired` and does not represent live support. The totals are mutually exclusive:
`convertible-now` counted providers that remained cheap to convert at audit time; other buckets named the next blocker
after that host-extension slice.

## Totals

Bundled Swift registration uses `PluginProviderSpec` for the ten pilot providers plus Synthetic, Chutes, v0,
ElevenLabs, Neuralwatt, ClawRouter, Aixy, Bifrost, Deepgram, LLM Proxy, LiteLLM, sub2api, and llmman. ClawRouter keeps
its custom app endpoint field. The other twelve additions share app settings builders; provider-owned endpoint
validation and the bundled scripts remain authoritative. This glue migration does not change the conversion
classifications or registry count below.

| Status | Count |
|---|---:|
| `cut-over` | 16 |
| `retired` | 1 |
| `converted` | 4 |
| `convertible-now` | 4 |
| `needs-cookie-import` | 9 |
| `needs-host-extension` | 5 |
| `needs-files/subprocess/oauth-broker` | 19 |
| `needs-pty/webview/native` | 9 |
| **Total** | **67** |

## Matrix

| Provider | Status | Converted | Reason |
|---|---|:---:|---|
| codex | `needs-pty/webview/native` | No | PTY CLI, OAuth files/refresh, browser cookies, WKWebView scraping, local logs, and reset-credit details exceed this host. |
| openai | `cut-over` | Yes | Bundled plugin returns typed daily spend, model, line-item, and token details. |
| azureopenai | `needs-pty/webview/native` | No | The current quota probe is a POST chat completion against a user-configured deployment origin. |
| claude | `needs-files/subprocess/oauth-broker` | No | Full parity needs credential files/Keychain, OAuth refresh, CLI/PTY, cookies, local logs, and admin details. |
| clinepass | `convertible-now` | No | Verified fixed-origin bearer GET; limits and identity map to generic windows. |
| cursor | `needs-cookie-import` | No | Browser cookies/app database provide auth, and integer request history also has bespoke detail. |
| opencode | `needs-cookie-import` | No | Skipped: React server-function response parsing needs a protocol-specific text decoder beyond `matchFirst`. |
| opencodego | `needs-files/subprocess/oauth-broker` | No | Local auth/SQLite state and browser sessions are required, with an additional bespoke usage model. |
| alibaba | `needs-host-extension` | No | Form POST is available in host-caps-3; CSRF/sec-token parsing stays in the script. Cookie-jar lane host-caps-4 owns redirect-scoped cookies and the remaining session parity audit; not yet convertible. |
| alibabatokenplan | `needs-host-extension` | No | Form POST is available in host-caps-3. Cookie-jar lane host-caps-4 must preserve domain/path metadata through redirects and define legacy-header migration before cutover. |
| qwencloud | `needs-host-extension` | No | Form POST is available in host-caps-3. Cookie-jar lane host-caps-4 owns declared-origin redirects, dashboard/API domain/path routing, final-URL proof, and migration of the native paired-header cache; no cutover here. |
| factory | `needs-files/subprocess/oauth-broker` | No | The canonical fallback recovers WorkOS tokens from browser localStorage and persists sessions; cookie headers cover only part of auth. |
| gemini | `needs-files/subprocess/oauth-broker` | No | Gemini CLI credential/config files, Google OAuth refresh, and a curl fallback own the current flow. |
| antigravity | `needs-pty/webview/native` | No | Process/port discovery, localhost IDE RPC, OAuth files, and a persistent PTY make this a native integration. |
| copilot | `needs-files/subprocess/oauth-broker` | No | Full parity includes stored token discovery and interactive device authorization with form-encoded POST; billing cookies alone are insufficient. |
| devin | `needs-files/subprocess/oauth-broker` | No | Full auth discovery reads Chromium localStorage and organization state; manual bearer alone is partial. |
| zai | `converted` | Yes | Converted: both fixed regional origins, personal/team settings, quota lanes, model totals, and hourly/daily token charts. |
| minimax | `needs-cookie-import` | No | Browser cookies/storage and group discovery feed a large service/billing/history-specific payload. |
| manus | `cut-over` | Yes | Bundled plugin iterates browser sessions and retains Manual/Off policy. |
| kimi | `needs-files/subprocess/oauth-broker` | No | Credential/device files and desktop token discovery remain native; domain cookies cover only the web account path. |
| kilo | `needs-files/subprocess/oauth-broker` | No | The default source reads Kilo's local auth file and organization metadata. |
| kiro | `needs-pty/webview/native` | No | Usage exists only through bounded CLI pipe/PTY automation and a bespoke credit/overage model. |
| vertexai | `needs-files/subprocess/oauth-broker` | No | ADC/gcloud files, OAuth refresh, optional subprocess fallback, and local cost logs are required. |
| augment | `needs-files/subprocess/oauth-broker` | No | The preferred strategy spawns `auggie`; the alternative imports browser cookies and maintains sessions. |
| jetbrains | `needs-pty/webview/native` | No | There is no HTTP strategy; native IDE discovery and local XML parsing are the provider. |
| moonshot | `convertible-now` | No | Verified bearer GET against two fixed regional origins; balances project into generic windows. |
| amp | `needs-files/subprocess/oauth-broker` | No | CLI subprocess and browser-cookie strategies plus workspace credit details are outside this host. |
| t3chat | `cut-over` | Yes | Bundled plugin preserves web timeout, captured headers, and JSONL parsing. |
| ollama | `needs-cookie-import` | No | Skipped: hosted parity requires HTML bootstrap/state extraction plus API-key fallback arbitration. |
| synthetic | `converted` | Yes | Converted: fixed-origin bearer GET with generic windows, cost, dates, and identity. |
| warp | `needs-pty/webview/native` | No | Warp sends a POST GraphQL operation, which the GET-only HTTP broker cannot express. |
| openrouter | `cut-over` | Yes | Cut over on JavaScriptCore: endpoint and client-header overrides plus one-second best-effort key enrichment match native behavior; the native fetch core is Linux-only. |
| elevenlabs | `convertible-now` | No | Verified `xi-api-key` GET; heterogeneous character/minute quotas map to named generic windows. |
| windsurf | `needs-files/subprocess/oauth-broker` | No | Chromium localStorage, IDE databases, and binary protobuf decoding supply the current session. |
| zed | `needs-files/subprocess/oauth-broker` | No | Zed server settings and a named Keychain credential must be read locally. |
| perplexity | `cut-over` | Yes | Bundled plugin iterates declared-domain sessions and reports recurring, bonus, and purchased credits. |
| mimo | `needs-files/subprocess/oauth-broker` | No | The canonical pipeline includes the file-based local usage fallback as well as browser sessions; cookies alone cannot preserve it. |
| doubao | `needs-files/subprocess/oauth-broker` | No | Full parity needs a CLI subprocess or Volcengine HMAC signing and POST-based plan calls. |
| sakana | `cut-over` | Yes | Manual cookie credentials already enter through the core descriptor; two fixed-origin HTML GETs and generic quota/PAYG detail projection fit the host. |
| abacus | `cut-over` | Yes | The bundled plugin collects required credits and optional billing with bounded cookie attempts and calendar-month pacing; the native fetcher was removed. |
| mistral | `needs-cookie-import` | No | CSRF extraction and dependent GETs fit scripts, but auth rejection iterates alternate browser profiles and preserves session selection. |
| deepseek | `needs-files/subprocess/oauth-broker` | No | Platform auth/profile selection reads Chromium localStorage, and the result has a bespoke history model. |
| deepinfra | `cut-over` | Yes | Both engines use fixed-origin bearer GETs for required billing data, preserving cents conversion, balance deductions, suspension, spending limits, and bounded retries. The native fetcher and parser are deleted. |
| codebuff | `needs-files/subprocess/oauth-broker` | No | Full credential parity reads a local Manicode credential file; environment-key mode is partial. |
| crof | `retired` | No | Crof was removed from QuotaKit's active provider catalog and runtime; this row remains only as historical audit context. |
| venice | `cut-over` | Yes | Cut over on JavaScriptCore: fixed-origin bearer GET with DIEM/USD allocation projection; native fetch code is Linux-only. |
| commandcode | `needs-host-extension` | No | Optional subscription enrichment races a two-second grace after required credits finish; per-request timeouts cannot preserve that join boundary. |
| qoder | `cut-over` | Yes | Bundled plugin iterates regional sessions and reports merged quotas. |
| stepfun | `needs-files/subprocess/oauth-broker` | No | Device registration, password login, refresh, quota, and plan operations are POST-based token-broker work. |
| bedrock | `needs-files/subprocess/oauth-broker` | No | AWS profiles/CLI credentials, SigV4 signing, pagination, and two services need host-owned credential/signing APIs. |
| grok | `needs-pty/webview/native` | No | Persistent stdio JSON-RPC, auth/session files, cookies, logs, and binary gRPC-web are strongly native. |
| groq | `needs-cookie-import` | No | Skipped: Stytch session exchange and console history remain a multi-step auth flow. |
| llmproxy | `needs-pty/webview/native` | No | Its origin is user-selected and may be private HTTP, conflicting with the manifest's fixed HTTPS origins. |
| litellm | `cut-over` | Yes | Cut over on both engines: configured HTTPS/private-network HTTP, key-bound user/team lookups, budgets, optional user-scoped model activity, spend-only and identity-only snapshots; the native fetch twin is deleted. |
| deepgram | `cut-over` | Yes | Cut over on JavaScriptCore: project discovery, aggregation, configured origins, numeric validation, and classified auth/permission/rate/network/API/parse failures match native behavior; the native fetch core is Linux-only. |
| poe | `converted` | Yes | Converted: fixed-origin bearer GET balance/history pagination with daily points and model/type summaries. |
| chutes | `cut-over` | Yes | Bundled plugin owns subscription usage and optional quota detail requests. |
| neuralwatt | `convertible-now` | No | Verified canonical bearer GET; quota lanes and prepaid cost/energy project generically. |
| clawrouter | `cut-over` | Yes | Cut over on JavaScriptCore: validated configured origins, classified failures, exact confidence, budget/ledger details, and provider charts match native behavior; the native fetch core is Linux-only. |
| longcat | `needs-cookie-import` | No | Still needs path/domain-aware cookie selection and retries across imported profiles; per-domain cache isolation does not expose those candidates. |
| sub2api | `cut-over` | Yes | Cut over on JavaScriptCore: configured HTTPS/loopback origins, a hard 15-second request deadline, strict parsing, exact confidence, and classified failures match native behavior; the native fetch core is Linux-only. |
| wayfinder | `needs-pty/webview/native` | No | The local unauthenticated HTTP gateway, metrics text, and routing/savings model violate HTTPS-only generic scope. |
| zenmux | `cut-over` | Yes | Bundled plugin reports subscription usage and optional PAYG balance. |
| aiand | `cut-over` | Yes | Verified fixed-origin bearer GET pagination; 30-day spend maps to generic cost. |
| zoommate | `needs-cookie-import` | No | Skipped: cookie-to-JWT exchange plus paginated history requires provider-specific retry state. |
| xai | `converted` | Yes | Converted: bearer GET balance plus best-effort JSON POST history and billing details. |
| notion | `needs-cookie-import` | No | Workspace selection and AI allowance calls require imported Notion cookies and forwarded session headers. |

Langdock is a plugin-first addition beyond the historical audit. Its selected Edge profile, live session revalidation, and personal tRPC limits use QuickJS and JavaScriptCore. Session-bound readings remain local and do not enter quota history, iPhone sync, fleet CloudKit, or widgets.

X API is also plugin-first. It uses QuotaKit's existing host-owned cookie and CSRF-header-echo capabilities to fetch
account-scoped prepaid USD credits on both plugin engines. The generic balance and safe detail rows sync to iPhone; no
quota history or burn-down window is inferred.
