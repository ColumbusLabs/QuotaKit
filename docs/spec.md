---
summary: "CodexBar implementation notes: data sources, refresh cadence, UI, and structure."
read_when:
  - Modifying usage fetching/parsing for Codex or Claude
  - Changing refresh cadence, background tasks, or menu UI
  - Reviewing architecture before feature work
---

# CodexBar – implementation notes

## Data source
- Codex: prefer the local `codex app-server` RPC (`codex -s read-only -a untrusted app-server`) for 5-hour + weekly rate limits and credits; fall back to a PTY scrape of `codex /status` when RPC is unavailable.
- Codex account: prefers RPC account details; falls back to decoding `~/.codex/auth.json` for email/plan when needed.
- Claude: run `claude /usage` + `claude /status` in a native PTY and parse the text UI (session + weekly + Sonnet-only weekly when present).
- OpenAI web (optional, Codex only): reuse an existing signed-in `chatgpt.com` browser session and scrape the Codex usage dashboard for:
  - Code review remaining (%)
  - Usage breakdown (dashboard chart)
  - Credits usage history (dashboard table) when available

### OpenAI web: cookie/session model
- Opt-in toggle: Settings → General → “Access OpenAI via web”.
- Cookie import order: Safari → Chrome (Safari first to avoid Chrome Keychain prompts when Safari matches).
- Multiple accounts: WebKit uses a per-email persistent `WKWebsiteDataStore` so multiple OpenAI dashboard sessions can coexist.
- Email sync: if the browser session email doesn’t match the Codex CLI email, we treat it as “not logged in” for the current Codex account (but keep the cookies for that other account so switching Codex accounts can auto-match later).
- Privacy: no passwords stored; only existing browser cookies are reused. Web requests go to `chatgpt.com` (as your normal browser session would).

## Refresh model
- `RefreshFrequency` presets: Manual, 1m, 2m, 5m (default), 15m; persisted in `UserDefaults`.
- Background refresh runs off-main, wakes per cadence, and updates `UsageStore` (usage + credits + optional OpenAI web scrape).
- Manual “Refresh now” menu item always available; stale/errors are surfaced in-menu and dim the icon.
- Optional future: auto‑seed a log if none exists via `codex exec --skip-git-repo-check --json "ping"`; currently not executed to avoid unsolicited usage.

## UI / icon
- NSStatusItem-based menu bar app (LSUIElement=YES). No Dock icon. Label replaced with custom NSImage.
- Icon: 20×18 template image; top bar = 5h window, bottom hairline = weekly window; fill represents “percent remaining” by default (optionally “percent used” via settings). Dimmed when last refresh failed.
- Menu: rich card (session + weekly; resets; account/plan), plus web-only Codex rows when enabled and available:
  - Code review remaining
  - Usage breakdown submenu (Swift Charts)
- Widgets (macOS WidgetKit): optional usage/credits/history widgets powered by a shared app-group snapshot.

## App structure (Swift 6, macOS 15+)
- `CodexBarCore`: fetch + parse (Codex RPC, PTY runner, Claude probes, OpenAI web scraping).
- `UsageStore`: state + refresh loop + caching + error handling.
- `SettingsStore`: persisted cadence/toggles.
- `StatusItemController`: NSStatusItems, menu building, menu actions, icon rendering/animations.
- Entry: `CodexBarApp` (SwiftUI keepalive + Settings scene) + `AppDelegate` (wires status controller + Sparkle updater).
- Widget data: `WidgetSnapshotStore` writes a compact JSON snapshot to an app-group container for WidgetKit extensions.

## Packaging & signing
- `Scripts/package_app.sh`: swift build (arm64), writes `CodexBar.app` + Info.plist, copies `Icon.icns` if present; seeds Sparkle keys/feed.
- `Scripts/sign-and-notarize.sh`: uses APP_STORE_CONNECT_* creds and Developer ID identity (`Y5PE65HELJ`) to sign, notarize, staple, zip (`CodexBar-0.1.0.zip`). Adjust identity/versions as needed.
- Sparkle: Info.plist contains `SUFeedURL` (GitHub Releases appcast) and `SUPublicEDKey` placeholder; updater is `SPUStandardUpdaterController`, menu has “Check for Updates…”.

## Limits / edge cases
- Codex: if RPC reports “data not available yet”, menu keeps cached credits and shows a friendly retry message.
- OpenAI web: Safari cookie access may require Full Disk Access; the settings UI links directly to the System Settings pane.
- OpenAI web: dashboard layout changes can break scraping; errors surface as “OpenAI dashboard data not found” with a short body sample in settings/debug.
- Only arm64 scripted; add x86_64/universal if desired.

## Alternatives considered
- PTY-only Codex parsing: retained as a fallback, but RPC is the primary path for reliability.
- OpenAI dashboard scraping: implemented as opt-in; cookie reuse only (no credential capture UI).

## Learnings / decisions
- About panel: `AboutPanelOptionKey.credits` needs `NSAttributedString`; we supply credits + icon safely.
- Menu palette: keep primary by default, apply `.secondary` only to meta lines, and use `.buttonStyle(.plain)` to avoid tint overriding colors.
- Usage fetch runs off-main via detached task to keep the menu responsive if logs grow.
- Emoji branding lives only in README; app name stays `CodexBar`.
- Swift 6 strict concurrency enabled via `StrictConcurrency` upcoming feature to catch data-race risks early.
