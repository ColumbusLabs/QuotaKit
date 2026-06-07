# Launch Inventory

Generated: 2026-06-07  
Scope: repository inventory for turning the current `CodexBar` / `CodexBarMobile` fork into the privacy-first QuotaKit product. This document records the upstream baseline and the first QuotaKit safety decisions.

## Product Decisions To Preserve

- Mac collector app remains free and open source.
- iOS companion app is free to install with a paid Pro tier.
- Pro is a StoreKit 2 non-consumable lifetime unlock.
- Product ID: `com.columbuslabs.quotakit.pro.lifetime`.
- Launch/founder price copy: `$4.99 lifetime`.
- No subscription in v1.
- No hosted backend in v1.
- No analytics by default.
- No credential sync ever.
- MIT license notices and upstream attribution must stay intact.
- Provider credentials, access tokens, refresh tokens, API keys, cookies, browser sessions, and raw provider responses must never be synced to CloudKit or iOS.

## Repository Baseline

- Intended fork remote: `https://github.com/ColumbusLabs/QuotaKit.git`.
- Seed/source branch inspected locally: upstream `o1xhack/CodexBar-Mobile` `mobile-dev`, commit `ad04882801040a1c585bd156fc442cd0434452d1`.
- Local `origin` is `ColumbusLabs/QuotaKit`; that remote currently has no refs from `git ls-remote`.
- Upstream remote is `https://github.com/o1xhack/CodexBar-Mobile.git`.

## 1. Targets And Packages

### Root SwiftPM package

`Package.swift` defines the macOS collector/menu bar app, CLI, shared sync library, widget binary, helper tools, macros, and tests.

| Product or target | Type | Purpose |
| --- | --- | --- |
| `CodexBarCore` | library target | Provider models, fetchers, settings readers, browser cookie access, keychain helpers, cost scanning, widget snapshot storage, config parsing. |
| `CodexBarCLI` | executable target | CLI wrapper for usage, cost, config, diagnostics, snapshots, serve routes. Also packaged for Linux. |
| `CodexBar` | macOS executable target | Main menu bar collector/dashboard app. Reads local provider data, runs providers, persists local/widget state, and pushes sanitized snapshots to iCloud when enabled. |
| `CodexBarSync` | target rooted at `Shared/` | Shared Mac/iOS CloudKit wire models, JSON codec helpers, CloudKit manager, notification-zone parsing, compression. |
| `CodexBarWidget` | macOS executable target | WidgetKit extension code source used by the macOS widget extension project. Reads local app-group snapshot JSON. |
| `CodexBarClaudeWatchdog` | macOS helper executable | Helper wrapper around Claude CLI execution. |
| `CodexBarClaudeWebProbe` | macOS helper executable | Claude web endpoint probing helper. |
| `CodexBarMacros` / `CodexBarMacroSupport` | macro/support targets | Provider registration macro support. |
| `CodexBarTests` | macOS test target | Main macOS test suite for providers, sync, widgets, config, CLI, costs. |
| `CodexBarLinuxTests` | Linux test target | Linux-compatible CLI/core tests. |

Dependencies include Sparkle, Commander, Swift Crypto, Swift Log, Swift Syntax, KeyboardShortcuts, Vortex, and SweetCookieKit.

### iOS Xcode project

`CodexBarMobile/project.yml` is the XcodeGen source for the iOS app.

| Target | Bundle ID | Purpose |
| --- | --- | --- |
| `CodexBarMobile` | `com.o1xhack.codexbar.mobile` | Main iOS companion app. Reads CloudKit/KVS snapshots, stores local SwiftData cost ledger, shows synced cards, notifications, diagnostics, share cards, utilization/cost views. |
| `CodexBarMobilePushExtension` | `com.o1xhack.codexbar.mobile.pushextension` | Notification Service Extension that enriches CloudKit quota transition notifications. |
| `CodexBarSync` | `com.o1xhack.codexbar.sync` | iOS framework wrapping shared `../Shared` sync layer. |
| `CodexBarMobileTests` | `com.o1xhack.codexbar.mobile.tests` | iOS unit tests. |
| `CodexBarMobileUITests` | `com.o1xhack.codexbar.mobile.uitests` | iOS UI tests. |

`CodexBarMobile/Package.swift` also defines a standalone package for `CodexBarSync`, `CodexBarMobile`, and `CodexBarMobileTests`, but the signed app/archive path is the Xcode project.

### macOS Widget extension project

`WidgetExtension/project.yml` defines `CodexBarWidgetExtension`, a macOS app extension with bundle ID `$(CODEXBAR_WIDGET_BUNDLE_ID)`. It sources `../Sources/CodexBarWidget` and reads `CodexBarCore` data.

## 2. Current CloudKit, KVS, Subscriptions, And Entitlements

### Upstream identifiers found during inventory

These were the active upstream/fork identifiers at inventory time. They must not be used for QuotaKit-owned release builds.

| Surface | Current value |
| --- | --- |
| CloudKit container | `iCloud.com.o1xhack.codexbar` |
| Legacy KVS identifier | `$(TeamIdentifierPrefix)com.codexbar.shared` on iOS; `3TUERHN53E.com.codexbar.shared` in macOS packaging by default |
| iOS app bundle | `com.o1xhack.codexbar.mobile` |
| iOS push extension bundle | `com.o1xhack.codexbar.mobile.pushextension` |
| macOS release bundle | `com.o1xhack.codexbar` |
| macOS debug bundle | `com.o1xhack.codexbar.debug` |
| macOS app group | `group.com.o1xhack.codexbar` in packaging, while `AppGroupSupport` computes `group.<team>.com.steipete.codexbar` |
| Current signing team hardcode | `3TUERHN53E` |
| Upstream legacy team hardcode | `Y5PE65HELJ` |

### Entitlements

- `CodexBarMobile/CodexBarMobile/CodexBarMobile.entitlements`
  - `aps-environment = development`
  - `com.apple.developer.icloud-container-environment = Production`
  - `com.apple.developer.icloud-container-identifiers = iCloud.com.o1xhack.codexbar`
  - `com.apple.developer.icloud-services = CloudKit`
  - `com.apple.developer.ubiquity-kvstore-identifier = $(TeamIdentifierPrefix)com.codexbar.shared`
- `CodexBarMobile/CodexBarMobilePushExtension/PushExtension.entitlements`
  - CloudKit Production container and KVS identifier only. No `aps-environment` in the extension entitlement file.
- macOS entitlements are generated by `Scripts/package_app.sh` into `.build/entitlements/CodexBar.entitlements` and `.build/entitlements/CodexBarWidget.entitlements`.
  - Main app gets application identifier, team identifier, app group, KVS ID, CloudKit service, CloudKit container, Production environment, and optional `get-task-allow`.
  - Widget gets sandbox and app group.

### Record zones and record types

Defined in `Shared/iCloud/CloudConstants.swift`.

| Zone | Record type | Writer | Reader | Purpose |
| --- | --- | --- | --- | --- |
| `DeviceSnapshotsZone` | `DeviceSnapshot` | Mac | iOS | Legacy per-device monolithic snapshot. Payload is JSON `SyncedUsageSnapshot` stored in `payload`. |
| `DeviceProvidersZone` | `DeviceProviderSnapshot` | Mac | iOS | Current per-provider incremental sync. One record per `(deviceID, providerID, accountEmail)`. Payload is zlib-compressed JSON `ProviderUsageEnvelope` stored in `payload`. |
| `DeviceProvidersZone` | `ProviderAccountLinkage` | iOS | iOS | User-confirmed account merge/unmerge records. Record name format `linkage-{UUID}`. |
| default private database zone | `DeviceSnapshot` | older Macs | iOS fallback | Pre-custom-zone legacy fallback. |
| `QuotaTransitionsZone` | `QuotaTransition` | legacy only | iOS cleanup only | Legacy Build 42-49 transition zone; no new records should be written. |
| `Quota-{providerID}-{state}Zone` | `QuotaTransition` | Mac | iOS/NSE | Per-provider/state visible push triggers for `depleted`, `restored`, and `warning`. |

Current top-level `DeviceSnapshot` fields:

- `deviceName`
- `deviceID`
- `appVersion`
- `syncTimestamp`
- `payload`

Current top-level `DeviceProviderSnapshot` fields:

- `deviceID`
- `deviceName`
- `providerID`
- `providerName`
- `accountEmail`
- `lastUpdated`
- `encodingVersion`
- `payload`

Current top-level `QuotaTransition` fields:

- `providerName`
- `providerID`
- `state`
- `transitionAt`
- `deviceID`
- optional `accountEmail`

Current top-level `ProviderAccountLinkage` fields:

- `providerID`
- `linkedIdentifiers`
- `confirmedAt`
- `confirmedFromDeviceID`
- `unmerge`

### Subscriptions

| Subscription | ID format | Type | Purpose |
| --- | --- | --- | --- |
| Provider-zone silent push | `device-provider-zone-sub` | `CKRecordZoneSubscription` on `DeviceProvidersZone` | Wakes iOS silently when Mac upserts/deletes per-provider records. |
| Quota transition visible pushes | `quota-{providerID}-{state}-sub` | `CKRecordZoneSubscription` on each `Quota-{providerID}-{state}Zone` | Visible alert fallback body per provider/state; NSE enriches warning/depleted/restored copy. |
| Legacy cleanup IDs | `quota-transition-zone-sub`, `quota-transition-depleted`, `quota-transition-restored` | deleted on setup | Removes older subscription designs. |

`QuotaProviderList.providers.count x 3` subscriptions are desired today. Comments say this was 120 subscriptions in iOS 1.7.0.

### CloudKit environment risks

- All current release/debug instructions insist on `Production` CloudKit even for Xcode debug iOS installs.
- Moving to QuotaKit cannot safely change only one side of `containerIdentifier`; Mac, iOS app, push extension, provisioning, CloudKit Dashboard, and tests must move together.
- The current comments label record types, zones, record-name formats, and JSON codec as wire contracts. Treat the new product as a fresh container migration unless there is a deliberate legacy import path.

## 3. Mac-To-iOS Sync Flow

1. User enables providers in Mac Settings.
2. Mac `UsageStore` refreshes enabled providers using CLI, OAuth, API key, browser cookie, local file, or web fetcher paths.
3. `Sources/CodexBar/Sync/SyncCoordinator.swift` observes `UsageStore.snapshots`, `UsageStore.errors`, `UsageStore.tokenSnapshots`, `settings.iCloudSyncEnabled`, and Codex account selection.
4. `SyncCoordinator.pushCurrentSnapshot()` builds sanitized `ProviderUsageSnapshot` values:
   - provider IDs and display names
   - usage windows, reset descriptions, quota warning config
   - account email / login method labels
   - cost summaries, budget fields, utilization history
   - provider-specific rich display models
   - app/mobile version, device name, stable device ID
5. `CloudSyncManager.pushSnapshot()` writes the legacy monolithic `DeviceSnapshot` to `DeviceSnapshotsZone` and also writes legacy KVS key `com.codexbar.usage.snapshot`.
6. `SyncCoordinator.buildPerProviderDelta()` builds `ProviderUsageEnvelope` records and diffs by stable JSON hash.
7. `CloudSyncManager.pushPerProviderRecords()` writes changed `DeviceProviderSnapshot` records to `DeviceProvidersZone`, chunked to 200-record batches.
8. `SyncCoordinator` computes stale record names and calls `deletePerProviderRecords()` to clean disabled or drifted provider records.
9. iOS `CloudSyncReader` calls `CloudSyncManager.fetchPerProviderZoneChanges()` for incremental changes or `fetchAllDeviceSnapshots()` for full reads.
10. iOS merges `DeviceProvidersZone`, `DeviceSnapshotsZone`, and default-zone snapshots with priority `providerZone > customZone > defaultZone`.
11. `CloudSyncReader.persistToSwiftData()` mirrors per-device CloudKit snapshots into SwiftData while the old observable path still drives views.
12. Quota notifications are written from Mac as `QuotaTransition` records in per-provider/state zones, then delivered to iOS via CloudKit subscriptions.

The iOS app should not fetch provider endpoints directly for v1 QuotaKit. Current iOS production code appears to read CloudKit, KVS, SwiftData/local demo data, notification payloads, StoreKit not yet implemented, and local share-card/photo-library surfaces.

## 4. Sensitive Data Read/Store Inventory

This section focuses on production code paths that read or persist credentials, cookies, API keys, OAuth credentials, browser storage, keychain items, or local usage logs. Tests and docs also mention these terms but are not runtime credential paths.

### Cross-cutting credential and storage primitives

| File | Sensitive surface |
| --- | --- |
| `Sources/CodexBarCore/KeychainCacheStore.swift` | Generic keychain-backed cache store. |
| `Sources/CodexBarCore/KeychainAccessGate.swift` | Keychain access gating state. |
| `Sources/CodexBarCore/KeychainAccessPreflight.swift` | Keychain preflight/probe helper. |
| `Sources/CodexBarCore/KeychainNoUIQuery.swift` | No-UI keychain query helper. |
| `Sources/CodexBar/KeychainMigration.swift` | Migrates legacy keychain entries. |
| `Sources/CodexBar/KeychainPromptCoordinator.swift` | Coordinates keychain prompt behavior. |
| `Sources/CodexBarCore/BrowserDetection.swift` | Browser profile discovery. |
| `Sources/CodexBarCore/BrowserCookieAccessGate.swift` | Browser-cookie permission/access gating. |
| `Sources/CodexBarCore/BrowserCookieImportOrder.swift` | Browser import ordering. |
| `Sources/CodexBarCore/Providers/ProviderCookieSource.swift` | Cookie source enum/policy. |
| `Sources/CodexBarCore/Providers/ProviderTokenResolver.swift` | Resolves provider tokens from env/config/token accounts. |
| `Sources/CodexBarCore/Providers/ProviderSettingsSnapshot.swift` | Snapshot of provider settings, including token/cookie-bearing fields. |
| `Sources/CodexBarCore/TokenAccounts.swift` | Stores token-account models. |
| `Sources/CodexBarCore/TokenAccountSupport.swift` | Token-account support metadata. |
| `Sources/CodexBarCore/TokenAccountSupportCatalog+Data.swift` | Catalog of providers supporting token-account storage. |
| `Sources/CodexBarCore/Config/CodexBarConfig.swift` | `~/.codexbar/config.json` model, including provider tokens/cookies/settings. |
| `Sources/CodexBarCore/Config/ProviderConfigEnvironment.swift` | Environment/config bridging for provider secrets. |
| `Sources/CodexBar/SettingsStore+Config.swift` | App settings to config bridge. |
| `Sources/CodexBar/SettingsStore+ConfigPersistence.swift` | Persists config to disk. |
| `Sources/CodexBar/SettingsStore+TokenAccounts.swift` | UI-side token account persistence. |
| `Sources/CodexBarCLI/CLIConfigCommand.swift` | CLI `set-api-key` and provider config commands. |
| `Sources/CodexBarCLI/TokenAccountCLI.swift` | CLI token-account management. |
| `Sources/CodexBarCore/CookieHeaderCache.swift` | Stores cached cookie headers locally. |
| `Sources/CodexBar/CookieHeaderStore.swift` | UI store for manual cookie headers. |
| `Sources/CodexBarCore/CookieHeaderNormalizer.swift` | Normalizes pasted cookie headers. |

### Provider credential/cookie/API-key files

| Provider or category | Files |
| --- | --- |
| Codex / OpenAI web | `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthCredentials.swift`, `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift`, `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexTokenRefresher.swift`, `Sources/CodexBarCore/Providers/Codex/CodexOpenAIWorkspaceResolver.swift`, `Sources/CodexBarCore/Providers/Codex/CodexWebDashboardStrategy.swift`, `Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardBrowserCookieImporter.swift`, `Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardFetcher.swift`, `Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardWebsiteDataStore.swift`, `Sources/CodexBar/Providers/Codex/CodexSettingsStore.swift`, `Sources/CodexBar/Providers/Codex/CodexProviderImplementation.swift`, `Sources/CodexBar/UsageStore+OpenAIWeb.swift`, `Sources/CodexBar/ManagedCodexAccountService.swift`, `Sources/CodexBarCore/ManagedCodexAccountStore.swift`. |
| OpenAI API / Azure OpenAI | `Sources/CodexBarCore/Providers/OpenAI/OpenAIAPISettingsReader.swift`, `Sources/CodexBarCore/Providers/OpenAI/OpenAIAPIUsageFetcher.swift`, `Sources/CodexBarCore/Providers/OpenAI/OpenAIAPICreditBalanceFetcher.swift`, `Sources/CodexBar/Providers/OpenAI/OpenAIAPISettingsStore.swift`, `Sources/CodexBarCore/Providers/AzureOpenAI/AzureOpenAISettingsReader.swift`, `Sources/CodexBarCore/Providers/AzureOpenAI/AzureOpenAIUsageFetcher.swift`, `Sources/CodexBar/Providers/AzureOpenAI/AzureOpenAISettingsStore.swift`. |
| Claude | `Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/*`, `Sources/CodexBarCore/Providers/Claude/ClaudeCredentialRouting.swift`, `Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift`, `Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift`, `Sources/CodexBarCore/Providers/Claude/ClaudeAdminAPISettingsReader.swift`, `Sources/CodexBarCore/Providers/Claude/ClaudeAdminAPIUsageFetcher.swift`, `Sources/CodexBar/Providers/Claude/ClaudeSettingsStore.swift`, `Sources/CodexBar/Providers/Claude/ClaudeProviderImplementation.swift`, `Sources/CodexBar/UsageStore+ClaudeDebug.swift`. |
| Browser-cookie providers | `Sources/CodexBarCore/Providers/Abacus/AbacusCookieImporter.swift`, `Sources/CodexBarCore/Providers/Alibaba/AlibabaCodingPlanCookieImporter.swift`, `Sources/CodexBarCore/Providers/Alibaba/AlibabaTokenPlanCookieHeader.swift`, `Sources/CodexBarCore/Providers/CommandCode/CommandCodeCookieHeader.swift`, `Sources/CodexBarCore/Providers/CommandCode/CommandCodeCookieImporter.swift`, `Sources/CodexBarCore/Providers/Grok/GrokCookieImporter.swift`, `Sources/CodexBarCore/Providers/Kimi/KimiCookieHeader.swift`, `Sources/CodexBarCore/Providers/Kimi/KimiCookieImporter.swift`, `Sources/CodexBarCore/Providers/Manus/ManusCookieHeader.swift`, `Sources/CodexBarCore/Providers/Manus/ManusCookieImporter.swift`, `Sources/CodexBarCore/Providers/MiMo/MiMoCookieImporter.swift`, `Sources/CodexBarCore/Providers/MiniMax/MiniMaxCookieHeader.swift`, `Sources/CodexBarCore/Providers/MiniMax/MiniMaxCookieImporter.swift`, `Sources/CodexBarCore/Providers/Mistral/MistralCookieImporter.swift`, `Sources/CodexBarCore/Providers/OpenCode/OpenCodeCookieImporter.swift`, `Sources/CodexBarCore/Providers/OpenCode/OpenCodeWebCookieSupport.swift`, `Sources/CodexBarCore/Providers/Perplexity/PerplexityCookieHeader.swift`, `Sources/CodexBarCore/Providers/Perplexity/PerplexityCookieImporter.swift`, `Sources/CodexBarCore/Providers/T3Chat/T3ChatUsageFetcher.swift`, `Sources/CodexBarCore/Providers/Windsurf/WindsurfDevinSessionImporter.swift`, `Sources/CodexBarCore/Providers/Windsurf/WindsurfWebFetcher.swift`, `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift`, `Sources/CodexBarCore/Providers/Factory/FactoryLocalStorageImporter.swift`, `Sources/CodexBarCore/Providers/Factory/FactoryStatusProbe.swift`, `Sources/CodexBarCore/Providers/Augment/AugmentStatusProbe.swift`, `Sources/CodexBarCore/Providers/Augment/AugmentSessionKeepalive.swift`, `Sources/CodexBarCore/Providers/Amp/AmpUsageFetcher.swift`. |
| LocalStorage/session importers | `Sources/CodexBarCore/Providers/Factory/FactoryLocalStorageImporter.swift`, `Sources/CodexBarCore/Providers/MiniMax/MiniMaxLocalStorageImporter.swift`, `Sources/CodexBarCore/Providers/Windsurf/WindsurfDevinSessionImporter.swift`. |
| Token/API-key stores | `Sources/CodexBar/ZaiTokenStore.swift`, `Sources/CodexBar/KimiTokenStore.swift`, `Sources/CodexBar/KimiK2TokenStore.swift`, `Sources/CodexBar/MiniMaxAPITokenStore.swift`, `Sources/CodexBar/MiniMaxCookieStore.swift`, `Sources/CodexBar/CopilotTokenStore.swift`, `Sources/CodexBar/SyntheticTokenStore.swift`. |
| Token/API-key readers/fetchers | `Sources/CodexBarCore/Providers/Alibaba/AlibabaCodingPlanSettingsReader.swift`, `Sources/CodexBarCore/Providers/Alibaba/AlibabaTokenPlanSettingsReader.swift`, `Sources/CodexBarCore/Providers/Bedrock/BedrockCredentialResolver.swift`, `Sources/CodexBarCore/Providers/Bedrock/BedrockProfileCredentialProvider.swift`, `Sources/CodexBarCore/Providers/Bedrock/BedrockSettingsReader.swift`, `Sources/CodexBarCore/Providers/Codebuff/CodebuffSettingsReader.swift`, `Sources/CodexBarCore/Providers/Copilot/CopilotDeviceFlow.swift`, `Sources/CodexBarCore/Providers/Copilot/CopilotUsageFetcher.swift`, `Sources/CodexBarCore/Providers/Crof/CrofSettingsReader.swift`, `Sources/CodexBarCore/Providers/DeepSeek/DeepSeekSettingsReader.swift`, `Sources/CodexBarCore/Providers/Deepgram/DeepgramSettingsReader.swift`, `Sources/CodexBarCore/Providers/Doubao/DoubaoSettingsReader.swift`, `Sources/CodexBarCore/Providers/ElevenLabs/ElevenLabsSettingsReader.swift`, `Sources/CodexBarCore/Providers/Groq/GroqSettingsReader.swift`, `Sources/CodexBarCore/Providers/Kilo/KiloBearerTokenResolver.swift`, `Sources/CodexBarCore/Providers/Kilo/KiloSettingsReader.swift`, `Sources/CodexBarCore/Providers/Kimi/KimiSettingsReader.swift`, `Sources/CodexBarCore/Providers/KimiK2/KimiK2SettingsReader.swift`, `Sources/CodexBarCore/Providers/LLMProxy/LLMProxySettingsReader.swift`, `Sources/CodexBarCore/Providers/Manus/ManusSettingsReader.swift`, `Sources/CodexBarCore/Providers/MiniMax/MiniMaxAPISettingsReader.swift`, `Sources/CodexBarCore/Providers/MiniMax/MiniMaxSettingsReader.swift`, `Sources/CodexBarCore/Providers/Moonshot/MoonshotSettingsReader.swift`, `Sources/CodexBarCore/Providers/OpenRouter/OpenRouterSettingsReader.swift`, `Sources/CodexBarCore/Providers/StepFun/StepFunSettingsReader.swift`, `Sources/CodexBarCore/Providers/Synthetic/SyntheticSettingsReader.swift`, `Sources/CodexBarCore/Providers/Venice/VeniceSettingsReader.swift`, `Sources/CodexBarCore/Providers/VertexAI/VertexAIOAuth/*`, `Sources/CodexBarCore/Providers/Warp/WarpSettingsReader.swift`, `Sources/CodexBarCore/Providers/Zai/ZaiSettingsReader.swift`. |
| Local usage logs / cost scans | `Sources/CodexBarCore/PiSessionCostScanner.swift`, `Sources/CodexBarCore/PiSessionCostCache.swift`, `Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift`, `Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+Claude.swift`, `Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+CacheHelpers.swift`, `Sources/CodexBarCore/Vendored/CostUsage/CostUsageCache.swift`, `Sources/CodexBarCore/Providers/Grok/GrokLocalSessionScanner.swift`, `Scripts/cost_jsonl_shape_survey.swift`. |
| Release secrets | `Scripts/load-release-secrets.sh`, `Scripts/sign-and-notarize.sh`, `Scripts/make_appcast.sh`, `Scripts/release.sh`, `Scripts/upload_ios_testflight.sh`, `.quotakit-release.local.env.example`, `.mac-release.env`. |

### iOS local data files

The iOS app stores synced/sanitized data locally, not provider credentials:

- `CodexBarMobile/CodexBarMobile/Storage/CostLedgerModels.swift`
- `CodexBarMobile/CodexBarMobile/Storage/CostLedgerService.swift`
- `CodexBarMobile/CodexBarMobile/Storage/SwiftDataBridge.swift`
- `CodexBarMobile/CodexBarMobile/Storage/ModelContainerFactory.swift`
- `CodexBarMobile/CodexBarMobile/Storage/SwiftDataSchema.swift`
- `CodexBarMobile/CodexBarMobile/Models/SnapshotCache.swift`
- `CodexBarMobile/CodexBarMobile/Models/SyncedUsageData.swift`

Launch risk: these can contain provider/account labels, emails, quota data, token counts, spend, history, and device names. That is acceptable for sanitized snapshots but should be disclosed and controllable.

## 5. Network Endpoints And Endpoint Classes

The provider surface is broad. For launch, Codex/OpenAI and CloudKit are the critical paths to audit first.

### Codex/OpenAI launch-critical endpoints

| Endpoint | File(s) | Auth/source |
| --- | --- | --- |
| `https://chatgpt.com/backend-api/wham/usage` | `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift`, `Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardFetcher.swift`, `docs/codex.md` | Codex OAuth bearer token or ChatGPT cookies depending path. |
| `https://auth.openai.com/oauth/token` | `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexTokenRefresher.swift` | OAuth refresh token from local Codex auth. |
| `https://chatgpt.com/backend-api/accounts` | `Sources/CodexBarCore/Providers/Codex/CodexOpenAIWorkspaceResolver.swift` | OAuth bearer token. |
| `https://chatgpt.com/codex/cloud/settings/analytics#usage` | `Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardFetcher.swift` | WebView/cookie dashboard scrape. |
| `https://chatgpt.com/backend-api/me` | `Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardFetcher.swift` | ChatGPT cookies. |
| `https://chatgpt.com/api/auth/session` | `Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardFetcher.swift` | ChatGPT cookies. |
| Browser cookie locations for `chatgpt.com` | `Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardBrowserCookieImporter.swift`, `docs/codex.md` | SweetCookieKit reads/decrypts browser cookies; Safari may require Full Disk Access; Chromium safe-storage keychain prompts may occur. |
| Local Codex auth file | `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthCredentials.swift` | `~/.codex/auth.json` or `CODEX_HOME` equivalent. |
| Local Codex config | `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift` | `~/.codex/config.toml`, used to resolve ChatGPT base URL override. |
| Local Codex CLI/session execution | `Sources/CodexBarCore/Providers/Codex/CodexCLISession.swift`, `Sources/CodexBar/Providers/Codex/UsageStore+CodexRefresh.swift` | Runs local CLI/probes; may read CLI-managed local state. |

### Other provider endpoint classes

Representative endpoint classes in `Sources/CodexBarCore/Providers`:

- OAuth APIs: Codex, Claude, Vertex AI, Antigravity, Copilot device flow.
- Browser-cookie/web APIs: Claude web, Cursor, OpenCode, OpenCode Go, Command Code, T3 Chat, Amp, Augment, Abacus, Grok, Kimi, Manus, MiMo, MiniMax, Mistral, Perplexity, Windsurf, Factory/Droid.
- API-key APIs: OpenAI API, Azure OpenAI, DeepSeek, Deepgram, Doubao, ElevenLabs, GroqCloud, Kilo, Kimi K2, LLM Proxy, Moonshot, OpenRouter, Synthetic, Venice, Warp, Crof, Codebuff, Alibaba Token/Coding Plan, AWS Bedrock.
- Local CLI/file probes: Codex, Claude, Gemini, Antigravity, Kiro, JetBrains, Vertex AI local logs, Grok local sessions.

Recommended v1 QuotaKit launch posture: enable only explicitly selected Mac providers; keep browser-cookie providers off by default and label them high-risk/advanced; ensure iOS has no provider endpoint code path.

## 6. Widget Architecture

### macOS-only today

- `Sources/CodexBarWidget/*` is a WidgetKit extension implementation for macOS.
- `WidgetExtension/project.yml` packages it as `CodexBarWidgetExtension`.
- `Sources/CodexBar/UsageStore+WidgetSnapshot.swift` writes a sanitized `WidgetSnapshot` JSON file whenever app state changes.
- `Sources/CodexBarCore/WidgetSnapshot.swift` defines `WidgetSnapshotStore` and `WidgetSelectionStore`.
- `Sources/CodexBarCore/AppGroupSupport.swift` resolves app-group containers and fallback paths.
- `Scripts/package_app.sh` bundles/signs the widget appex into the Mac app and generates widget entitlements.

### Widget data model

`WidgetSnapshot` includes:

- provider
- updated timestamp
- primary/secondary/tertiary windows
- usage rows
- credits remaining
- Codex code-review remaining percent
- token/cost summaries
- daily usage points
- enabled provider list

It does not contain provider credentials by design.

### Supported providers in widgets

`ProviderChoice` currently supports Codex, Claude, Gemini, Alibaba, Alibaba Token Plan, Antigravity, z.ai, Copilot, MiniMax, Kilo, OpenCode, and OpenCode Go. Many providers are explicitly unsupported in widgets.

### iOS readiness

The existing widget extension is macOS-oriented:

- It reads local app-group JSON written by the Mac app, not iOS CloudKit/SwiftData state.
- `WidgetExtension/project.yml` is `platform: macOS`.
- iOS Home Screen/Lock Screen widgets are not implemented as iOS targets yet.

QuotaKit Pro widget work should create iOS widget targets that read sanitized iOS-side cached snapshots/SwiftData, not Mac app-group files and not provider credentials.

## 7. Build, Release, Signing, Notarization, Updates

### Local commands

- `make build` -> `swift build`
- `make test` -> `swift test`
- `make lint` / `make check` -> `./Scripts/lint.sh lint`
- `make start` / `make restart` -> `./Scripts/compile_and_run.sh`
- `make release` -> `./Scripts/package_app.sh release`

### Mac packaging and update flow

- `Scripts/package_app.sh`
  - Builds SwiftPM products.
  - Creates `CodexBar.app`.
  - Generates Info.plist and entitlements.
  - Embeds CLI/helper/widget.
  - Configures Sparkle feed URL.
  - Hardcodes current product/bundle/team/container values.
- `Scripts/sign-and-notarize.sh`
  - Uses Developer ID identity `Developer ID Application: Yuxiao Wang (3TUERHN53E)`.
  - Requires App Store Connect key ID/issuer/key file or P8.
  - Requires Sparkle private key.
  - Builds universal by default.
  - Signs helper, widget, app with runtime/timestamp.
  - Submits to notarytool, staples, verifies Gatekeeper/stapler, runs direct launch test, packages dSYM.
- `Scripts/release.sh`
  - Phase 1: clean worktree, changelog/appcast checks, lint, optional tests, sign/notarize, tag, draft GitHub release.
  - Phase 2: publish draft, generate signed Sparkle appcast, commit/push `appcast.xml`, verify assets.
  - Hardcoded to `o1xhack/CodexBar-Mobile`, `mobile-dev`, `CodexBar`, and current release tag shape.
- `Scripts/make_appcast.sh`, `Scripts/verify_appcast.sh`, `Scripts/sparkle_helpers.sh`
  - Sparkle appcast generation/verification.
- `appcast.xml`
  - Current feed points to o1xhack and older steipete release entries.
- `docs/sparkle.md`, `docs/RELEASING.md`
  - Current release docs and assumptions.

### iOS release flow

- `Scripts/upload_ios_testflight.sh`
  - Runs lint.
  - Archives `CodexBarMobile/CodexBarMobile.xcodeproj`, scheme `CodexBarMobile`.
  - Exports/upload via Xcode cloud signing and App Store Connect destination.
  - Hardcodes team `3TUERHN53E`.
  - Does not use API-key auth for cloud signing because current notes say API key lacks required role.

### CI/release workflows

- `.github/workflows/ci.yml`
  - macOS lint/build/test with Xcode 26 fallback selection.
  - Linux CLI build/test/smoke.
- `.github/workflows/release-cli.yml`
  - Publishes CLI artifacts for Linux and macOS.
  - Contains upstream/homebrew-tap assumptions (`steipete/homebrew-tap`, `codexbar` formula/cask).
- `.github/workflows/release-mac-verify.yml`
  - Verifies published Mac release zips launch on clean macOS runner.
- `.github/workflows/upstream-monitor.yml`
  - Monitors `steipete/CodexBar` and `nguyenphutrong/quotio` style upstreams.

## 8. Existing Branding And Bundle Identifiers To Change

### Product/user-facing names and URLs

Must be changed before QuotaKit launch:

- App names: `CodexBar`, `CodexBarMobile`, `CodexBar iOS`, `CodexBarWidget`, `CodexBar CLI`.
- README/App Store copy that presents "CodexBar iOS" and "CodexBar".
- App Store ID URL: `https://apps.apple.com/app/id6760216772`.
- Website: `https://codexbarios.o1xhack.com`.
- Social link: `https://x.com/o1xhack`.
- GitHub URLs: `o1xhack/CodexBar-Mobile`, `steipete/CodexBar`.
- Share card QR URL: `CodexBarMobile/CodexBarMobile/Views/CyberShareCardView.swift` uses `https://codexbarios.o1xhack.com`.
- App copy in `CodexBarMobile/CodexBarMobile/ContentView.swift`, `OnboardingView.swift`, localizations, App Store metadata, screenshots, release notes, appcast, docs.
- Provider-logo/brand-heavy UI assets under `Sources/CodexBar/Resources/provider-icons` and mobile views. Provider icons can remain as provider identifiers if legally safe, but cannot become primary app branding.

### Bundle IDs, groups, containers, keys

Must be changed via a constants/config slice, not scattered edits:

- `com.o1xhack.codexbar`
- `com.o1xhack.codexbar.debug`
- `com.o1xhack.codexbar.mobile`
- `com.o1xhack.codexbar.mobile.pushextension`
- `com.o1xhack.codexbar.sync`
- `com.o1xhack.codexbar.mobile.tests`
- `com.o1xhack.codexbar.mobile.uitests`
- `group.com.o1xhack.codexbar`
- `group.com.o1xhack.codexbar.debug`
- `iCloud.com.o1xhack.codexbar`
- `3TUERHN53E.com.codexbar.shared`
- `$(TeamIdentifierPrefix)com.codexbar.shared`
- `com.codexbar.sync.deviceID`
- `com.codexbar.usage.snapshot`
- `~/.codexbar/config.json`
- `~/.codexbar-secrets/...`
- appcast/Sparkle keys and feed URLs
- `CodexBarTeamID` Info.plist key if renamed

QuotaKit placeholders for the implementation slice:

- public app name: `QuotaKit`
- internal product name: `QuotaKit`
- macOS bundle ID: `com.columbuslabs.quotakit.mac`
- iOS bundle ID: `com.columbuslabs.quotakit.ios`
- push extension ID: `com.columbuslabs.quotakit.ios.pushextension`
- shared sync framework ID: `com.columbuslabs.quotakit.sync`
- app group: `group.com.columbuslabs.quotakit`
- CloudKit container: `iCloud.com.columbuslabs.quotakit`
- KVS identifier: `$(TeamIdentifierPrefix)com.columbuslabs.quotakit.shared`
- StoreKit product: `com.columbuslabs.quotakit.pro.lifetime`

Final IDs should be confirmed against Apple Developer portal availability before release. No outside Apple team IDs, signing identities, Sparkle private-key paths, release repositories, or credential files should remain as active defaults.

## 9. Privacy And Security Risks

### Highest risks

1. Browser-cookie providers are broad and powerful. Automatic import may touch Safari/Chrome/Firefox/Chromium-family cookie stores and safe-storage keychain items. Keep all browser-cookie integrations advanced/off by default.
2. CloudKit payloads include account emails, login labels, cost/spend, token counts, utilization history, device names, provider IDs, and provider-specific account/workspace details. This is sanitized usage data, but still privacy-sensitive.
3. The current sync model writes to CloudKit when `iCloudSyncEnabled` is on and providers are enabled. QuotaKit must clearly separate "provider enabled locally" from "sync sanitized snapshots to iCloud."
4. Token-account support is broad. Ensure token values and raw headers never enter `ProviderUsageSnapshot`, `ProviderUsageEnvelope`, `WidgetSnapshot`, SwiftData, diagnostics, or share cards.
5. Local config `~/.codexbar/config.json` can contain API keys/cookies. Moving to QuotaKit should not migrate or upload this file without explicit user action.
6. The iOS app currently includes advanced full-sync views and notifications. Free mode must gate provider count/features without suppressing privacy/security/restore/troubleshooting screens.
7. Existing release scripts contain real team and release assumptions for o1xhack. Accidental use could publish/update the wrong product/feed.
8. `AppGroupSupport` currently computes `group.<team>.com.steipete.codexbar` while packaging uses `group.com.o1xhack.codexbar`. This deserves a dedicated audit before relying on widgets.
9. Logs/debug exports can disclose account emails, paths, provider availability, endpoint failures, and possibly snippets of provider responses if fetchers are not consistently redacted.
10. Provider affiliation risk is high: current copy leads with Codex/OpenAI/Claude/Cursor provider names and icons. QuotaKit must use neutral branding and avoid implying provider endorsement.

### Recommended mitigations

- Add `docs/security-model.md` defining a hard data boundary: Mac may read credentials only for enabled providers; iOS never receives credentials; CloudKit carries sanitized snapshots only.
- Add `docs/data-inventory.md` with field-level classification for every synced model and SwiftData/widget/share-card model.
- Introduce `ProductConfig` constants before rebranding and replace CloudKit/container/bundle/app-group references through it.
- Add tests that assert forbidden substrings/fields do not appear in CloudKit envelope JSON for representative providers.
- Add a debug "what is synced" screen/export that shows exactly which sanitized fields are uploaded.
- Make browser-cookie providers opt-in with explicit risk copy and no automatic enablement during onboarding.
- Keep manual refresh and one-provider free sync simple; avoid background provider enabling on iOS.
- Add a CloudKit delete/reset flow for user data in the new product.
- Keep logs redacted with `EmailRedaction` and expand redaction to tokens, cookie names/values, bearer headers, paths where needed.
- Remove or quarantine o1xhack/steipete release scripts until ProductConfig and signing constants are deliberately updated.

## 10. Proposed First Milestone Issue List

### Milestone 0: Inventory and safety baseline

1. Add launch inventory document.  
   Acceptance: `docs/launch-inventory.md` exists and covers targets, CloudKit, sync, secrets, endpoints, widgets, release scripts, branding, risks, and next issues.
2. Confirm product naming and ID authority.  
   Acceptance: final public name, internal name, bundle ID prefix, app group, CloudKit container, website/support/privacy URLs, and Apple team are approved.
3. Decide migration posture from `iCloud.com.o1xhack.codexbar`.  
   Acceptance: either fresh-container launch with no legacy migration, or a deliberate import/migration story.

### Milestone 1: Security and product config foundation

4. Add `docs/security-model.md`.  
   Acceptance: credential boundary, local-only provider reading, CloudKit snapshot contract, iOS data sources, browser-cookie risk, and no-backend/no-analytics posture are explicit.
5. Add `docs/data-inventory.md`.  
   Acceptance: every CloudKit, KVS, SwiftData, widget, share-card, log/debug, and local config field is classified.
6. Add `Shared/App/ProductConfig.swift` or equivalent.  
   Acceptance: public app name, internal product name, bundle IDs, app group, CloudKit container, KVS ID, URLs, and StoreKit product IDs live behind one constants layer.
7. Replace hardcoded CloudKit container references with `ProductConfig`.  
   Acceptance: `rg "iCloud.com.o1xhack.codexbar|com.o1xhack.codexbar|com.codexbar.shared"` shows only documented legacy references/tests after the change.
8. Add sync constants/JSON codec tests.  
   Acceptance: tests prove CloudKit IDs resolve from config and `CloudSyncConstants.makeJSONEncoder/Decoder` still round-trip Dates and key sync models.

### Milestone 2: StoreKit foundation

9. Add StoreKit 2 purchase service for `com.columbuslabs.quotakit.pro.lifetime`.  
   Acceptance: product load, purchase, entitlement listener, verification, restore, and errors are covered.
10. Add `ProEntitlementStore` with local entitlement cache.  
    Acceptance: cached Pro state restores offline display state but never grants credential access.
11. Add `FeatureGate` enum and feature checks.  
    Acceptance: gates cover unlimited providers, Home Screen widgets, Lock Screen widgets, notifications, cost dashboard, history charts, share cards, exports, advanced merging.
12. Add functional paywall/settings UI without final art.  
    Acceptance: locked/unlocked previews, restore purchases, `$4.99 lifetime` launch copy, no subscription copy/logic.
13. Add StoreKit test configuration.  
    Acceptance: local StoreKit tests/previews can simulate locked, purchased, restored, and failed states.

### Milestone 3: Free/Pro behavior

14. Implement iOS free-mode provider limit.  
    Acceptance: demo mode always works; real synced data shows one selected provider; privacy/security/restore/troubleshooting remain accessible.
15. Gate Pro iOS widgets and notifications.  
    Status: visible quota notifications are gated for Pro, silent CloudKit sync remains free, and locked cleanup removes managed quota-alert subscriptions. Home Screen and Lock Screen widgets are still pending.
    Acceptance: widgets/notifications explain Pro requirement without reading credentials or creating provider fetch paths on iOS.
16. Gate cost dashboard, history, share cards, exports, and advanced merges.  
    Status: complete for existing iOS surfaces. Free real-data mode shows locked states or suppresses advanced controls; Pro and demo mode keep the full current feature surface.
    Acceptance: Pro sees full features; free sees calm locked states and useful basics.

### Milestone 4: Branding and release readiness

17. Rebrand app/UI/docs/assets while preserving MIT attribution.  
    Acceptance: no primary branding uses Codex/OpenAI/Claude/Cursor/Anthropic/provider logos or implies affiliation.
18. Replace signing/release scripts with QuotaKit-safe placeholders.  
    Acceptance: scripts cannot publish to o1xhack/steipete feeds/releases by accident.
19. Provision Apple identifiers and CloudKit schema.  
    Acceptance: new IDs exist in Apple Developer portal; dev and production CloudKit environments are understood; entitlements match.
20. Add privacy disclosure and data deletion controls.  
    Acceptance: user can see synced data classes and clear local/CloudKit state.

## Stop Point

Per the launch plan, stop here after this inventory. Do not begin rebranding, ProductConfig, data-inventory, security-model, StoreKit, entitlement, or code changes until explicitly approved.
