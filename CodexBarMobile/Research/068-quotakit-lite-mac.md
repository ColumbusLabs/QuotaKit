# 068 — QuotaKit Lite for Mac (rate-limit-only spinoff)

- **Status:** `in progress`: Phase 0 done (§10); product decisions recorded in §12
- **Date:** 2026-10-11
- **Scope:** A new, separate Mac menu bar app that tracks only rate-limit windows for
  Claude, Codex, and Antigravity, and syncs them to the existing iOS app without iOS changes.
- **Audience:** Personal tool for the repository owner, not a public product. There are no public
  releases, updater, website, or onboarding. Its only user-facing surfaces are its own menu and the existing iPhone app.

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
   | Binary size, including logo resources | ≤ 3 MB |
   | Helper processes | none |
   | Keychain prompts during background work | none, ever |

3. Needs almost no upkeep: no third-party runtime dependencies, about 3k lines of new code, and no upstream-sync burden.
4. **Publishes to the existing iPhone app** through the same CloudKit records the full app writes, so iOS, widgets, and push alerts work unchanged.

**Non-goals:**

- cost or spend, token history, daily charts;
- multiple accounts;
- other providers;
- web or cookie sources;
- a CLI;
- Mac widgets;
- a settings window;
- public distribution: no notarized release lane, no Sparkle or appcast, no setup page, no onboarding copy, no localization.

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
- On a 400, or a 403 whose body does not mention `user:profile`, retry once without `cedar_ember`, using the
  same token and the fallback User-Agent `claude-code/<ver>`. A 403 that mentions `user:profile` is a scope error
  and is not retried. This matches `ClaudeOAuthUsageFetcher.swift:104-113`.
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
- **What makes a card render:** `providerID`, `providerName`, `isError` and `lastUpdated`, plus at least one signal such as `primary`, `secondary` or `rateWindows`, or `isError` set, or a `statusMessage`. Otherwise iOS drops the card as a ghost (`SnapshotCache.isGhost`).
- **iOS wakes itself.** It subscribes with `device-provider-zone-sub` (a CKRecordZoneSubscription, content-available), so there is no server and no APNs relay to run.
- **Several Macs are supported by design.** Records are keyed per `deviceID`, and iOS merges cards across Macs by `accountIdentities` strings. So Lite is simply "another Mac" to iOS.
- **Push alerts are optional.** Alerts are `QuotaTransition` records in `Quota-{providerID}-{depleted|restored|warning}Zone`. If Lite writes them, Pro users keep depletion and restoration notifications.

### 2.3 Credential access is where the maintenance cost lives

On macOS, Claude Code stores its token in the Keychain item `Claude Code-credentials`, and usually not in `~/.claude/.credentials.json`. Claude Code also rewrites that item's ACL on every token refresh, so an "Always Allow" grant does not last. Handling this costs the full app thousands of lines in `ClaudeOAuthCredentials.swift`: consent gates, prompt policies, cooldowns, delegated `claude /status` PTY refresh, and ACL repair.

Lite takes a much smaller position (see §4.1): it **reads the token through `/usr/bin/security` only when the item changes, never prompts, never refreshes, and never spawns `claude`**.

## 3. Architecture

```
QuotaKitLite.app  (single process, AppKit, no helpers, not sandboxed, signed locally)
├── AppShell          NSApplication .accessory, NSStatusItem, NSMenu, auto-pause (~250 LOC)
├── UI/               status item renderer, provider cards, bars, logos (~700 LOC, §7)
├── Scheduler         activity-driven refresh engine                   (~250 LOC)
├── Probes/
│   ├── ClaudeProbe   creds (file → own cache → silent Keychain) + GET  (~350 LOC)
│   ├── CodexProbe    auth.json + GET                                   (~150 LOC)
│   └── AntigravityProbe  kernel proc scan + loopback POST              (~350 LOC)
├── Model             QuotaWindow / ProviderState, local reset projection (~150 LOC)
├── SyncBridge        ProviderState → ProviderUsageSnapshot → CloudSyncManager (~300 LOC)
├── Alerts            transition detector, QuotaTransition writer, Mac banners (~300 LOC, §6.4)
└── CodexBarSync      ../Shared, reused unmodified                     (6k LOC, existing)
```

The new code is about 3k lines, against about 340k in the full app. The only outside dependency is CodexBarSync.

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
- **No WebKit, no `DisplayLink`, no animations, and no subprocesses in steady state.** The one exception is a
  short `/usr/bin/security` read (about 0.1 s) when the Claude Keychain item changes (§4.1). The status icon redraws only when its rendered value changes.
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

  This rules out the Mac App Store, which doesn't matter for a personal tool.
- **Build and install** run locally from source: `QuotaKitLite/Scripts/install.sh` builds a release binary, assembles
  the `.app` with its icon resources, and signs it with the same team identity and a provisioning profile that
  carries the CloudKit entitlement (§6.5). It installs to `~/Applications/QuotaKit Lite.app` and relaunches the app.
  Notarization isn't needed, because the app is built and signed on the machine that runs it. Updating is just
  `git pull`, then running the script again.

## 4. Providers

### 4.1 Claude

**Credential resolution** runs only when there is no cached token, or the cached one has expired. Steps in order:

1. **`~/.claude/.credentials.json`**, or `$CLAUDE_CONFIG_DIR/.credentials.json`. Parse `claudeAiOauth.{accessToken, expiresAt(ms), scopes, subscriptionType, rateLimitTier}`.
   On the owner's Mac this file does not exist (Phase 0), so in practice the token comes from step 3.
2. **Lite's own Keychain cache item.**
   - Service `com.columbuslabs.quotakit.lite.cache`.
   - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
   - Lite created this item, so reading it never prompts. It saves a subprocess on every launch.
3. **Change check, then `/usr/bin/security`.**
   - First run an attributes-only `SecItemCopyMatching` on `Claude Code-credentials` (no `kSecReturnData`), with
     the `KeychainNoUIQuery` flags. Phase 0 showed this never prompts, even after Claude Code rewrites the item.
   - Read the secret only when the item's modification date changed since the last read. This is the full app's
     fingerprint trick (`ClaudeOAuthCredentials.swift:2441-2630`).
   - Read it with `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`. Claude Code lists
     `security` in the item's ACL, and it stayed silent after a token refresh (Phase 0: about 0.05–0.12 s). Rules:
     hard 5 s timeout, then SIGKILL; stdout read into memory only, never logged; at most one run per modification
     date.
   - **Never read the item's data with `SecItemCopyMatching`.** Phase 0 showed that the no-UI flags do **not**
     stop the Keychain dialog for this item. A newly signed app got a dialog, and "Always Allow" was wiped by
     Claude Code's next token refresh, which brought the dialog back. In the background, that would be a dialog
     roughly every 8 hours of Claude use.
4. **If `security` ever fails** (a non-zero exit, or a timeout), mark the state `needsKeychainAccess` and show
   "Claude: token unavailable — run `claude` once". Lite has no interactive grant fallback, because a grant
   doesn't survive the next token refresh.

**When the token expires:**

- Do **not** call `platform.claude.com/v1/oauth/token`. Re-run step 3, which costs nothing until the
  modification date changes.
- If the Claude CLI has been used since, its refresh has already rewritten the item, so the change check picks up
  the new token with a single `security` read.
- If nobody has run `claude`, show the last known numbers with **local reset projection** (§5.3) and a muted "token expired — run `claude` once" note. Someone who isn't running Claude isn't using Claude quota, so stale numbers that roll over at known reset times are still correct.

**The request** is described in §2.1. Errors are handled as follows:

| Response | Handling |
|---|---|
| 401 | Invalidate the cached token and run credential resolution once. |
| 400, or 403 whose body doesn't mention `user:profile` | Retry once without `cedar_ember` (§2.1), then handle the retry's status with this table. |
| 403 whose body mentions `user:profile` | Scope error: terminal state with a "sign in to Claude Code again" message. No retry. |
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
   - The Antigravity 2.0 app (`/Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone`)
     passes `--https_server_port` and `--csrf_token`, and no extension-server flags (Phase 0). When
     `--https_server_port` is present, use it directly and skip the socket scan.
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

### 5.4 Coexisting with the full app (confirmed: auto-pause)

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
    - `pace` is filled in for every window (§7.5). Its `stage`, `deltaPercent`, `expectedUsedPercent` and
      `actualUsedPercent` fields come from the same calculation the menu uses. `leftLabel` and `rightLabel` carry the
      exact strings ("3% in reserve", "Runs out in 1d 4h"), so the iPhone shows the same text as the Mac.
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

- When a provider is disabled in Lite, delete `{deviceID}|{provider}|*` for Lite's own deviceID. Delete by the record
  names Lite has persisted, not by querying on `deviceID`, which can come back empty right after a write (Phase 0, Q4).
- Add an "Unpublish from iPhone" menu action that deletes every Lite record. Without it, uninstalling Lite leaves stale cards behind, which is a known gap in the full app (§2.2).

### 6.4 Alerts (v1, shipped with sync in Phase 2)

**iPhone push alerts** come from CloudKit `QuotaTransition` records. iOS already subscribes to them when Pro is unlocked, and its notification service extension rewrites the text.

- Port the transition logic from `Sources/CodexBar/Sync/QuotaTransitionWriter.swift`, about 200 lines, without the `CodexBarCore` import.
  - **depleted:** a window reaches `usedPercent >= 100`.
  - **restored:** usage drops back after a depletion. In practice this happens after a reset, and the confirm fetch from §5.3 detects it.
  - **warning:** a window crosses a remaining-percent threshold. The defaults are `[50, 20]` remaining, the same as the full app, configured per window (session or weekly).
- **Write the records exactly as the full app does:**
  - zones `Quota-{providerID}-{depleted|restored|warning}Zone`;
  - the same record-name scheme, including the hour bucket and the 8-byte SHA256 scope;
  - fields `providerName`, `providerID`, `state`, `transitionAt`, `deviceID`, `accountEmail`, `windowDisplayLabel`.

  Same-hour duplicates then collapse into one alert, and the extension renders the text correctly.
- **Debounce:** 5 min for depleted and restored, 60 s for warnings. A debounce timestamp is stored only after a successful write.
- **Never alert from guesses.** Transitions are evaluated only on **fetched** data, never on the projected values from §5.3. On a cold start, Lite seeds its "last state" from a persisted copy, so a restart doesn't fire a fresh alert for a window that was already depleted.
- **Keep the iPhone markers in step.** Lite also ships the effective thresholds as `ProviderUsageEnvelope.quotaWarnings` (`SyncQuotaWarningConfig`), so the iPhone draws markers at the same places alerts fire.
- **Paused means silent.** While auto-paused (§5.4), Lite writes no alerts; the full app owns them then.

**Mac alerts** are a local `UNUserNotificationCenter` banner for the same transitions, using the provider logo as the attachment. They are on by default and can be turned off in the menu. Notification permission is requested once, the first time an alert would fire. No extra process is involved.

**Alert menu (Alerts ▸):**

- iPhone push on or off;
- Mac banner on or off;
- warning thresholds, with presets `50 / 20`, `25 / 10`, or `Depleted only`.

### 6.5 Signing and entitlements

- **New bundle ID** `com.columbuslabs.quotakit.lite`, in the same team as the full app.
- Add the **iCloud/CloudKit capability** with container `iCloud.com.columbuslabs.quotakit` and environment **Production**.
- Use a Developer ID provisioning profile with iCloud. The full app's `Scripts/package_app.sh:293-325` already does this, so copy that pattern.
- Not needed:
  - App Group, because there is no widget;
  - KVS, because Lite doesn't write the legacy record;
  - `aps-environment`, because Lite only writes.
- **iOS needs no change.** No `appVersion` or `mobileVersion` gate was found on iOS, and Phase 0 should confirm that.
  - Since this is a personal tool, there's no setup-page or onboarding copy.
  - Push alerts need Pro unlocked on the phone, as they do with the full app.

## 7. UI: polished but cheap

The menu should look as good as the full app's cards, with real provider logos, brand colours and proper bars.
It should still cost nothing while closed.

### 7.1 Rendering approach

- **AppKit with custom-drawn `NSView` rows,** not SwiftUI. SwiftUI hosted in `NSMenu` items (as the full app's
  `MenuCardView` does) loads the SwiftUI and AttributeGraph runtime for the life of the process. Phase 0 measured
  about 5 MB for one hosted row (15.1–15.8 MB in total), against 0.8 MB for a custom-drawn row, within a budget
  of 25 MB.
  Custom `draw(_:)` code produces the same visual result for one fixed layout, in about 300 lines.
- **Card views live only while the menu is open.** Build them in `menuNeedsUpdate(_:)` and release them in
  `menuDidClose(_:)`. A closed menu holds only the model structs.
- **Appearance:**
  - Semantic colours (`labelColor`, `secondaryLabelColor`, `quaternaryLabelColor` for bar tracks) adapt
    to light and dark mode and to the menu's vibrancy for free.
  - Text uses the system font, with `monospacedDigit` for percentages, so numbers don't jitter.
- **Accessibility:** every card sets an accessibility label such as "Claude, session 37 percent used, resets in 2 hours
  14 minutes".

### 7.2 Provider assets, reused from the full app

| Provider | Template icon (menu bar) | Brand icon (menu card) | Brand colour |
|---|---|---|---|
| Claude | `Sources/CodexBar/Resources/ProviderIcon-claude.svg` | `Brand-ProviderIcon-claude.svg` | `#CC7C5E` |
| Codex | `ProviderIcon-codex.svg` | `Brand-ProviderIcon-codex.png` | `#49A3B0` |
| Antigravity | `ProviderIcon-antigravity.svg` | `Brand-ProviderIcon-antigravity.png` | `#60BA7E` |

- **Where the colours come from:** the `branding.color` values in each `*ProviderDescriptor.swift`.
- **Copy, don't link:** the six files total about 50 KB and go into `QuotaKitLite/Resources/`. A check in
  `lite-fixture-sync.sh` flags any time the full app's copies change.
- **Loading:** `NSImage` loads them once at 16 pt and 18 pt. Template icons get `isTemplate = true`, the same
  way `ProviderBrandIcon.swift` handles them.
- **App icon:** the QuotaKit icon with a small "Lite" badge. It only shows in Finder and in notification banners.

### 7.3 Status item

The status item is a single `NSStatusItem` with a cached image. It redraws only when the displayed value changes.
There are three styles, chosen under Menu bar style ▸:

1. **Logos and bars** (default). For each enabled provider: its template logo at 14 pt, and two hairline bars under
   it (session on top, weekly underneath). Three providers fit in about 70 pt.
2. **Most constrained.** One logo for whichever provider has the least headroom, plus its percent, for example
   `[Claude logo] 82%`.
3. **Percentages.** A logo and a percentage for each provider.

The image stays a template image, so it follows the menu bar's appearance. The one exception is a provider that is
depleted or at 95% or more: its bars are drawn in `systemRed` as a non-template overlay, so a problem is
visible at a glance.

### 7.4 Menu layout

```
┌────────────────────────────────────────────────┐
│ [Claude logo]  Claude      Max 20x     2m ago  │
│   Session  ███████░┆░░░░░░░░░░  37%            │
│            3% in reserve · Lasts until reset   │
│            Resets in 2h 14m · 4:30 PM          │
│   Weekly   ████████████░┆░░░░░  61%            │
│            8% in deficit · Runs out in 1d 4h   │
│            Resets Thu 9:00 AM                  │
│   Sonnet   ████░░░░░░░░░░░░░░░  22%            │
├────────────────────────────────────────────────┤
│ [Codex logo]  Codex         Pro        1m ago  │
│   Session  …                                   │
│   Weekly   …                                   │
├────────────────────────────────────────────────┤
│ [Antigravity logo]  Antigravity  Ultra  5m ago │
│   Gemini        5h ██░░  12%   Week █████░ 48% │
│   Claude + GPT  5h ████  70%   Week ███░░░ 33% │
│   ⏸ Not running — showing last data            │
├────────────────────────────────────────────────┤
│ ↻ Refresh now                            ⌘R    │
│ Alerts ▸   Providers ▸   Menu bar style ▸      │
│ ✓ Sync to iPhone          ✓ Launch at login    │
│ Unpublish from iPhone                          │
│ Quit QuotaKit Lite                       ⌘Q    │
└────────────────────────────────────────────────┘
```

**Card header:**

- the brand logo at 18 pt;
- the provider name, semibold;
- the plan as a small rounded pill;
- a "2m ago" freshness label, right-aligned.

**Bars:**

- 6 pt rounded capsules filled with the provider's brand colour;
- the fill turns `systemOrange` at 80% and `systemRed` at 95% or more;
- thin tick marks at the alert thresholds (the same idea as the full app's `MenuCardQuotaWarningMarkers`), so the
  bars show where an alert will fire;
- a projected (post-reset) value is drawn with a dashed outline instead of a solid fill.

**Pace line** goes under each bar: "3% in reserve" (or "8% in deficit" / "On pace") on the left, then "Lasts until
reset" / "Runs out in 1d 4h" / "Projected empty in 40m" on the right, as in the full app. A small `┆` tick on the
bar marks the expected position, so you can see at a glance whether you're ahead of or behind pace. Details are in §7.5.

**Reset text** combines a relative and an absolute time ("Resets in 2h 14m · 4:30 PM"), formatted only when the
menu opens.

**State footer:** one line with an SF Symbol, shown only when something needs attention:

- `key` with "Claude token unavailable — run claude once" (shown if `/usr/bin/security` fails, §4.1);
- `terminal` with "Token expired — run claude once";
- `pause.circle` with "Not running — showing last data";
- `pause.fill` with "Paused — QuotaKit is running";
- `exclamationmark.triangle` with a short error.

**Clicking a card** opens that provider's own usage page in the browser:

- Claude: `claude.ai/settings/usage`;
- Codex: the ChatGPT Codex usage settings page;
- Antigravity: nothing.

**No settings window.** All preferences live in `UserDefaults` and are edited through these menu toggles.

### 7.5 Pace ("3% in reserve")

**Port `UsagePace.weekly` unchanged.** It's in `Sources/CodexBarCore/UsagePace.swift`, about 150 lines, with no
dependencies; it only needs a small local `RateWindow` stand-in. It does the following:

- `expected = elapsed / windowDuration × 100`, with an optional workday weighting for weekly windows;
- `delta = actual − expected`. Delta of 2 or less is "On pace"; otherwise a negative delta is "N% in reserve" and a
  positive one is "N% in deficit";
- stages: 2 or less is on track, 6 or less is slightly ahead or behind, 12 or less is ahead or behind, and anything
  more is far ahead or behind;
- the run-out estimate extrapolates the current burn rate:
  - if usage will last to the reset, the label is "Lasts until reset";
  - otherwise it is "Runs out in X" for weekly windows and "Projected empty in X" for the session.

**Port the label wording** from `Sources/CodexBar/UsagePaceText.swift` (`detailLeftLabel` and `detailRightLabel`), as
plain English strings.

**Where pace shows up:**

- every window, Antigravity's group buckets included;
- the menu cards;
- the iPhone cards, through `SyncUsagePace`;
- optionally the menu bar: a "Show pace in menu bar" toggle adds `+3`/`−8` next to the percentage in the
  Percentages and Most-constrained styles, following the full app's sign convention ("Reserve is +").

**Workday pacing:** there's an optional menu choice of 5 or 6 workdays for the weekly expectation, which the
full app also has (`workDays`). The default is 7 days.

**Not ported:** the full app's history-based pace (`HistoricalUsagePace.swift`, the "(12% risk)" suffix and
learned burn curves). It needs weeks of stored usage history plus about 900 lines of code. If you want the risk
figure later, the cheap way is a small ring buffer of `(timestamp, usedPercent)` samples per window, persisted as one
small JSON file and appended only on fetched data. It's listed as a Phase 5 option.

**Cost:** nothing. Pace is computed only when the menu opens, when the status item changes, and when the iPhone
payload is built. There's no extra timer.

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
4. **No third-party dependencies at all.** No Sparkle: updating is `git pull` followed by `install.sh`.
5. **Later, optional:** extract a tiny shared `QuotaProbes` module (the three parsers and requests, no dependencies) that both `CodexBarCore` and Lite use. That removes the duplication, but it refactors full-app provider code, which `VISION.md` says needs sign-off. Do it only if drift-porting turns out to be frequent.
6. **Build hygiene:**
   - `swift build -c release` for `QuotaKitLite/` runs in the existing macOS CI. It's cheap, and it stops a
     `Shared/` change from breaking Lite silently.
   - Parser and alert-transition unit tests run with no Keychain or network access, per AGENTS.md.
   - A binary-size check fails if `QuotaKitLite` exceeds 4 MB.
   - Because this is a personal tool, there's no release lane, versioning ceremony, or changelog. A git short SHA
     in the About line is enough.

## 9. Measuring the budget

Each check, and when it runs:

| Check | Method | When |
| --- | --- | --- |
| Footprint | `footprint -p QuotaKitLite` at 1 min, 1 h and 8 h; target ≤ 25 MB steady, no growth; also after opening and closing the menu 20 times, to show card views are released | Phase 1 exit; after UI changes |
| CPU and wakeups | `sudo powermetrics --samplers tasks --show-process-energy -i 60000` for 1 h idle and 1 h while running Claude Code; Activity Monitor Energy tab "Avg Energy Impact" ≈ 0 | Phase 1 exit; after scheduler changes |
| Network | `nettop -p QuotaKitLite`: 0 requests over 30 min idle with the screen locked | Phase 1 exit |
| Regressions | Scripted soak (`Scripts/lite-soak.sh`) that samples `footprint` and `ps -o rss,%cpu` every minute for 1 h and fails on > 30 MB or any sample > 1% CPU at idle | Before installing a build with structural changes |

Lightweight tactics to keep the footprint down:

- autorelease pools around each fetch cycle;
- `JSONDecoder` instances that are not kept around;
- the Antigravity URLSession is dropped after 5 idle minutes;
- `malloc_zone_pressure_relief(nil, 0)` after a CloudKit write burst, as the full app's `CLIServeHeapTrimmer` does.

## 10. Phased delivery

| Phase | Deliverable | Exit criteria |
|---|---|---|
| **0 — Spike** (1–2 days) | Throwaway checks on a real Mac (the six questions below) | All six answered; record the results in this doc |
| **1 — Core and menu** | Shell, scheduler, Claude and Codex probes, local reset projection, the full polished menu (§7) with logos, status item styles, pace (§7.5) | §9 budget met with sync off; parser tests green; the menu looks right in light and dark mode |
| **2 — iPhone sync and alerts** | SyncBridge, persisted dedup hash, cleanup, identity strings, pace on iPhone cards, `quotaWarnings`, QuotaTransition push alerts, Mac banners, auto-pause | iPhone shows Lite cards; a single merged card when the full app has the same accounts; no write when nothing changed; a forced threshold crossing delivers exactly one iPhone push and one Mac banner; no alerts while paused |
| **3 — Antigravity** | Kernel process discovery, loopback fetch, launch observer, two-group card | Live data while the Antigravity app is open; a clean "not running" state otherwise; zero subprocesses; Antigravity alerts work |
| **4 — Finish** | `install.sh`, launch at login, soak test | One week of daily use with no unexplained prompts, stale data or energy flags |
| **5 — Optional** | History-based pace risk (§7.5), Codex app-server "refresh via CLI", shared `QuotaProbes` extraction, the Codex `chatgpt_base_url` override | As needed |

**Phase 0 questions:**

1. Does a no-UI read of `Claude Code-credentials` succeed for a newly signed app, and how often does Claude Code's ACL rewrite force a re-grant?
2. Does `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` read the item without a prompt? That depends on whether Claude Code lists `security` in the item's ACL. If it does, it's a better fallback than an interactive grant: one about 10 ms subprocess roughly every 8 h, and only on token expiry.
3. Can `PROC_PIDFDSOCKETINFO` list the Antigravity `language_server`'s listening ports without root? It should for the same user.
4. Does a provisioning profile for the new bundle ID with the existing container write to Production? Try a
   Developer ID profile, or a Mac Development profile with `icloud-container-environment = Production`.
5. Baseline footprint of an empty `NSStatusItem` app with and without CloudKit loaded.
6. How much footprint does one SwiftUI-hosted menu row add, compared with a custom-drawn `NSView` row? This confirms
   the §7.1 choice.

**Phase 0 results** (2026-10-11, macOS 27.0, Claude Code 2.1.292). The spike was a throwaway SwiftPM package
outside the repo. It linked `Shared/` and was signed with Developer ID as `com.columbuslabs.quotakit.lite`, and it
never printed secret values.

| Q | Result |
|---|---|
| 1 | **No.** The no-UI read (`interactionNotAllowed` plus `kSecUseAuthenticationUIFail`) **showed the Keychain dialog** and blocked for 158 s until the owner answered. After "Always Allow" it read in 0.05 s. After Claude Code refreshed its token (`claude -p`, which rewrote the item), the same read showed the dialog again; the owner denied it (`-128`). So every token refresh, about every 8 h of use, wipes a grant, and the no-UI flags don't stop the dialog. An attributes-only query never prompted. |
| 2 | **Yes.** `security find-generic-password -w` read the item silently both before and after the refresh (0.12 s, then 0.05 s, exit 0), returning the new token. §4.1 now reads through `security` only. |
| 3 | **Yes, without root.** Scanning every process found the 2.0 app's `language_server` in 18–58 ms with no subprocesses. `PROC_PIDFDSOCKETINFO` listed ports 56140 (HTTPS) and 56142 (HTTP). `RetrieveUserQuotaSummary` returned HTTP 200 with a `response` object on both. |
| 4 | **Yes.** Created App ID `com.columbuslabs.quotakit.lite` ("QuotaKit Lite": iCloud with CloudKit, container `iCloud.com.columbuslabs.quotakit`) and a Developer ID profile, "QuotaKit Lite Developer ID" (UUID `152abca4-170b-4b14-a30b-324e5e619af7`, Developer ID certificate expiring 2031-08-01). With the profile embedded and `icloud-container-environment = Production`, `CloudSyncManager.pushPerProviderRecords` saved a ghost record. Fetching it by record ID returned it (196-byte payload); `deletePerProviderRecords` removed it, and a second fetch returned `unknownItem`. Account status: `available`. One caveat: `fetchPerProviderRecordNames(forDeviceID:)` returned 0 right after the save, either because the query index lags or because that helper hides errors. Lite's cleanup (§6.3) should delete by known record names rather than rely on that query. |
| 5 | AppKit `.accessory` status item app: **10.1–10.3 MB**. With `CodexBarSync` linked and CloudKit unused: **11.0–11.5 MB**. After touching CloudKit (account status plus one query): **11.5–12.3 MB**, so CloudKit costs under 1 MB. Signed spike bundle including `CodexBarSync`: **2.1–2.2 MB**. |
| 6 | A custom-drawn `NSView` row adds **0.8 MB**; a SwiftUI-hosted row adds **about 5 MB**. AppKit stays (§7.1). |

Other finding: `~/.claude/.credentials.json` does not exist on this Mac, so §4.1 step 1 never applies here.

## 11. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Claude Code Keychain ACL churn | A direct read prompts after every token refresh (confirmed in Phase 0) | Never read the secret with `SecItem`; a metadata-only change check, then `/usr/bin/security`, which Claude Code allows; honest stale UI with reset projection if `security` ever fails |
| Claude Code drops `security` from the item's ACL | Claude token unavailable | Detected as a non-zero exit; "run `claude` once" state; no dialog is ever shown |
| A private endpoint changes shape | A provider shows "unrecognised response" | Fail-soft decoding, fixture sync, drift check (§8) |
| Antigravity is closed most of the time | No live Antigravity data | By design; a launch observer gives an instant fetch when it opens; the last-known data stays projected |
| Lite and the full app run on the same Mac | Double polling, 429s | §5.4 auto-pause |
| CloudKit ghost records after Lite is uninstalled | Stale card on iPhone | An "Unpublish from iPhone" action; iOS already hides records with no email after 30 min |
| Duplicate or spurious alerts | Noise on phone and Mac | Alerts only from fetched data, never projected; persisted last state; same record names and hour bucket as the full app; paused means silent |
| CloudKit entitlement provisioning for a second Mac bundle ID | Sync blocked | Phase 0 question 4, before any sync code |

## 12. Decisions

| Question | Decision |
|---|---|
| Name | **QuotaKit Lite** (bundle ID `com.columbuslabs.quotakit.lite`) |
| Audience | **Personal tool for the owner only.** Built from source and signed locally; no public release, updater, setup page, onboarding or localization. |
| Alerts | **In v1.** iPhone push through `QuotaTransition` records and a local Mac banner, both in Phase 2 alongside sync. |
| Menu look | **Polished.** Real provider logos and brand colours from the full app's assets, brand-coloured bars with threshold ticks; custom-drawn AppKit, not SwiftUI, to keep the footprint (§7). |
| Pace | **In v1**, on the Mac menu and the iPhone cards, using the full app's formula and wording (§7.5) |
| Coexistence | **Auto-pause** while the full QuotaKit app is running (§5.4). |

## 13. Implementation slices

Each slice is one reviewable commit or PR that builds and is used on its own. The package splits into two targets so
that most of the logic can be tested without AppKit:

- **`LiteCore`** depends only on Foundation and `CodexBarSync`. It holds the models, parsers, pace, reset projection,
  the scheduler policy, the transition detector and the envelope mapping. It builds and tests on **macOS only**.
  `Shared/` guards only `CloudSyncManager.swift` with `canImport(CloudKit)`. `PayloadCompression.swift` imports
  `Compression` and `AccountIdentityNormalize.swift` imports `CryptoKit` without guards, and neither framework
  exists on Linux. Lite doesn't change `Shared/` to fix this, because the iOS app builds the same files. The split
  is still worth having: `LiteCore` tests run without AppKit, a Keychain or the network.
- **`QuotaKitLite`** is the AppKit app. It holds the UI, Keychain, FSEvents, kernel process APIs, CloudKit and the
  notification glue, and it is verified on the Mac.

**Phase 0: verify on a real Mac**

**S0 — Spike harness.** ✅ Done 2026-10-11; results in §10.
- Build a throwaway `lite-spike` executable with five subcommands:
  - `keychain` does a silent read of `Claude Code-credentials`, then tries the `security` CLI;
  - `cloudkit` saves and then deletes one `DeviceProviderSnapshot` under a `spike-` deviceID;
  - `antigravity` prints the ports found through kernel socket info;
  - `footprint-empty` and `footprint-cloudkit` measure baselines.
- **Size:** about 300 lines, deleted after use.
- **Done when:** all six Phase 0 answers are recorded in §10. If the CloudKit check fails, rework the plan before S8.

**Phase 1: core and menu**

**S1 — Skeleton and install.**
- Files:
  - `QuotaKitLite/Package.swift`;
  - the `Shared` symlink;
  - an empty `LiteCore`;
  - an `.accessory` app with one `NSStatusItem` showing a static Claude template logo and a Quit item;
  - resources copied from the full app (§7.2);
  - `Scripts/install.sh`, which builds, assembles the `.app`, adds entitlements (§6.5), signs, installs to
    `~/Applications` and relaunches.
- **Size:** about 250 lines.
- **Done when:** it launches at the menu bar and survives a relaunch, with a measured idle footprint.

**S2 — Model, pace and reset projection** (`LiteCore`).
- Contents:
  - `QuotaWindow`, `ProviderState` and `ProviderStatus`;
  - the `UsagePace.weekly` port and the label wording (§7.5);
  - local reset projection (§5.3);
  - a persisted state store (one JSON file in Application Support).
- **Tests:** pace stages and labels against the full app's expectations, reset rollover, and workday pacing.
- **Size:** about 450 lines including tests.

**S3 — Codex probe.**
- Contents:
  - the `auth.json` reader (`CODEX_HOME`, JWT claims for account ID, email and expiry);
  - the `wham/usage` request;
  - window mapping by length;
  - the 401, 429 and 5xx handling from §4.2;
  - identity strings that match `AccountIdentityComputer`.
- **Tests:** fixtures copied from `Tests/CodexBarTests`.
- **Size:** about 250 lines.
- **Done when:** a temporary menu row shows real Codex numbers.

**S4 — Claude probe.**
- Contents:
  - the credential chain from §4.1: file, then Lite's Keychain cache, then an attributes-only change check
    followed by a `/usr/bin/security` read, with a 5 s timeout;
  - the usage request with its `cedar_ember` retry, and the 429 gate;
  - the profile identity call, made once per token fingerprint.
- **Tests:** parsing and mapping run against fixtures; the Keychain code sits behind a protocol and is tested
  with a stub, never real `SecItem` calls (AGENTS.md).
- **Size:** about 400 lines.

**S5 — Scheduler.**
- Contents:
  - the due-time policy in `LiteCore`, as a pure function from the trigger list in §5 to the next due time
    per provider;
  - in the app: one `DispatchSourceTimer` with leeway, the FSEvents stream, wake and network observers, the
    menu-open trigger, a Low Power and thermal clamp, and exponential backoff.
- **Tests:** a policy table covering activity bursts, idle, lock, low power and backoff.
- **Size:** about 350 lines.
- **Done when:** over 30 minutes of locked idle, `nettop` shows no requests; while a coding agent runs, there is at
  most one fetch per 90 s.

**S6 — Menu cards.**
- Contents: the custom-drawn `ProviderCardView`, with
  - the header row (logo, name, plan pill, freshness);
  - capsule bars in brand colours with orange and red states;
  - pace and reset lines;
  - the expected-pace tick;
  - threshold ticks;
  - a dashed bar for projected values;
  - the state footer;
  - click-through to the provider's usage page;
  - accessibility labels.
- Views are built on open and released on close.
- **Size:** about 450 lines.
- **Done when:** checked by eye in light and dark mode, and footprint is unchanged after opening and closing the menu 20 times.

**S7 — Status item styles and menu actions.**
- Contents:
  - the three status item styles from §7.3, each cached and redrawn only when its value changes, with a red
    overlay at 95% or more;
  - the optional pace sign in the menu bar;
  - Refresh, Providers ▸, Menu bar style ▸, Launch at login (`SMAppService`) and the workday pacing choice.
- **Size:** about 300 lines.
- **Done when:** Phase 1 exit criteria in §10 are met. **This is the first build to use day to day.**

**Phase 2: iPhone sync, alerts, auto-pause**

**S8 — Auto-pause.**
- Contents:
  - detect the full app with `NSRunningApplication` and launch/terminate notifications;
  - suspend fetching, syncing and alerts while it runs;
  - a "Paused — QuotaKit is running" footer;
  - an immediate refresh when the full app quits.
- **Size:** about 80 lines.
- This comes before sync so the two apps never double-publish, even for a moment.

**S9 — SyncBridge.**
- Contents:
  - in `LiteCore`: `ProviderState` to `ProviderUsageEnvelope` (windows, identities, `pace`, `quotaWarnings`);
  - in `LiteCore`: a content hash that excludes timestamps;
  - in the app: lazy `CloudSyncManager`;
  - in the app: a write on change, on state transitions, or on the 30-minute heartbeat;
  - in the app: a persisted hash, deletes when a provider is disabled, and Unpublish from iPhone;
  - in the app: a Sync to iPhone toggle.
- **Tests:** envelope snapshots that the iOS decoder accepts, using a round trip through
  `CloudSyncConstants.makeJSONDecoder` and the `SnapshotCache` ghost rule; identity strings checked
  byte-for-byte against `AccountIdentityComputer` outputs.
- **Size:** about 350 lines.
- **Done when:** Lite's cards show up on the iPhone, merge with the full app's cards for the same account, and
  nothing is written when nothing changed.

**S10 — Alerts.**
- Contents:
  - in `LiteCore`: a transition detector covering depleted, restored and warning thresholds, fed only fetched
    data, with persisted last state;
  - in the app: a port of `QuotaTransitionWriter`, keeping the same zones, record names and debounce;
  - Mac banners through `UNUserNotificationCenter` with the logo attached;
  - the Alerts ▸ menu.
- **Tests:** threshold crossing, restart without re-alerting, a projected reset not alerting, and the hour-bucket
  record names matching the full app.
- **Size:** about 350 lines.
- **Done when:** a forced crossing gives exactly one iPhone push and one Mac banner, and nothing fires while paused.

**Phase 3: Antigravity**

**S11 — Antigravity probe.**
- Contents:
  - kernel process discovery (`proc_listallpids`, `KERN_PROCARGS2`, `PROC_PIDFDSOCKETINFO`);
  - a cached endpoint;
  - a loopback-only TLS trust;
  - `RetrieveUserQuotaSummary` with fallbacks to `GetUserStatus` and `GetCommandModelConfigs`;
  - a launch and terminate observer;
  - the two-group card layout;
  - alerts and sync, which come for free.
- **Tests:** classification of command lines and the three response parsers, using fixtures from the full app.
- **Size:** about 450 lines.
- **Done when:** data is live with Antigravity open, the "Not running" state looks clean, and no subprocess is ever
  spawned (checked with `ps` during refresh).

**Phase 4: finish**

**S12 — Hardening.**
- Contents:
  - `Scripts/lite-soak.sh`, `lite-fixture-sync.sh` and `lite-drift-check.sh`;
  - a `QuotaKitLite` build-and-test job on a macOS runner in `.github/workflows/ci.yml`, run only when
    `QuotaKitLite/**` or `Shared/**` changes (Linux can't build `Shared/`; see the start of §13);
  - a binary-size gate;
  - a short git SHA in the About line.
- **Done when:** a week of daily use with no unexplained prompts, stale data or energy flags; then mark this
  doc `done`.

**Order and parallelism:** S0 → S1 → S2. After S2, S3, S4 and S5 are independent. S6 and S7 need S2. S8 needs S7.
S9 needs S8. S10 needs S9. S11 can start any time after S2; its sync and alerts work once S9 and S10 land.

**Total:** about 3.2k lines across 13 slices.
