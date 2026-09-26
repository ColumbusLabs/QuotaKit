---
summary: "WidgetKit snapshot pipeline + visibility troubleshooting for QuotaKit widgets."
read_when:
  - Modifying WidgetKit extension behavior or snapshot format
  - Debugging widget update timing
  - Widget gallery shows no QuotaKit widgets
---

# Widgets

## Snapshot pipeline
- `WidgetSnapshotStore` writes compact JSON snapshots to the app-group container.
- Widgets read the snapshot and render usage/credits/history states.
- The app writes snapshots after the main refresh pipeline and token-usage refreshes; narrow single-provider refresh paths may wait for the next snapshot write.
- Automatic provider refresh is the sole periodic trigger for token/cost refreshes; the token/cost TTL only determines
  eligibility when that refresh runs. Automatic local-history scans have a 15-minute minimum (30 minutes in low-power
  mode), while Manual disables automatic scans. The floor limits repeated local-history work and extra WidgetKit reload
  requests without changing provider usage/status freshness or the user-selected provider refresh cadence.
- Claude local cost/token history remains eligible for widget snapshots when its account does not expose numeric
  session or weekly quota data.
- When claude-swap owns Claude's menu presentation, the provider widget uses the active swap account even if
  per-account widgets are disabled. Retained quota stays bound to an opaque account fingerprint and keeps its original
  measurement age; missing or changed owners cannot inherit ambient or another swap account's quota.
- If no snapshot is available, widgets fall back to preview/empty data.

## Extension
- `Sources/CodexBarWidget` contains timeline + views.
- `WidgetExtension/CodexBarWidgetExtension.xcodeproj` builds those sources as the packaged macOS WidgetKit app extension.
- Keep data shape in sync with `WidgetSnapshot` in the main app.

## Widget types
- **QuotaKit Switcher** (`CodexBarSwitcherWidget`): static provider switcher widget, small/medium/large.
- **QuotaKit Usage** (`CodexBarUsageWidget`): configurable provider usage widget, small/medium/large.
- **QuotaKit Account Usage** (`CodexBarAccountUsageWidget`): pins one verified saved account, small/medium/large.
- **QuotaKit History** (`CodexBarHistoryWidget`): configurable usage-history chart, medium/large.
- **QuotaKit Metric** (`CodexBarCompactWidget`): compact credits/today-cost/30-day-cost widget, small only.
- **QuotaKit Burn Down** (`CodexBarBurnDownWidget`): configurable quota burn-down chart, medium only.
- **QuotaKit Burn Down (Combined)** (`CodexBarCombinedBurnDownWidget`): two quota burn-down charts, medium only.

## Account selection

Enable **Settings → Menu → Widgets → Keep accounts updated for widgets**, then add a **QuotaKit Account Usage**
widget and choose its **Provider** and **Account**. For example, two Account Usage widgets can pin different Claude
accounts while a third widget displays Codex. The existing Usage widget sizes, bars and reset countdowns are reused.
An Account Usage widget without an account shows setup instructions; it never follows the current account implicitly.
Regular **QuotaKit Usage** widgets continue following their configured provider as before.

The opt-in keeps saved token accounts and visible Codex accounts refreshing independently of the menu's segmented
or stacked layout, using the existing six-account refresh bound. Claude-swap continues to own its own polling;
its widget choices remain available when only one slot remains. Slot labels and an opaque ownership fingerprint
keep a replacement account from inheriting an old pin without persisting the adapter's personal identity fields.
**Hide personal info** replaces other account labels with ordinals without changing widget account identities.

Saved-token pins combine the source UUID with a verified returned owner and any explicit usage scope. Claude OAuth requests the account profile with the same token only when account widgets are enabled. A profile failure keeps the last verified quota at its original age while the credential scope matches; labels never establish ownership. The general usage identity stays unchanged for Cloud Sync and hook throttling. A private app cache stores the verified opaque pin, a one-way credential-scope guard, and quota-only data for offline restarts; it stores no account labels or credentials and is separate from the shared widget JSON. Opt-out, removal, authentication failure, and credential replacement retire the corresponding cached data.

Codex pins combine managed account UUIDs with verified owners or normalized source/owner identities, not the menu's email-disambiguated
row IDs. Adding or removing a same-email sibling does not change an existing pin. Profile homes remain distinct,
and rotating credentials does not change a pin's identity.

An explicitly selected account never falls back to another account if it is removed, unavailable, or belongs to a
different provider. Transient refresh failures retain the matching account's last-good quota and its original
measurement timestamp; authentication failures and owner changes do not borrow prior account data. Disabling the
setting removes account choices and data from the shared snapshot; provider-only widgets keep working.

Pinned account snapshots currently include quota windows only. Provider-level local cost scans, credits, and history
are not copied into account widgets because their ownership is not necessarily the selected account.
Usage, History, Metric, Switcher, and Burn Down widgets retain their existing provider-only configuration.

### Upgrade and rollback compatibility

The existing widget kinds, `ProviderSelectionIntent`, and provider timeline behavior are unchanged. Account selection
uses a new `CodexBarAccountUsageWidget` kind and a separate `AccountUsageSelectionIntent`; no parameters are added to
persisted configurations of existing widgets. The new intent has no default account. Enabling background account
refresh is a separate opt-in, off by default.

The Mac app-group widget JSON format is additive: older snapshots omit `accounts`, and the new reader accepts
them. The iPhone widget snapshot and CloudKit account payloads use separate schemas and are unchanged. Older readers ignore those fields in new snapshots. A rollback can rewrite the provider snapshot without
account data; a feature widget reading that rewritten snapshot shows unavailable rather than another account’s quota.
The old app does not provide the new Account Usage widget kind; rollback support applies to the existing provider widgets.
`WidgetSnapshotCompatibilityTests` covers fixed legacy wire data and an older reader/writer, while
`WidgetAccountCompatibilityTests` covers account removal, replacement, identity changes, and refresh failures.

Installed WidgetKit behavior still needs native verification; JSON tests and unchanged intent definitions alone
do not prove the operating system’s upgrade and rollback behavior. In an isolated macOS environment, use baseline and feature bundles with the same bundle
identifiers, signing team, and app group:

1. Install the baseline and add provider-only Usage and History widgets with a non-default provider.
2. Upgrade in place without removing the widgets. Confirm the provider selection, quota, and history remain intact.
3. Opt into account refresh and add two Account Usage widgets with different accounts. Switch the app's selected account,
   refresh, and relaunch; each widget must keep its own pin and measurement.
4. Remove a sibling, then remove or replace a pinned account. Surviving pins must remain stable; removed/replaced
   pins must show unavailable. Opt out and confirm provider-only widgets still work.
5. Roll back the bundle and confirm provider-only widgets still render. Record app/widget versions and screenshots
   separately from synthetic rendering fixtures, with personal information hidden.

## Provider picker support
The configurable provider widgets currently expose:
Codex, Claude, Cursor, Gemini, Alibaba, Antigravity, z.ai, Copilot, MiniMax, Kilo, OpenCode, and OpenCode Go.

Providers without a `ProviderChoice` case can still be present in the app snapshot, but they are not selectable from the widget configuration UI yet.

Burn-down provider choices are filtered from the enabled providers in the latest saved snapshot. A quota
qualifies when it has a finite usage percentage, a positive `windowMinutes`, a reset date, and is not a
synthetic placeholder. The compile-time AppIntent catalog covers all built-in providers; providers that
only report balances, unknown durations, or unknown resets do not appear. Refresh QuotaKit before
configuring a newly enabled provider. Custom plugin instance IDs are not part of the AppEnum catalog.

For **Burn Down**, select **Provider**, then **Usage window**. The choices use the snapshot's quota names:
Devin offers **Daily** and **Weekly**; Cursor offers **Total**, **Cursor**, and **Third Party** when those
billing-cycle quotas are present. Each chart uses that quota's actual duration and reset, including
Cursor's billing cycle. The choice stays pinned to its quota slot: missing data shows the empty state,
never another quota. Provider titles in the snapshot take precedence over descriptor defaults.

**Burn Down (Combined)** shows the first two quota lanes with their own names and durations, such as
Devin's **Daily & Weekly** or Cursor's **Total & Cursor**. A missing lane shows **No data** under its own
name. The single widget also offers the third quota when available. Combined requires a compatible first or
second quota; a provider with only a compatible third quota appears in the single widget picker.

Existing Codex/Claude intents retain their types, provider raw values, defaults, and exact **Session
(5-hour)** / **Weekly (7-day)** meanings. Their Combined widgets keep those two lanes, including the
weekly-cap behavior. If either provider supplies a different window duration, the new quota-slot choices
and Combined layout use those actual windows; saved Session/Weekly aliases remain exact. New cases are additive; the configuration schema requires no removal and
re-adding of widgets. Snapshot persistence, empty-snapshot preservation, and the 5–30-minute timeline schedule are
unchanged. This does not address Homebrew removing widget placements during bundle replacement (#3627).

Migration tests pin the original raw values and parameter types and exercise the old selections against
legacy snapshots. Offscreen synthetic renders verify labels and chart layout; they do not prove installed
WidgetKit upgrade behavior. Native upgrade verification should keep non-default Claude/Weekly widgets
installed across an in-place signed bundle upgrade, then check Devin/Cursor choices in the widget editor.

## Visibility troubleshooting (macOS 14+)
When widgets do not appear in the gallery at all, the issue is almost always
registration, signing, or daemon caching (not SwiftUI code).

### 1) Verify the extension bundle exists where macOS expects it
```
APP="/Applications/QuotaKit.app"
WAPPEX="$APP/Contents/PlugIns/QuotaKitWidget.appex"
WIDGET_ID="com.columbuslabs.quotakit.mac.widget" # debug builds use com.columbuslabs.quotakit.mac.debug.widget

ls -la "$WAPPEX" "$WAPPEX/Contents" "$WAPPEX/Contents/MacOS"
```

### 2) PlugInKit registration (pkd)
```
pluginkit -m -p com.apple.widgetkit-extension -v | grep -i quotakit || true
pluginkit -m -p com.apple.widgetkit-extension -i "$WIDGET_ID" -vv
```
Notes:
- `+` = elected to use, `-` = ignored (PlugInKit elections).
- If missing or ignored, force-add and re-elect:
```
pluginkit -a "$WAPPEX"
pluginkit -e use -p com.apple.widgetkit-extension -i "$WIDGET_ID"
```
- Check for duplicates (old installs or version precedence):
```
pluginkit -m -D -p com.apple.widgetkit-extension -i "$WIDGET_ID" -vv
```
If multiple paths appear, delete older installs and bump `CFBundleVersion`.

### 3) Code signing + Gatekeeper assessment
Widgets are loaded by system daemons. Any signing failure can hide the widget.
```
codesign --verify --deep --strict --verbose=4 /Applications/QuotaKit.app
codesign --verify --strict --verbose=4 "$WAPPEX"
codesign --verify --strict --verbose=4 "$WAPPEX/Contents/MacOS/QuotaKitWidget"
spctl --assess --type execute --verbose=4 /Applications/QuotaKit.app
```

### 4) Restart the right daemons (NotificationCenter alone is not enough)
```
killall -9 pkd || true
sudo killall -9 chronod || true
killall Dock NotificationCenter || true
```

### 5) Watch logs while opening the widget gallery
```
log stream --style compact --predicate '(process == "pkd" OR process == "chronod" OR subsystem CONTAINS "PlugInKit" OR subsystem CONTAINS "WidgetKit")'
```

### 6) Packaging sanity checks
- Widget bundle id should be `com.columbuslabs.quotakit.mac.widget` for release and `com.columbuslabs.quotakit.mac.debug.widget` for debug.
- `NSExtensionPointIdentifier` must be `com.apple.widgetkit-extension`.
- Bundle folder name should match: `QuotaKitWidget.appex`.

Optional: re-seed LaunchServices (rarely helps, but low risk):
```
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -seed
```

## Common post-visibility issue: stale data
If the widget appears but always shows preview data:
- App writes snapshot to fallback path while widget reads app-group container.
- Validate that both app and widget resolve the same app-group container.

See also: `docs/ui.md`, `docs/packaging.md`.

The **Cost** metric follows the app’s [cost reporting period](cost-reporting-periods.md), including month-to-date and all available history. The displayed period label travels with the cost snapshot.
