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
- If no snapshot is available, widgets fall back to preview/empty data.

## Extension
- `Sources/CodexBarWidget` contains timeline + views.
- `WidgetExtension/CodexBarWidgetExtension.xcodeproj` builds those sources as the packaged macOS WidgetKit app extension.
- Keep data shape in sync with `WidgetSnapshot` in the main app.

## Widget types
- **QuotaKit Switcher** (`CodexBarSwitcherWidget`): static provider switcher widget, small/medium/large.
- **QuotaKit Usage** (`CodexBarUsageWidget`): configurable provider usage widget, small/medium/large.
- **QuotaKit History** (`CodexBarHistoryWidget`): configurable usage-history chart, medium/large.
- **QuotaKit Metric** (`CodexBarCompactWidget`): compact credits/today-cost/30-day-cost widget, small only.
- **QuotaKit Burn Down** (`CodexBarBurnDownWidget`): configurable quota burn-down chart, medium only.
- **QuotaKit Burn Down (Combined)** (`CodexBarCombinedBurnDownWidget`): two quota burn-down charts, medium only.

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
