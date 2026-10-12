# 068 — QuotaKit Lite for Mac (rate-limit-only spinoff)

- **Status:** `proposed`
- **Date:** 2026-10-12
- **Scope:** A new, separate Mac menu bar app that tracks only rate-limit windows for
  Claude, Codex, and Antigravity, and syncs them to the existing iOS app without iOS changes.

## 1. Problem and goal

The full QuotaKit Mac app is about 340k lines of Swift, covering roughly 100 providers. That breaks down as:

- `Sources/CodexBar` with 125k lines;
- `Sources/CodexBarCore` with 216k lines;
- 88 bundled JS plugins.

Its heaviest work is not rate limits:

- **Cost scanning:** the JSONL ledger, about 18k lines in `Vendored/CostUsage`, plus SQLite.
- **Browser cookie decryption:** SweetCookieKit.
- **A QuickJS plugin engine.**
- **Hidden WKWebView scrapers.**
- **PTY-driven CLI probes, plus a watchdog helper:** these have caused CPU incidents in the past (`docs/perf-energy-issue-139-*`).
- **About 48 timer or sleep sites.**

A user who only wants to know how much of a quota is used and when it resets pays for all of that.

**Goal:** a second Mac app, working name **QuotaKit Lite**, that:

1. Shows the session (5h) and weekly windows for **Claude, Codex, and Antigravity** only.
2. Costs almost nothing at idle, with these targets:

   | Metric | Target |
   | --- | --- |
   | Steady-state footprint | ≤ 25 MB |
   | CPU while idle | 0.0% |
   | Average wakeups | < 1 per minute |
   | Network while the user is not coding | none (one heartbeat every 30 min) |
   | Binary size, excluding Sparkle | ≤ 3 MB |
   | Helper processes | none |
   | Keychain prompts during background work | none, ever |

3. Needs almost no upkeep: no third-party runtime dependencies, about 2k lines of new code, and no upstream-sync burden.
4. **Publishes to the existing iPhone app** through the same CloudKit records the full app writes, so iOS, widgets, and push alerts work unchanged.

**Non-goals:**

- cost or spend, token history, daily charts;
- multiple accounts;
- other providers;
- web or cookie sources;
- a CLI;
- Mac widgets;
- a settings window.

## 2. Key findings that shape the design

### 2.1 Each provider needs about one HTTP call

| Provider | Endpoint | Credentials | Who refreshes the token |
|---|---|---|---|
| Claude | `GET https://api.anthropic.com/api/oauth/usage` (see `ClaudeOAuthUsageFetcher.swift:61-141`) | `claudeAiOauth.accessToken` from `~/.claude/.credentials.json` or Keychain item `Claude Code-credentials` | Claude Code CLI. **Lite must not refresh**, because rotating the refresh token signs the CLI out. |
| Codex | `GET https://chatgpt.com/backend-api/wham/usage` (see `CodexOAuthUsageFetcher.swift:412-456`) | `~/.codex/auth.json` → `tokens.access_token`, `tokens.account_id` (or from the JWT claim) | Codex CLI. **Lite must not refresh**, for the same reason as Claude (see `CodexProviderDescriptor.swift` `nativeRefreshRequired`). |
| Antigravity | `POST https://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary` | `--csrf_token` from the running `language_server` command line; the `agy` CLI server needs no token | Not applicable; the data is local and only available while Antigravity is running. |

**Claude request details:**

- Headers:
  - `Authorization: Bearer <accessToken>`
  - `anthropic-beta: oauth-2025-04-20`
  - `User-Agent: claude-cli/<ver> (external, cli)`
  - query `?cedar_ember=1`
- On 400, retry once without `cedar_ember`.
- On 429, honour `Retry-After`.
- Use from the response:
  - `five_hour` and `seven_day`, each `{utilization, resets_at}`;
  - `seven_day_sonnet` or `seven_day_opus`;
  - `extra_usage`, whose amounts are in cents.
- The token needs the `user:profile` scope. A `claude setup-token` token does **not** work.

**Codex request details:**

- Headers: `Authorization: Bearer`, `ChatGPT-Account-Id`, `Accept: application/json`.
- Response: `rate_limit.primary_window` and `rate_limit.secondary_window`, each `{used_percent, reset_at (epoch s), limit_window_seconds}`, plus `plan_type` and `credits`.
- Lanes by window length: 300 min is the session, 10080 min is weekly.

**Antigravity request details:**

- The response has two groups, "Gemini Models" and "Claude and GPT models". Each group has a weekly bucket and a 5h bucket, each with `remainingFraction` and `resetTime`.
- Fallbacks: `GetUserStatus`, then `GetCommandModelConfigs`.
- The server's self-signed certificate is accepted only for loopback.
- Full notes: `docs/antigravity.md`.

### 2.2 The iOS sync layer can be reused unchanged

All of `Shared/` (about 6k lines) imports only Foundation, CloudKit, Compression, CryptoKit, OSLog and Security. It already builds as the `CodexBarSync` library for both Mac and iOS. The iPhone app CodexBarMobile uses it through symlinks (`CodexBarMobile/Shared -> ../Shared`).

**What iOS needs from a Mac writer:**

- **Container:** `iCloud.com.columbuslabs.quotakit`, private database, Production environment.
- **Records:** `DeviceProviderSnapshot` records in zone `DeviceProvidersZone`.
  - Record name: `"{deviceID}|{providerID}|{accountEmail ?? "_"}"`.
  - `payload` is a zlib-compressed `ProviderUsageEnvelope`.
  - `encodingVersion` is 1.
- **Device metadata comes from the envelope.** The legacy `DeviceSnapshot` record and KVS are not required (`SnapshotCache.swift:178,226`).
- **What makes a card render:** `providerID`, `providerName`, `isError` and `lastUpdated`, plus at least one signal such as `primary`, `secondary` or `rateWindows`. Without a signal iOS drops the card as a ghost (`SnapshotCache.swift:59-71`).
- **iOS wakes itself.** It subscribes with `device-provider-zone-sub` (a CKRecordZoneSubscription, content-available), so there is no server and no APNs relay to run.
- **Several Macs are supported by design.** Records are keyed per `deviceID`, and iOS merges cards across Macs by `accountIdentities` strings. So Lite is simply "another Mac" to iOS.
- **Push alerts are optional.** Alerts are `QuotaTransition` records in `Quota-{providerID}-{depleted|restored|warning}Zone`. If Lite writes them, Pro users keep depletion and restoration notifications.

### 2.3 Credential access is where the maintenance cost lives

On macOS, Claude Code stores its token in the Keychain item `Claude Code-credentials`, and usually not in `~/.claude/.credentials.json`. Claude Code also rewrites that item's ACL on every token refresh, so an "Always Allow" grant does not last. Handling this costs the full app thousands of lines in `ClaudeOAuthCredentials.swift`: consent gates, prompt policies, cooldowns, delegated `claude /status` PTY refresh, and ACL repair.

Lite takes a much smaller position (see §4.1): it **reads but never prompts in the background, never refreshes, and never spawns `claude`**.

## 3. Architecture

```
QuotaKitLite.app  (single process, AppKit, no helpers, not sandboxed, Developer ID)
├── AppShell          NSApplication .accessory, NSStatusItem, NSMenu  (~250 LOC)
├── Scheduler         activity-driven refresh engine                   (~250 LOC)
├── Probes/
│   ├── ClaudeProbe   creds (file → own cache → silent Keychain) + GET  (~350 LOC)
│   ├── CodexProbe    auth.json + GET                                   (~150 LOC)
│   └── AntigravityProbe  kernel proc scan + loopback POST              (~350 LOC)
├── Model             QuotaWindow / ProviderState, local reset projection (~150 LOC)
├── SyncBridge        ProviderState → ProviderUsageSnapshot → CloudSyncManager (~300 LOC)
└── CodexBarSync      ../Shared, reused unmodified                     (6k LOC, existing)
```

The new code is about 2k lines, against about 340k in the full app. The only outside dependency is CodexBarSync.

### 3.1 Repository and package layout

- New top-level directory `QuotaKitLite/` with its own `Package.swift`, following the CodexBarMobile pattern:
  - `QuotaKitLite/Shared -> ../Shared` is a symlink;
  - the package has a target `CodexBarSync` (path `Shared`) and an executable target `QuotaKitLite`.
- It does **not** depend on `CodexBarCore`. Importing it pulls in SweetCookieKit, QuickJS, the cost store and SQLite whether they are used or not, which defeats the purpose.
- It does **not** join the root `Package.swift`. That keeps the heavy dependency graph and upstream merges away from Lite, and Lite away from them.
- `AdaptiveRefreshCore` (103 lines, no dependencies) can be shared the same way through a symlink if its policy table is useful. The scheduler in §5 is simple enough to own outright.
- Tests live in `QuotaKitLite/Tests/` and use parser fixtures copied from `Tests/CodexBarTests` (see §8 on keeping them aligned).

### 3.2 Process model and frameworks

- **App type:** `LSUIElement = YES` (no Dock icon), with `NSApplication.setActivationPolicy(.accessory)`.
- **AppKit only.** No SwiftUI, Combine or Observation. Each of those adds megabytes of footprint and its own invalidation machinery. A plain `NSMenu` with a few custom `NSView` rows is enough.
- **No WebKit, no subprocesses in steady state, no `DisplayLink`, no animations.** The status icon redraws only when its rendered value changes.
- **One networking stack:** a single `URLSession(configuration: .ephemeral)` with:
  - `urlCache = nil`
  - `httpMaximumConnectionsPerHost = 2`
  - `timeoutIntervalForRequest = 15`
  - `waitsForConnectivity = false`, because the scheduler retries.

  A separate session with a loopback-only trust delegate is created lazily for Antigravity and dropped when idle.
- **Launch at login** uses `SMAppService.mainApp`, with no helper bundle.
- **Not sandboxed**, because Lite needs:
  - read access to `~/.claude/.credentials.json` and `~/.codex/auth.json`;
  - kernel process inspection of the Antigravity `language_server`.

  This rules out the Mac App Store. Ship it the same way as the full app: Developer ID, notarized ZIP or DMG, from `columbus-labs.com/quotakit/mac`.

## 4. Providers

### 4.1 Claude

**Credential resolution** runs only when there is no cached token, or the cached one has expired. Steps in order:

1. **`~/.claude/.credentials.json`**, or `$CLAUDE_CONFIG_DIR/.credentials.json`. Parse `claudeAiOauth.{accessToken, expiresAt(ms), scopes, subscriptionType, rateLimitTier}`.
2. **Lite's own Keychain cache item.**
   - Service `com.columbuslabs.quotakit.lite.cache`.
   - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
   - Lite created this item, so reading it never prompts.
3. **Silent read of `Claude Code-credentials`.**
   - Use the `KeychainNoUIQuery` technique: `LAContext.interactionNotAllowed` plus `kSecUseAuthenticationUIFail`. Port the 20-line helper.
   - If the ACL denies access, do not prompt. Mark the state as `needsKeychainGrant`.
   - Run an attributes-only query first, and read the item's data only when its modification date changed since the last read. This is the full app's fingerprint trick (`ClaudeOAuthCredentials.swift:2441-2630`): it stops repeated secret reads and catches a CLI-side refresh cheaply.
4. **User-initiated grant only.** A menu row reads "Claude: allow Keychain access…". It runs one interactive read and copies the token into the cache from step 2. The row explains that macOS may ask again after Claude Code refreshes its token, which is Claude Code's behaviour and not Lite's.

**When the token expires:**

- Do **not** call `platform.claude.com/v1/oauth/token`. Re-run step 3, which costs nothing because the attributes check is metadata-only.
- If the Claude CLI has been used since, its refresh has already rewritten the item, so the new token is picked up silently whenever the ACL allows.
- If nobody has run `claude`, show the last known numbers with **local reset projection** (§5.3) and a muted "token expired — run `claude` once" note. Someone who isn't running Claude isn't using Claude quota, so stale numbers that roll over at known reset times are still correct.

**The request** is described in §2.1. Errors are handled as follows:

| Response | Handling |
|---|---|
| 401 | Invalidate the cached token and run credential resolution once. |
| 403 without `user:profile` | Retry without `cedar_ember`. |
| 403 with a scope error | Terminal state with a "sign in to Claude Code again" message. |
| 429 | Block this token until `max(Retry-After, 5 min)`. |
| 5xx or network error | Exponential backoff: 1, 2, 4, 8 min, capped at the regular interval. |

**Identity, for iOS merging:**

- Optional `GET /api/oauth/profile` gives the email and the account UUID. Call it **once per token fingerprint**, not once per refresh.
- Emit `claude:account:<uuid>` and `claude:email:<normalized>` through `AccountIdentityNormalize` in `Shared/`, so the bytes match exactly what `AccountIdentityComputer` writes in the full app.

**Kept from the response:** `five_hour`, `seven_day`, and `seven_day_sonnet ?? seven_day_opus`.

**Dropped:** `extra_usage`, `limits[]`, `iguana_necktie`, `cedar_ember`. They can be added later as optional envelope fields.

### 4.2 Codex

1. Read `$CODEX_HOME/auth.json`, defaulting to `~/.codex/auth.json`.
   - Fields: `tokens.access_token` and `tokens.account_id`. The account ID falls back to the JWT claim `https://api.openai.com/auth.chatgpt_account_id`.
   - Expiry comes from the access token's JWT `exp`.
   - Watch the file through the same FSEvents stream as §5.1, so a CLI-side refresh is picked up immediately.
2. If the token has expired, do not refresh it. Mark it stale with the note "run `codex` once" and apply local reset projection.
   - There is an optional, **user-initiated only** "Refresh via Codex CLI" menu item.
   - It runs `codex -s read-only -a never app-server` for one JSON-RPC exchange (`initialize`, then `account/rateLimits/read`), with a hard timeout of 10 s and SIGKILL on timeout.
   - About 120 lines. It can wait until after v1.
3. Make the request described in §2.1.
   - Map the windows by `limit_window_seconds`: 18000 s is the session, 604800 s is weekly.
   - `plan_type` becomes `loginMethod`.
   - The email comes from `id_token`.
   - Identities: `codex:account:<id>` and `codex:email:<normalized>`.
4. A 401 re-reads `auth.json` once and then becomes the "sign in" state. 429 and 5xx are handled as for Claude.

Not supported:

- the `chatgpt_base_url` override from `config.toml`;
- PAT mode;
- managed multi-account homes;
- workspaces.

These can come later as small additions.

### 4.3 Antigravity

Live data exists only while one of these is running:

- the Antigravity 2.0 app's `language_server`;
- the IDE's `language_server`;
- a signed-in `agy`.

Lite **never launches `agy`**. Doing so needs a PTY, a keyring warm-up of several seconds and a keep-alive of about 180 s, which is exactly the background weight Lite exists to avoid. Lite **does not use the Google OAuth cloud path**. That path often returns placeholder 100% values, and its client-secret discovery is fragile.

**Discovery, with no subprocesses and no `ps`/`lsof`:**

1. `proc_listallpids`, then `proc_pidpath` for each pid, keeping executables whose path contains `antigravity` or whose name matches `language_server*` or `agy`. The prefilter is the same as `DarwinProcessEnumerator.swift:7-20`.
2. `sysctl(KERN_PROCARGS2)` on the matches only, to read argv.
   - Classify as app, IDE or CLI using the regexes in `AntigravityStatusProbe.swift:1226-1300`.
   - Extract `--csrf_token`, `--extension_server_port` and `--extension_server_csrf_token`.
3. Listening ports come from `proc_pidinfo(PROC_PIDLISTFDS)` plus `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)`, filtered to TCP sockets in LISTEN state on 127.0.0.1.
4. **Cache `(pid, port, token, kind)`.** Rediscover only when:
   - a request fails with a connection error;
   - `kill(pid, 0)` fails;
   - the app's launch or terminate notification fires.

**Making it event-driven:**

- `NSWorkspace.didLaunchApplicationNotification` and `didTerminateApplicationNotification` cover the Antigravity app and IDE bundles. A launch triggers discovery after a 5 s grace period. A terminate drops the cache and marks the provider `notRunning`, keeping the last data and reset projection.
- The `agy` CLI has no NSWorkspace event. Rediscover only on the ordinary schedule. A full pid scan with path prefiltering costs about 1–3 ms.

**Fetching:**

1. `RetrieveUserQuotaSummary` with `{"forceRefresh": true}`.
2. If that fails, `GetUserStatus`, which also returns the email and plan. Call it only once per pid for identity.
3. Use the headers `Connect-Protocol-Version: 1` and `X-Codeium-Csrf-Token`, the latter only for the app and IDE kinds.

**Mapping:**

- Two rate windows per group, so four `rateWindows` in total.
- `primary` is the lowest-remaining 5h bucket and `secondary` the lowest-remaining weekly bucket, so iOS's two-bar card works.
- `usedPercent = (1 − remainingFraction) × 100`.

## 5. Refresh engine: where the CPU budget is won

The full app polls every 2 to 30 minutes and adjusts the interval around menu opens and coding activity. Lite turns this around: **it does nothing until something happens.** The default refreshes and their triggers:

| Trigger | Action |
|---|---|
| **Coding activity** (FSEvents) | Refresh that provider, then at most once per 90 s while activity continues |
| **Menu opened** | Refresh any provider whose data is older than 60 s; render the cache immediately |
| **Reset boundary reached** | Project locally to 0% at once; confirm with a fetch 60 s later |
| **System wake / network back** | One refresh per provider after a 10 s settle |
| **Antigravity app launched** | Discover, then fetch |
| **Idle heartbeat** | Every 30 min while the user is active on the Mac. Paused while the screen is locked, asleep, or the user has been idle more than 30 min. This keeps the iOS "updated" timestamps honest. |
| **Low Power Mode / serious thermal state** | Activity throttle 90 s → 5 min; heartbeat 30 min → 60 min |

### 5.1 Activity detection with FSEvents

One `FSEventStreamCreate` call, with these settings:

- Paths:
  - `~/.claude/projects`
  - `~/.codex/sessions`
  - the directory of `~/.codex/auth.json`
  - the directory of `~/.claude/.credentials.json`
  - `~/.gemini/antigravity*` — the exact path needs verifying in Phase 0.
- `latency = 15 s`: the kernel coalesces events, so there is one callback per burst at most.
- `kFSEventStreamCreateFlagNoDefer` off.
- File-level events off: directory-level is enough. Lite never reads these files; it only maps the changed path to a provider.

Cost: almost nothing. fseventsd does the work, and the app wakes at most once every 15 s, and only while an agent is actively writing logs.

### 5.2 Timers

- Exactly **one** `DispatchSourceTimer`, re-armed to the earliest "next due" time across providers.
- `leeway` is set to 10% of the interval, with a minimum of 5 s, so macOS can coalesce wakeups with other processes.
- No repeating timers, and no countdown timer for "resets in 2h 14m". That text is formatted when the menu opens.
- In the menu bar, the reset text is shown only on demand, so the menu bar itself never needs a 1-minute redraw tick.

### 5.3 Local reset projection

Each window stores `resetsAt`. When `now ≥ resetsAt`, the displayed `usedPercent` becomes 0 and `resetsAt` advances by `windowMinutes`, all without a network call. This is what makes the "expired token" and "Antigravity closed" states acceptable. Projected values are marked as projected:

- Lite does not publish projected windows to iOS as fresh data. It republishes the last real `lastUpdated`.
- iOS already does its own reset display from `resetsAt`.

### 5.4 Coexisting with the full app

If the full app (`com.columbuslabs.quotakit.mac`) is running, found via `NSRunningApplication` and the launch and terminate notifications, Lite does both of these:

- **Pauses network fetching and CloudKit writes.** The menu then shows "QuotaKit is running — Lite is paused", or reads the full app's snapshot if one is accessible.
- **Avoids doubling API traffic.** Claude's per-token 429 gate makes double polling actively harmful.

## 6. Syncing to iOS

### 6.1 What Lite writes

- **`DeviceProviderSnapshot` only**, through the existing writer methods on `CloudSyncManager` for per-provider save and delete. Lite does not write the legacy `DeviceSnapshot` record or KVS; iOS reads metadata from the envelope.
- **One record per enabled provider**, carrying a `ProviderUsageEnvelope`:
  - `deviceID`: a UUID stored in Lite's own defaults. It is deliberately different from the full app's, so the two never overwrite each other's records and one app's cleanup can't delete the other's.
  - `deviceName`: from `Host.current().localizedName`.
  - `appVersion`: `"Lite <version>"`.
  - `mobileVersion`: nil.
  - `provider`: a `ProviderUsageSnapshot` built as follows.
    - `providerID`: `claude`, `codex` or `antigravity`. These must match `QuotaProviderList`.
    - `primary` is the session window and `secondary` the weekly one, each with `label`, `windowMinutes`, `resetsAt` and `identity` (`session` or `weekly`).
    - `rateWindows` holds the Antigravity groups and the Claude Sonnet/Opus weekly window.
    - `loginMethod` is the plan.
    - `accountEmail` and `accountIdentities` follow §4.
    - `statusMessage` is set for error states, with `isError` true.
    - `pace` is optional. The pace stage maths is small and pure (expected versus actual over the elapsed part of the window), so Lite can port it about Phase 4. iOS treats it as optional.
- Every cost, budget, history and provider-specific extension field is nil.

### 6.2 Write minimisation, better than the full app today

- Lite hashes the snapshot **without its timestamps** using FNV-1a over sorted-key JSON, matching `SyncCoordinator.swift:1594-1648`.
- **The hash is persisted to disk**, so a restart doesn't re-upload everything. The full app keeps it only in memory.
- **Write rules:**
  - write when the hash changes;
  - write on the 30-minute heartbeat even if nothing changed, so iOS freshness stays right;
  - also write on state changes such as an error appearing or clearing.
- One `CKModifyRecordsOperation` per cycle, with `savePolicy = .changedKeys` and at most three records.
- Quality of service is `.utility`. `isLongLived` is false.
- **Load CloudKit lazily.** Create `CKContainer` only on the first write, behind the same entitlement check as `CloudSyncManager.swift:82-109`, so an ad-hoc dev build runs without CloudKit.

### 6.3 Cleanup

- When a provider is disabled in Lite, delete `{deviceID}|{provider}|*` for Lite's own deviceID.
- Add an "Unpublish from iPhone" menu action that deletes every Lite record. Without it, uninstalling Lite leaves stale cards behind, which is a known gap in the full app (§2.2).

### 6.4 Push alerts (Phase 4)

- Port the transition logic from `Sources/CodexBar/Sync/QuotaTransitionWriter.swift`, about 200 lines.
  - **depleted:** `usedPercent >= 100`.
  - **restored:** usage drops back after a depletion.
  - **warning:** the thresholds come from `SyncQuotaWarningConfig`.
- Write `QuotaTransition` records with the same record-name scheme and the same per-hour bucket, so alerts from several Macs collapse into one, just as they do today.
- Debounce: 5 min for depleted and restored, 60 s for warnings.
- iOS Pro users then get the same push notifications whichever Mac app they run.

### 6.5 Signing and entitlements

- **New bundle ID** `com.columbuslabs.quotakit.lite`, in the same team as the full app.
- Add the **iCloud/CloudKit capability** with container `iCloud.com.columbuslabs.quotakit` and environment **Production**.
- Use a Developer ID provisioning profile with iCloud. The full app's `Scripts/package_app.sh:293-325` already does this, so copy that pattern.
- Not needed:
  - App Group, because there is no widget;
  - KVS, because Lite doesn't write the legacy record;
  - `aps-environment`, because Lite only writes.
- **iOS needs no change.** No `appVersion` or `mobileVersion` gate was found on iOS, and Phase 0 should confirm that.
  - Optional copy change: mention Lite on the `/quotakit/mac` setup page and in iOS onboarding text. Any iOS string change needs all `Localizable.xcstrings` locales, per AGENTS.md.
  - The iOS free tier's one-card limit still applies.

## 7. UI

**Status item:**

- A template image, drawn with `NSImage(size:flipped:drawingHandler:)` and cached per rendered value.
- It shows up to three pairs of tiny bars (session over weekly), or the user's choice of compact text, for example `C 42 · X 18 · A 70`.
- It re-renders only when a rounded integer percent changes.

**Menu:**

- Content is built in `menuNeedsUpdate(_:)`, so formatting runs only when the menu is opened.
- One row per provider:
  - name and plan;
  - two bars with "37% · resets in 2h 14m";
  - the status note;
  - "updated 3m ago".
- **Actions:**
  - Refresh now.
  - Claude: allow Keychain access… (only when it's needed).
  - Providers ▸ with Claude, Codex and Antigravity toggles.
  - Menu bar style ▸ Bars / Percent / Most-used only.
  - Sync to iPhone (toggle).
  - Unpublish from iPhone.
  - Launch at login.
  - Check for updates….
  - Quit.
- **No settings window.** All preferences live in `UserDefaults` and are edited through these menu toggles.

## 8. Maintenance strategy

Lite's real long-term cost is undocumented endpoints drifting. The Claude, Codex and Antigravity APIs are private, and the full app already absorbs that churn. Strategies, all in this one repository:

1. **Shared fixtures:**
   - Copy the response fixtures for the three parsers from `Tests/CodexBarTests` into `QuotaKitLite/Tests/Fixtures/`.
   - Add a script, `Scripts/lite-fixture-sync.sh`, that diffs them against the main tests. Run it in CI and fail when they differ.
2. **Drift watch:** `Scripts/lite-drift-check.sh` lists commits since the last Lite review that touch any of these:
   - `Providers/Claude/ClaudeOAuth/`
   - `Providers/Codex/CodexOAuth/`
   - `Providers/Antigravity/AntigravityStatusProbe*`
   - `AntigravityQuotaSummaryParser`
   - `AccountIdentityComputer`

   Each upstream sync PR checks this list once. Adopting a parser fix then usually means porting a line or two.
3. **Fail soft on schema drift:**
   - Every decode uses `decodeIfPresent`.
   - An unknown shape becomes an "unrecognised response, update Lite" state, not a crash.
   - Never retry tightly on decode failures.
4. **No third-party dependencies at runtime.** The one optional exception is Sparkle; the update-path decision is in §10.
5. **Later, optional:** extract a tiny shared `QuotaProbes` module (the three parsers and requests, no dependencies) that both `CodexBarCore` and Lite use. That removes the duplication, but it refactors full-app provider code, which `VISION.md` says needs sign-off. Do it only if drift-porting turns out to be frequent.
6. **Build hygiene:**
   - `swift build -c release` for `QuotaKitLite/` runs in the existing macOS CI.
   - Parser unit tests run with no Keychain or network access, per AGENTS.md.
   - A binary-size check fails if `QuotaKitLite` exceeds 4 MB.

## 9. Measuring the budget

Each check, and when it runs:

| Check | Method | When |
| --- | --- | --- |
| Footprint | `footprint -p QuotaKitLite` at 1 min, 1 h and 8 h; target ≤ 25 MB steady, no growth | Phase 1 exit; every release |
| CPU and wakeups | `sudo powermetrics --samplers tasks --show-process-energy -i 60000` for 1 h idle and 1 h while running Claude Code; Activity Monitor Energy tab "Avg Energy Impact" ≈ 0 | Phase 1 exit; every release |
| Network | `nettop -p QuotaKitLite`: 0 requests over 30 min idle with the screen locked | Phase 1 exit |
| Regressions | Scripted soak (`Scripts/lite-soak.sh`) that samples `footprint` and `ps -o rss,%cpu` every minute for 1 h and fails on > 30 MB or any sample > 1% CPU at idle | Before each release |

Lightweight tactics to keep the footprint down:

- autorelease pools around each fetch cycle;
- `JSONDecoder` instances that are not kept around;
- the Antigravity URLSession is dropped after 5 idle minutes;
- `malloc_zone_pressure_relief(nil, 0)` after a CloudKit write burst, as the full app's `CLIServeHeapTrimmer` does.

## 10. Phased delivery

| Phase | Deliverable | Exit criteria |
|---|---|---|
| **0 — Spike** (1–2 days) | Throwaway checks on a real Mac (the five questions below) | All five answered; record the results in this doc |
| **1 — Lite core** | Shell, scheduler, Claude and Codex probes, menu UI, local reset projection | §9 budget met with sync off; parser tests green |
| **2 — iPhone sync** | SyncBridge, persisted dedup hash, cleanup, identity strings | iPhone shows Lite cards; a single card when the full app also runs on another Mac with the same accounts; no write when nothing changed |
| **3 — Antigravity** | Kernel process discovery, loopback fetch, launch observer | Live data while the Antigravity app is open; a clean "not running" state otherwise; zero subprocesses |
| **4 — Polish and ship** | QuotaTransition alerts, pace, Sparkle (or a lightweight appcast check), notarized release lane, setup page link | Pro push alerts fire from Lite; soak test passes; notarized build installs cleanly |
| **5 — Optional** | Codex app-server "refresh via CLI", shared `QuotaProbes` extraction, the Codex `chatgpt_base_url` override | As needed |

**Phase 0 questions:**

1. Does a no-UI read of `Claude Code-credentials` succeed for a newly signed app, and how often does Claude Code's ACL rewrite force a re-grant?
2. Does `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` read the item without a prompt? That depends on whether Claude Code lists `security` in the item's ACL. If it does, it's a better fallback than an interactive grant: one about 10 ms subprocess roughly every 8 h, and only on token expiry.
3. Can `PROC_PIDFDSOCKETINFO` list the Antigravity `language_server`'s listening ports without root? It should for the same user.
4. Does a Developer ID provisioning profile for the new bundle ID with the existing container write to Production?
5. Baseline footprint of an empty `NSStatusItem` app with and without CloudKit loaded.

**Update path (decision in Phase 4):**

- **Default:** Sparkle, reusing the existing EdDSA appcast pipeline with a separate `appcast-lite.xml`, set to check once a day.
- **If footprint is tight:** replace it with one daily GET of the appcast and a "Download update" menu item. This trades install convenience for about 1–2 MB less binary and fewer dependencies.

## 11. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Claude Code Keychain ACL churn | Claude data goes stale after token refresh until the user re-grants | `.credentials.json` first; a metadata-only change check; the `security` CLI path if Phase 0 proves it; honest stale UI with reset projection |
| A private endpoint changes shape | A provider shows "unrecognised response" | Fail-soft decoding, fixture sync, drift check (§8) |
| Antigravity is closed most of the time | No live Antigravity data | By design; a launch observer gives an instant fetch when it opens; the last-known data stays projected |
| Lite and the full app run on the same Mac | Double polling, 429s | §5.4 auto-pause |
| CloudKit ghost records after Lite is uninstalled | Stale card on iPhone | An "Unpublish from iPhone" action; iOS already hides records with no email after 30 min |
| CloudKit entitlement provisioning for a second Mac bundle ID | Sync blocked | Phase 0 question 4, before any sync code |

## 12. Open product decisions

1. Name: "QuotaKit Lite", "QuotaKit Mini", or something else.
2. Should Lite be a free standalone download alongside the full app, or replace it for users who only need these three providers?
3. Should iOS Pro push alerts (Phase 4) ship in v1, or is the card plus widget sync enough at first?
4. Should Lite pause when the full app is running (recommended), or keep publishing independently?
