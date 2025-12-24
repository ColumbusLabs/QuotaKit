---
summary: "Antigravity provider notes: local LSP probing, quota parsing, and UI mapping."
read_when:
  - Adding or modifying the Antigravity provider
  - Debugging Antigravity port detection or quota parsing
  - Adjusting Antigravity menu labels or model mapping
---

# Antigravity provider notes

CodexBar treats Antigravity as a local-provider quota source. Data is pulled from the Antigravity language server running on the machine (no Google/Gemini API usage here). The provider is modeled after the AntigravityQuotaWatcher extension behavior and is intentionally conservative because the APIs are internal and may change.

## Data source overview
- Process detection: scan `ps -ax -o pid=,command=` for `language_server_macos` with Antigravity markers.
  - Marker heuristics: `--app_data_dir antigravity` OR a path containing `/antigravity/`.
  - Extract flags: `--csrf_token` (required), `--extension_server_port` (HTTP fallback).
- Port discovery: `lsof -nP -iTCP -sTCP:LISTEN -p <pid>` to list all listening ports.
- Connect port selection: probe each listening port with:
  - POST `https://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/GetUnleashData`
  - Header: `X-Codeium-Csrf-Token: <token>` + `Connect-Protocol-Version: 1`
  - First 200 OK response is treated as the HTTPS "connect" port.
- Quota fetch (primary):
  - POST `.../GetUserStatus` on the connect port.
  - Fallback: POST `.../GetCommandModelConfigs` if GetUserStatus fails.
  - HTTPS first, fallback to HTTP on `extension_server_port`.

## Request bodies (summary)
- `GetUserStatus` / `GetCommandModelConfigs` use a minimal metadata payload:
  - `ideName: antigravity`, `extensionName: antigravity`, `locale: en`, `ideVersion: unknown`.
- `GetUnleashData` probe uses a lightweight context payload (enough to get a 200 without auth).

## Parsing and model mapping
- Source fields:
  - `userStatus.cascadeModelConfigData.clientModelConfigs[].quotaInfo.remainingFraction`
  - `userStatus.cascadeModelConfigData.clientModelConfigs[].quotaInfo.resetTime`
- Quota mapping in CodexBar:
  - Primary: Claude (first model containing `claude` but not `thinking`).
  - Secondary: Gemini Pro Low (label contains `pro` + `low`).
  - Tertiary: Gemini Flash (label contains `gemini` + `flash`).
  - If none match: fall back to lowest remaining percent.
- `resetTime` parsing:
  - ISO-8601 if possible; otherwise, tries numeric epoch seconds.
- `accountEmail` and `planName` are only available via GetUserStatus (not CommandModelConfigs).

## UI mapping
- Provider metadata:
  - Display: `Antigravity`
  - Labels: `Claude` (primary), `Gemini Pro` (secondary), `Gemini Flash` (tertiary)
- Menu card + menu list use the same `UsageSnapshot` shape as other providers.
- Icon styling:
  - Uses Gemini sparkle eyes plus a small "orbit" dot to distinguish Antigravity.

## Settings and toggles
- General: "Show Antigravity usage" toggle.
- Autodetect: enabled if Antigravity language server is detected running.
- No web scraping or login flow; switch account button surfaces a guidance alert.

## CLI behavior
- `codexbar` CLI accepts `antigravity` as a provider.
- Output format mirrors other providers. Version string is `nil` (we only know "running").

## Constraints and risks
- Internal protocol: endpoints and fields are not public and may change.
- Requires `lsof` on macOS for port detection.
- TLS trust: local HTTPS uses a self-signed cert; CodexBar uses an insecure session delegate.
- If Antigravity is not running, the provider is treated as unavailable.

## Debugging checklist
1. Confirm Antigravity is running and language server process is present.
2. Ensure `lsof` is available.
3. Verify `--csrf_token` is present in the process command line.
4. Re-run provider autodetect in Debug pane.
5. Check provider error in Settings -> General.

## References
- Implementation: `Sources/CodexBarCore/AntigravityStatusProbe.swift`
- Provider wiring: `Sources/CodexBar/ProviderRegistry.swift`
- UI toggle: `Sources/CodexBar/PreferencesGeneralPane.swift`
- Changelog entry: `CHANGELOG.md`
