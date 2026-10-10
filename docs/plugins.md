---
summary: "Authoring, installing, approving, and operating local JavaScript and TypeScript provider plugins."
read_when:
  - Writing a QuotaKit provider plugin
  - Installing or reviewing a local provider plugin
  - Debugging plugin approval, TypeScript, settings, or network behavior
---

# Local provider plugins

QuotaKit can load one local JavaScript or TypeScript file as a provider. Put a `.js` or `.ts` file in
`~/.config/quotakit/providers/`, or choose **Settings → Plugins → Install…**. Each file declares its complete authority
and settings schema in a manifest, fetches through QuotaKit's sandboxed host API, and returns a generic usage snapshot.

Plugins are local files only. QuotaKit has no plugin catalog, does not download plugin code or assets, and does not
resolve imports. A plugin cannot use Node, browser globals, subprocesses, local files, databases, OAuth, WebViews, or
arbitrary native APIs. The maximum source size is 1 MiB.

App refreshes are scoped to the installed plugin runtime and its fetch settings. Disabling, removing, reloading, or
reconfiguring a plugin prevents an older refresh from publishing usage or errors. A replacement refresh waits for retired
work to finish and reads the current configuration when its fetch starts. Display-only preferences do not invalidate usage.

## Bundled API-key provider registration

For a bundled plugin with a simple API-key configuration, declare a public `PluginProviderSpec` named `spec` in its
provider-owned `*ProviderDescriptor.swift` file, then expose `descriptor = Self.spec.makeDescriptor()`. The spec owns
metadata, branding, environment-key aliases, the API-key field, and optional presentation and script-settings overrides;
the bundled script still owns requests and parsing. See `XKiroProviderDescriptor` for a minimal example and
`ZenMuxProviderDescriptor` for optional usage settings. Optional dashboards, subscription links, plan labels,
widget colors, and progress colors retain their provider-owned values. `V0ProviderDescriptor` demonstrates a
workspace field shared by config projection, plugin settings, and the app's Scope field.

`Endpoint` shares the `enterpriseHost` projection, environment key, Base URL field, and validated URL resolver.
Its requirement distinguishes a configured override (including invalid values that must reach fetch validation),
a validated override, and an optional override with a declared default. URL normalization and validation remain in
the provider-owned reader. Deepgram's environment-only API URL override stays separate from its Project ID field;
it does not gain an `enterpriseHost` setting.

Typed Boolean toggles share config reads/writes, environment projection, app bindings, and an optional enabled
fetch timeout; LiteLLM uses this for model activity. Only llmman opts out of requiring an API key for fetching.
The pre-migration `plugin-provider-specs.json` golden covers settings, registration, CLI help, branding, credential
projections, token-account metadata, and availability. Extend it before migrating another provider.

Run `Scripts/regenerate-provider-manifests.sh` after wiring the provider. A spec with an `apiKeyField` and no separate
app implementation registers `PluginAPIKeyProviderImplementation(spec: ...)` in the existing provider order. Preserve
the provider's availability and detail-line policies explicitly. Providers with extra fields or token-account behavior
can share the descriptor builder while retaining their app implementation, as GitKraken and DeepInfra do. Keep native
credential discovery and cookie/session handling outside this API-key-only building block.

Ollama's API-key strategy runs the bundled `ollama-api.ts` plugin on both engines. A fixed-origin bearer GET reads the
included allowance, reset, and purchased balance into the existing Monthly and Credits presentation; cookie import
and HTML parsing remain native. The public legacy catalog fetcher remains available for `CodexBarCore` API
compatibility but is no longer used by provider refreshes.

## Minimal plugin

[Cosmic AI](cosmic.md), [Aerostack](aerostack.md), [Sail Research](sailresearch.md), and [Sofya](sofya.md) use the
shared API-key provider spec and fixed-origin GET requests in both plugin engines. Cosmic also declares its Project ID
through the spec's workspace field. Their scripts preserve provider account scope, distinct credit pools, and reported
periods; missing quotas and reset dates remain unavailable.

```js
defineProvider({
  id: "acme-usage",
  name: "Acme Usage",
  icon: { monogram: "AC", tint: "#336699" },
  endpoints: ["https://api.example.com"],
  auth: { type: "bearer", secret: "API_KEY" },
  settings: [
    { key: "API_KEY", title: "API key", subtitle: "Create one in Acme settings.", type: "secure" },
  ],
  async fetchUsage(ctx) {
    const response = await ctx.http.getJSON("https://api.example.com/v1/usage");
    return {
      primary: {
        usedPercent: response.json.used_percent,
        resetsAt: response.json.resets_at,
        windowMinutes: 300,
      },
      details: [{
        title: "Usage",
        rows: [{ label: "Requests", value: String(response.json.requests) }],
      }],
    };
  },
});
```

## Manifest reference

`defineProvider` must be called exactly once with an object containing:

- `id`: 1–64 lowercase ASCII letters, digits, or hyphens. It must not match a built-in provider or another installed
  plugin.
- `name`: trimmed display name, 1–80 UTF-8 bytes.
- `icon` (optional): `{monogram, tint}`. `monogram` is 1–3 characters; `tint` is `#RRGGBB`. The fallback is the first
  letter of `name` with a neutral tint. File/SVG icons are not supported.
- `topLevel` (optional): set to `true` to give an enabled plugin its own provider-switcher tab. The default is `false`.
- `endpoints`: 1–16 declared network origins. A fixed endpoint is a normalized HTTPS origin such as
  `https://api.example.com` (no path, query, fragment, or user info). A settings-derived endpoint is
  `{setting: "BASE_URL", policy: "https"}`, `"https-or-loopback-http"`, or
  `"https-or-private-network-http"`. Its setting must be declared as `plain`. The private-network policy permits
  authenticated HTTP only to a validated private origin after exact-origin typed approval.
- `auth` (optional): one of the forms below. The named secret must be a declared `secure` setting.
- `settings`: up to 32 setting definitions. Keys contain 1–64 ASCII letters, digits, or underscores and start with a
  letter. Each entry has `key`, `title`, optional `subtitle`, and `type: "plain" | "secure"` (default `secure`).
- `capabilities` (optional): `"browser-cookies"`, `"http-status"`, and `"persistent-storage"`.
- `http-status`: lets the plugin inspect received HTTP response status codes and bodies, including non-2xx responses.
  The plugin must classify those responses itself; this does not expand approved network origins or bypass host
  timeouts and response-size limits.
- `persistent-storage`: grants bounded, non-secret state scoped to this plugin instance. Adding or removing this
  capability changes the approval binding.
- `cookieDomains`: required with `browser-cookies`; a non-empty list of normalized DNS host names.
- `cookiePolicy` (bundled plugins only): `{selection: "request-url", cache: "nonpersistent"}` opts into host-owned,
  URL-matched cookie records without persistent cookie storage. It may also declare `imports`, `requiredCookies`, and
  a host-owned `headerEcho`; these cannot be enabled by user-installed plugins. `imports` defaults to
  `"app-interactive"`; `"access-gated"` lets the host browser access gate govern the import attempt.
- During an explicit app refresh, the host may allow one bounded retry for one browser whose cookie access was blocked.
  The retry context follows the importer across plugin engines. Scheduled refreshes remain noninteractive and never
  gain permission to show a Keychain prompt. If cookie permission blocks available sessions and the provider then
  reports missing or expired authentication, QuotaKit surfaces a permission error with explicit-refresh and Manual
  source guidance; unrelated provider errors keep their original classification.
- For `cache: "nonpersistent"`, a successfully validated refresh counts as success without a persistent cookie-cache write.
- `fetchUsage(ctx)`: function returning a snapshot or fetch result envelope, or a promise for one.

First-party plugins with the `browser-cookies` capability may call
`ctx.browser.rejectCookie(domain)` after the declared host rejects an imported browser session. QuotaKit clears only the
automatic cookie cache entry that produced that request; it leaves manually entered headers and any newer replacement
session intact. The domain must match the plugin's declared `cookieDomains` list.

### Bundled cookie header echo

A bundled cookie policy can declare one `headerEcho` with an origin, one required cookie name, and a custom `X-` header.
The origin must be a declared fixed HTTPS endpoint and cookie domain. The host derives the header from the same opaque
session and URL-matched records used for `Cookie`; scripts never receive the cookie value. Missing, empty, duplicate,
expired, or path-mismatched cookies fail closed, and scripts cannot set or replace the echo header. Same-origin HTTPS
redirects reselect both cookie headers for the redirected URL. Other origins and ports cannot carry the echo.

[X API](xapi.md) uses this host-owned `ct0` echo for account discovery and developer-console credits. Its script receives
neither cookie values nor permission to request another origin; its synced result contains the prepaid balance and
safe provider detail rows, without quota history or a rate window.

Authentication forms:

```js
auth: { type: "bearer", secret: "API_KEY" }
auth: { type: "x-api-key", secret: "API_KEY" }
auth: { type: "header", header: "X-Custom-Key", secret: "API_KEY" }
auth: { type: "authorization-scheme", scheme: "Token", secret: "API_KEY" }
```

The host owns the authentication header; plugin request options cannot override it. Authenticated public origins use
HTTPS; authenticated private-network HTTP requires the endpoint policy and typed origin approval above. Secure settings
can be overridden for CLI use with
`QUOTAKIT_PLUGIN_<PLUGIN_ID>_<SETTING_KEY>`, uppercased with non-alphanumeric characters replaced by underscores. For
example, `acme-usage` and `API_KEY` use `QUOTAKIT_PLUGIN_ACME_USAGE_API_KEY`.

## `ctx` API

`ctx` exists only during `fetchUsage`. QuotaKit uses QuickJS-NG 0.17.0 and JavaScriptCore on Apple platforms; both
provide ECMAScript built-ins but no browser or Node environment. `Intl` is engine-dependent and unavailable in QuickJS,
so portable third-party plugins must use the host helpers below instead of ECMA-402. `fetch`, `XMLHttpRequest`, timers,
`require`, `process`, and filesystem APIs are unavailable.

- `await ctx.http.getJSON(url, opts?)` performs GET and returns `{status, headers, json}`.
- `await ctx.http.get(url, opts?)` performs GET and returns `{status, headers, bodyText}`.
- `await ctx.http.getWithOptional(url, optional, opts?)` runs a required GET beside an optional GET or POST. The optional response may be discarded after a bounded collection budget; its request has no retries and a five-second limit.
- Without `http-status`, the host rejects non-2xx responses before returning them. Declaring this capability allows the
  plugin to inspect their status and body; it does not add retries or alter origin/authentication checks.
- `await ctx.http.postJSON(url, {body, headers?})` performs JSON POST. `body` must be JSON-serializable.
- `await ctx.http.post(url, {body, headers?})` sends the same JSON POST and returns `{status, headers, bodyText}` so a
  plugin can classify non-JSON error pages before parsing a successful response.
- `await ctx.http.post(url, {form: {key: "value"}, headers?})` sends `application/x-www-form-urlencoded` data and
  returns the text response, including its final `url`. The host encodes a string-to-string map; raw form strings,
  non-string values, and combining `form` with `body` are rejected. Form requests use the same declared-origin,
  authentication, deadline, response-size, and retry rules as JSON POST. Form values, their percent-encoded values,
  and their JSON-escaped values join the fetch's log/error redaction set before transport starts. Do not log
  credentials before submitting the request; values discovered by the script are not known to the host yet.
- `opts.headers` accepts string values. Plugins cannot replace their declared auth header. `opts.timeoutSeconds` sets a
  hard request deadline from 1 through 90 seconds; the default is 15 seconds. Each attempt’s deadline starts when
  its transport task begins, so scheduler delays do not consume the request budget. Queued work remains bounded
  by the overall fetch deadline and cancellation. An override does not extend that overall deadline; bundled
  strategies that need a longer request must also supply a sufficient fetch budget.
- `opts.retryPolicy: "transientIdempotent"` opts GET into the native single-retry policy: 408, 429, 500, 502, 503, 504,
  timeout, lost connection, connection failure, and DNS failures. The delay is one second or numeric `Retry-After`,
  capped at ten seconds. POST, offline, TLS, and cancellation failures are not retried. This replaces the automatic
  status-based fetch replay for that request; explicit `ctx.fail` retry options should not add another retry.
- HTTP rejections are `Error` objects on both engines. Native failures expose `transportCode` (the Foundation URL-error
  code), `transportClass` (`timeout`, `dns`, `offline`, `cancelled`, `tls`, `connection`, or `other`), and `retryable`.
  Rejected HTTP responses expose `status` and class `http`. Plugins can use these fields when choosing a `ctx.fail`
  classification. Rethrow cancellation unchanged; uncaught cancellation remains a Swift `CancellationError`, and
  cancelling the refresh interrupts its pending request and retry delay.
- `ctx.settings.get(key)` reads a declared `plain` setting.
- `ctx.settings.getSecret(key)` reads a declared `secure` setting. Missing values return `null`; kind mismatches and
  undeclared keys throw.
- `ctx.fail` creates classified errors for `authenticationExpired`, `missingCredential`, `permissionDenied`,
  `rateLimited`, `providerUnavailable`, `parseFailure`, `networkFailure`, and `apiFailure`. Throw the returned error,
  for example `throw ctx.fail.rateLimited("Provider rate limit reached")`; ordinary errors retain generic mapping.
  Every plugin automatically gets one delayed retry when a request returns 408, 429, 500, 502, 503, or 504. A numeric
  `Retry-After` header sets the delay; otherwise the delay is 1 second, and the host clamps it to 10 seconds. A plugin
  that needs provider-specific handling—such as a non-numeric `Retry-After`, quota data in the error body, or a vendor
  retry field—declares `http-status`, receives the response, and throws `ctx.fail.rateLimited(message,
  {retryAfterSeconds})` or another transient classified failure. Both paths share one retry budget and never retry the
  retry. Cancellation during the delay stops the retry.
- `ctx.browser.availability(domain)` returns `"available"`, `"manual"`, or `"off"` for a declared cookie domain.
  It inspects source/cookie policy only, without accessing the broker, Keychain, or browser. It does not promise a
  usable session. API-only (and other non-web) source modes report `"off"`; Manual reports `"manual"`, so plugins can
  route an origin-less pasted header to one explicitly selected tenant. Missing cookie resolvers report `"off"`.
  `cookieHeader` also enforces Off/API-only policy, even if the plugin skips this check.
- `ctx.browser.supportedBrowsers` is a comma-separated display list from this provider's configured automatic browser
  sources. It does not inspect installed profiles, search browsers, or access Keychain. When browser import is unavailable,
  the value is `none on this platform`; Manual remains the fallback for other browsers.
- `await ctx.browser.cookieHeader(domain)` returns a cookie header only with the `browser-cookies` capability and for a
  declared domain. User plugins import from Chrome; bundled providers retain their declared browser order.
  Cookie values are secret-equivalent and redacted.
- `for await (const session of ctx.browser.sessions(domain))` visits origin-bound candidates in order: the exclusive
  manual credential, or the cached session followed by browser profiles in the provider's import order. Each candidate
  has `{id, header, source, origin}`. Enumeration is scoped to one declared domain and stops when candidates are exhausted.
  Manual regional captures retain their origin through settings projection; an origin-less legacy header is restricted
  to the selected domain. Qoder's legacy headers select the global site.
  The optional `{cachedOnly: true}` argument yields manual/cached candidates without importing browser profiles;
  cached candidates include `cachedAt` as Unix seconds. This lets a regional provider try its newest cached session
  before importing any fresh cookies, even when that session belongs to its second domain.
- `ctx.browser.rejectCookie(domain, session)` rejects that candidate after an authentication failure. It conditionally
  evicts the matching persistent entry without deleting a newer session or another domain's cache. The opaque candidate
  ID makes late rejections safe. Continuing the iterator visits the next candidate; a successful fetch can return
  immediately. `cookieHeader` remains available for providers needing only one header.
- `ctx.html.metaContent(html, name)` returns the first matching quoted meta value or `null`.
- `ctx.html.matchFirst(html, regexSource, flags?)` returns the first capture/full match or `null`.
- `ctx.log(...values)` writes to the instance-scoped plugin log. Known secrets and cookie values are redacted.
- `ctx.cache.get(key)` and `ctx.cache.set(key, value, ttlSeconds)` provide a per-runtime memory cache. TTL is capped at
  24 hours.
- `ctx.storage.get(key)`, `set(key, value)`, and `remove(key)` provide non-secret strings persisted under
  `~/Library/Application Support/QuotaKit/plugin-storage/` when `persistent-storage` is declared. State is isolated by
  instance ID and deleted with the plugin. Keys are 1–128 UTF-8 bytes; at most 64 entries and 64 KiB total are kept.
- `ctx.date.iso(text)`, `unixSeconds(number)`, and `unixMillis(number)` create JavaScript dates.
- `ctx.date.nextDailyReset(timeZoneIdentifier, hour)` returns the next wall-clock reset in an IANA time zone.
- `ctx.date.addMonths(date, months, timeZoneIdentifier)` adds whole Gregorian calendar months in the chosen time zone, preserving local wall-clock time and clamping month ends.
- `ctx.date.addMonths(date, months, timeZoneIdentifier)` adds an integer number of Gregorian calendar months to a
  valid JavaScript `Date`; use negative months to subtract. Both engines call Foundation Calendar with the specified
  IANA time zone, preserving local wall-clock time across DST and clamping month ends (January 31 plus one month is
  February 28, or February 29 in a leap year). Offsets are limited to ±120,000 months, and invalid dates, time zones,
  fractional offsets, or results outside JavaScript's Date range throw.
- `ctx.env.timeZone` is the host's current IANA time-zone identifier; zero-offset GMT aliases are normalized to `UTC`.
- `ctx.format.currency(value, currencyCode)` matches native QuotaKit currency formatting, including currency-specific
  precision. `number(value, options?)`, `usd(value)`, and `monthDay(date)` also provide deterministic formatting on both
  engines. Number options support `minimumFractionDigits` and `maximumFractionDigits`.
- `ctx.jwt.decode(token)` decodes (but does not authenticate) a JWT JSON payload.
- `ctx.pct(used, limit)` returns a finite percentage clamped to 0–100; non-positive limits map to 100.

User-plugin requests run in an ephemeral session with no ambient cookies, credential store, or URL cache. Redirects are
rejected, the timeout is 15 seconds, `Accept-Encoding: identity` is sent, compressed and non-2xx responses fail, and
response bytes are capped at 1 MiB. Request URLs must match a declared, approved origin.

Bundled first-party providers that have cut over to JavaScript use the shared runtime's 20-second hung-script watchdog.
A timeout fails that refresh and discards the poisoned worker before returning the error, so an immediate retry starts
with a fresh context. Cancellation retires the worker in the same way. This is production-default and does not depend
on `CODEXBAR_JS_PROVIDERS`.
On Linux, QuickJS enforces the watchdog in-engine with `JS_SetInterruptHandler`, caps the runtime heap at 64 MiB, and
caps the JavaScript stack at 2 MiB. The interrupt terminates evaluation on its confined thread; timed-out scripts do not
leave an abandoned evaluation thread behind.

The bundled Abacus AI plugin uses required credits GET and optional billing POST with host-encoded form data. It tries at most five Chrome-first validated sessions within a bounded refresh budget, and uses calendar-month dates for its pacing window.

## Snapshot result

Return at least one rate window, cost object, detail section, or meaningful identity field. When a successful fetch
has no usage to report, return `{ empty: true }` to clear stale plugin data. The `empty` marker must be a boolean;
`empty: false` does not make an otherwise empty result valid.

```js
return {
  primary: { usedPercent: 25, resetsAt: new Date(), windowMinutes: 300 },
  secondary: { usedPercent: 40, resetsAt: "2026-08-10T00:00:00Z", windowMinutes: 10080 },
  tertiary: { usedPercent: 5 },
  extraWindows: [{ id: "daily", title: "Daily", window: { usedPercent: 12 } }],
  cost: { used: 8.5, limit: 20, currency: "USD", period: "This month", balance: 11.5 },
  identity: { email: "user@example.com", organization: "Acme", loginMethod: "API key", accountID: "123" },
  subscriptionRenewsAt: "2026-09-01T00:00:00Z",
  dataConfidence: "exact", // exact | estimated | percentOnly | unknown
  details: [{
    title: "Usage summary",
    rows: [{ label: "Requests", value: "1,240", secondaryValue: "Last 30 days" }],
    chart: {
      kind: "bars", // bars | line
      title: "Daily spend",
      unit: "USD",
      points: [{ label: "2026-08-01", value: 4.25 }],
    },
  }],
};
```

Percentages must be finite and are clamped to 0–100. Window minutes are positive integers. Cost requires finite `used`
and a three-letter uppercase currency. Dates are JavaScript `Date` values or ISO-8601 strings. Snapshot identity is
always scoped to the manifest's instance ID. Data confidence defaults to `unknown`. Details allow at most 8 sections, 24 rows per section, 120 chart points,
and 120 characters per detail string. Wrong types and limit violations fail the whole fetch instead of truncating it.
Named extra windows accept an optional `usageKnown` boolean (default `true`). Set it to `false` for reset-only limits:
the window remains visible as **Unavailable**, and its placeholder `usedPercent` is not presented as measured usage.
Detail rows accept optional `progress` (a finite consumed fraction from 0 through 1) and `usageValue` (finite raw usage).
The host maps the fraction to native progress with `used: progress, total: 1`; `usageValue` is preserved independently.
Absent or null numeric fields leave existing text-only rows unchanged. A supplied `usageKnown` must be a boolean,
including when the window uses the nested `window` form; null is invalid.
An identity-only snapshot is useful for balance-only or zero-usage provider states and renders its available account,
organization, plan/login-method, and account-ID fields in the menu and CLI. A verified response with no displayable data
may return `{empty: true}` with optional identity. This creates no artificial rate window; every supplied field is still
validated. An empty object, an empty `identity` object, or metadata such as confidence and subscription dates without
displayable usage or identity remains invalid unless `empty: true` is explicitly declared.


DeepInfra uses a bundled JavaScript plugin for API key billing.

ZenMux uses the bundled `zenmux.js` plugin for management API usage.

## TypeScript

Chutes uses the bundled `chutes.ts` plugin for subscription usage and optional quota details.

ai& uses a bundled `aiand.ts` plugin for request log spending.

TypeScript files are transpiled with the bundled Sucrase 3.35.1 build using its `typescript` transform. Use ordinary
type syntax but no module imports, JSX, decorators, or runtime TypeScript features that require module resolution.
Transpiled output is cached in `~/Library/Caches/QuotaKit/plugins/` under a filename containing the SHA-256 of the source
and the Sucrase version. An unchanged file is a cache hit; any source or compiler-version change produces a new key.
Transpile failures appear as that plugin's Settings error.

## Install, approve, run, and delete

1. Open **Settings → Plugins** and choose **Install…**, or copy one `.js`/`.ts` file into the providers directory.
2. QuotaKit validates the source and manifest without network, file, cookie, or secret capabilities.
3. The approval sheet lists exact normalized origins, auth mode, capabilities (including persistent storage), secure setting
   names, and cookie domains.
4. For loopback, IP-literal, or `.local` origins, type every normalized origin exactly before approval.
5. Enter manifest settings and enable the plugin. Its refresh result appears in its generic menu card.

QuotaKit serializes replacement refreshes for each plugin. Results from an older request are discarded when the
plugin is disabled, reconfigured, removed, or reloaded; a later refresh reads the current settings when it begins.

Approval records live outside plugin files under `~/Library/Application Support/QuotaKit/plugin-approvals.json`. A
change to instance ID, normalized origins, auth mode/header, secure setting names, capabilities, or cookie domains
invalidates approval before the next request. There is no bulk approval or import path.

Bifrost's bundled plugin uses a configured HTTPS or private-network HTTP gateway. The virtual key is sent only to the validated gateway origin.

`quotakit plugins list` shows locally discovered plugins. `quotakit plugins fetch <id>` displays the same approval
fields and can approve only from an interactive terminal; redirected/headless input fails closed. Browser-cookie plugins
are app-only and fail closed in the CLI.

Every CLI command discovers user plugins before loading config, so `config providers` and `config dump` include
installed plugins. Unrelated app and CLI config writes preserve unavailable plugin records, including settings and
secrets, in their original positions. Missing files, discovery failures, and platforms without the plugin runtime do
not delete saved data. `config providers` labels these entries as `plugin (not loaded)`. Their opaque fields are
redacted in `config dump` unless `--show-secrets` is explicitly requested.
After discovery, entries using an unsupported future config format remain unchanged if an edit would lose data.

Delete from Settings with **Delete…**. QuotaKit removes the plugin file, matching TypeScript cache output, approval,
per-instance settings and secrets, and per-instance usage history. Invalid plugin files are listed with their validation
error and can also be deleted.

## Security and limitations

Treat a plugin like code you run locally, even though its host capabilities are narrow. Read the manifest and source,
verify every origin, and avoid installing files from untrusted repositories. Approval grants the listed origin network
authority; DNS changes after approval are outside QuotaKit's threat model. Secrets are never placed in URLs or logged,
redirects cannot forward authentication, and undeclared settings/cookies/origins fail closed.

Plugins support the macOS app plus the macOS and Linux CLIs. They are excluded from widgets and all built-in-provider-only
surfaces (status feeds, token accounts, OAuth, browser automation, storage probes, local cost scanners, and provider
specific payloads). Rendering is limited to generic snapshots and declarative details. There are no remote catalogs,
downloaded plugins/assets, custom SVGs, imports, arbitrary local I/O, or compatibility fallback from an unknown ID to a
built-in provider.

## Provider switcher tabs

QuotaKit intentionally keeps `topLevel` opt-in. An omitted field preserves the
existing appended-card placement; upgrading the app does not move existing plugin
cards into tabs. This differs from upstream's default-on policy and is a placement
choice, independent of installation, enablement and capability approval.

Set `topLevel: true` in the manifest to give an enabled plugin its own tab when **Merge Icons** is enabled. The tab uses
the manifest name and icon. Selecting it shows that plugin’s usage followed by any enabled plugins using the original
appended-card placement. With Merge Icons disabled, plugins retain appended-card placement.

A single plugin works without a redundant switcher, and multiple plugin tabs work even with no built-in providers
enabled. Refresh and Cmd-R refresh the selected plugin; each card’s refresh button targets that card. Completed
refreshes update visible plugin cards, and repeated requests for the same plugin share its in-flight refresh.
Overview continues to summarize built-in providers. This setting changes placement only: it grants no additional host
capabilities and does not change network approval.

## Selected browser profiles

A bundled plugin can declare `cookiePolicy.store: "selected-profile"` with `selection: "request-url"`,
`cache: "nonpersistent"`, `imports: "access-gated"`, a nonempty `requiredCookies` list, and a `sessionURL` on
its single declared request host. Its `PluginProviderSpec.WebSource` registers a settings section with
`selectedProfileBrowsers`; the shared **Browser** and **Browser profile** pickers persist `browserID` and the
explicit `browserProfileID`. When `browserID` is absent, the first registered browser preserves legacy
configurations without selecting a profile. Unsupported browser IDs fail closed. Changing the browser clears the
profile selection, previous measurements, and pending fetches. Safari requires a concrete cookie file; its
browser-wide placeholder is rejected. There is no default profile, Manual header path, other-profile fallback, or
cookie-cache read/write.

The single-browser `selectedProfileBrowser` initializer and property remain supported for source compatibility
with the previously shipped public `CodexBarCore` API. New registrations use `selectedProfileBrowsers`; the legacy
property returns `nil` for registrations that support multiple browsers.

The host fingerprints the selected browser/profile and the applicable required cookies before fetching. After
success, failure, or cancellation it reads that same profile again under the background no-interaction gate.
Only matching, unambiguous live ownership authorizes publication or transient-error retention. Cookie values and
the digest stay in Swift; neither is exposed to the script, logs, or serialized usage. Preference cookies do not
change ownership. Changes are detected on refresh, not continuously. Unreadable or changed sessions fail closed.
Selected-profile responses omit `Cookie`, `Set-Cookie`, and `Set-Cookie2` headers from the script-facing response;
ordinary headers remain available. Response cookies are neither applied to the browser nor persisted by the host.

Providers without stable account identity can set `history: .unavailable` and `burnDownWidgetSelectable: false`
on the spec. Langdock uses these capabilities and does not backfill missing reset dates from prior sessions.
Providers with both widget capabilities disabled are omitted from widget files. Selected-profile usage is never
exported to iPhone sync, fleet CloudKit account snapshots, or widgets: its ownership can only be verified on the importing device.

## Search and research credit providers

[Tavily](tavily.md) reads account-plan, API-key, and pay-as-you-go credits through its public usage API;
[Linkup](linkup.md) reports its prepaid USD balance. Both use API keys and the shared `PluginProviderSpec`.
[Exa](exa.md) reports selected-key monthly spend through Team Management with a support-enabled service key and API key ID.
[TinyApi](tinyapi.md) reads aggregate available credits through its website session and QuotaKit's shared cookie host.
These providers omit undocumented reset dates, credit-bucket splits, and live request-rate headroom.
