---
summary: "Menu bar UI, icon rendering, and menu layout details."
read_when:
  - Changing menu layout, icon rendering, or UI copy
  - Updating menu card or provider-specific UI
---

# UI & icon

## Settings

On macOS 26 and later, Settings uses the system split-view sidebar, toolbar, search, and scroll-edge effects. The native sidebar toggle and divider can hide or restore the sidebar; its saved width is preserved. The detail scroll view and frosted toolbar backing fill the available column in wide windows. Earlier macOS versions keep the existing sidebar, titlebar layout, and detail reading-width cap.

- Back and Forward revisit the panes you opened, using Command-[ and Command-] as in System Settings. Selecting a new pane after going back clears forward history; reselecting the current pane preserves it. The last pane still restores at launch, while navigation history lasts only for the current app session. Hidden Debug panes are removed from history. On macOS 26 and later, the controls use the native toolbar; earlier macOS versions retain the native window title and show the controls above the pane content. The native window title stays set on every version for accessibility and the Window menu. About and Acknowledgements share this history. Opening About explicitly returns to its root; reopening Settings preserves the current destination during the session. Only the pane, not a subpage or history, restores after relaunch.
- App copy, credential-expiry alerts, share cards, number formatting, and layout direction follow the selected app language. Widgets use the system language independently. All 23 supported languages have app catalogs and generated widget catalogs. After editing app translations or widget lookup keys, run `node Scripts/sync-widget-locales.mjs`; hosted lint verifies key coverage, format arguments, plural branches, and generated resources.
- Usage & Spend charts group longer periods by week or month, drill into days and hours, and isolate individual sources. The amount inspector uses the reporting calendar and labels totals as recorded spend; measured zero, unavailable, and incomplete amounts remain distinct.
- Codex settings show saved accounts with separate quota snapshots. Viewing or refreshing an account does not switch the active account; local usage remains tied to the current Codex profile.
- The provider sidebar keeps saved order and the one-click alphabetical toggle (enabled first). Its adjacent menu offers Only show enabled providers and Restore default order. Restore is disabled when the saved order is already the default and alphabetical sorting is off. Search matches service names, provider IDs, CLI names, and CLI aliases, ignoring case and accents. Browsing filters do not rewrite provider configuration or menu bar order; dragging is available only in the unfiltered saved-order view and retains hidden plugin positions. Restore resets built-in service positions to catalog order while preserving plugins. Undo reverses the latest sidebar order change without reverting later credential edits.
- Usage & Spend keeps Refresh beside the title and places the period picker on its own bounded row so narrow preference panes retain readable controls.
- General → Preferred Currency supports Turkish lira (`TRY`, `₺`), New Zealand dollar (`NZD`), `SEK`, `NOK`, `DKK`, `PLN`, `BRL`, `MXN`, `ZAR`, `THB`, `IDR`, `VND`, `UAH`, and Israeli new shekel (`ILS`, `₪`) alongside the existing currencies, using the shared daily exchange rates and offline fallback for cost estimates.
- Hooks fields expose distinct threshold, executable, and argument accessibility labels.
- Agent session menus can hide unreachable hosts; the option defaults off.
- Compact account expansion choices persist locally across menu closes; temporary tail expansion does not.
- The Help command opens QuotaKit’s README.
- General → Default terminal supports installed Terminal, iTerm, Ghostty, and stable Warp. Terminal is the default and fallback. Warp launches target its app directly and use owner-only temporary tab configs, removed after one minute; interrupted-launch leftovers are cleaned on the next app start.
- Provider accent colors use the hex field and color picker; the picker previews the selected color, while Reset restores the provider default without a duplicate swatch.

## Menu bar
Stacked rows with leading window labels align their values and meters after the widest label. Rows that begin with names, explicit spaces, or inline icons retain their natural spacing; hiding percentage window labels is unchanged.
- **Highest usage** compares quota windows, not cost or token activity. Providers without quota windows, such as Pi, are not candidates; choose **Current selection** and select the provider in the menu to keep it visible in the combined icon.
- Combined icon source can follow the current selection, highest usage, or frontmost enabled provider app. Focus monitoring runs only for collapsed merged icons, uses application notifications, and never changes the saved selection or reads terminal tabs.
- Optional Color by provider uses provider accents without rewriting layouts. Pace colors remain independent. Open menus, stale readings, Increase Contrast, inactive-display contrast, and insufficient accent contrast use monochrome rendering.
- The empty Settings placeholder never promotes the app to a Dock application. Real settings and update dialogs retain temporary Dock behavior; macOS may refuse demotion after those dialogs close.
- Overview offers Share Usage Snapshot when its Usage & Spend summary has shareable data. The local preview uses the same spend sources, hidden-source choices, calendar, and currency as that summary; Copy Image exports PNG and TIFF without uploading anything.
- Shared snapshots name the last included reporting day in the dashboard's timezone, use a singular caption for one subscription, and keep recognized public model families behind one gateway namespace. A partial model history is labeled as partial.
- LSUIElement app: no Dock icon; status item uses custom NSImage.
- Merge Icons toggle combines providers into one status item with a switcher.
- Stacked switcher provider labels remain on one line so row content stays aligned.
- With the automatic metric selected, switcher progress honors a provider's exhausted-quota policy before showing
  weekly progress. Healthy allowances, explicit metric choices, and providers that opt out retain their selection rules.
- Cached status menus refresh their effective appearance when the system appearance changes, including previously opened
  nested menus.
- Provider status items use stable autosave names and are reused across provider toggles so macOS can preserve icon
  positions.
- Normal quit removes status items with their stable identities intact, preventing retained blank menu bar slots while
  preserving saved placement.
- With separate icons, explicitly reordering providers in Settings reassigns QuotaKit's saved menu bar slots in that order, from right to left. Recreated items retain their stable autosave and accessibility identities. Orders changed while icons are merged also update these saved slots before returning to separate icons. Ordinary refreshes and visibility recovery continue to preserve manual Command-drag placement.
- When Overview has selected providers, the switcher includes an Overview tab that renders up to 6 provider rows.
- Overview spend uses the native menu background rather than an extra accent tint.
- Overview row order follows provider order; selecting a row jumps to that provider detail card.
- Menu → Overview layout offers Detailed (default) and Compact. Compact keeps provider/account headers and labeled quota bars, omits their reset/detail lines and supplemental sections, and retains detail-only providers. Select a provider for its full card. Visibility choices and the shared Usage & Spend summary continue to apply.
- The global open-menu keyboard shortcut toggles the currently tracked menu closed before opening a new one.
- Display → Menu Bar → Layout provides presets plus a token editor. Tokens can be clicked to append, dragged from the
  palette, reordered between one or two lines, dragged out, or removed with Delete. Layouts can be global or overridden
  per provider. Manual edits select the Custom preset.
- Turn off **Show window labels** beside **Monospaced digits** to hide Session, Weekly, and Scoped weekly percentage
  prefixes such as `5h` and `W`. It defaults on and applies to all layouts. Percentages keep their full VoiceOver
  descriptions; named provider lanes, named allowances, Spend currency symbols, and progress-bar labels remain visible.
- Automatic percentage, pace, and reset tokens identify the selected window when multiple distinct quota windows are available. Show window labels controls the visible prefix, while VoiceOver retains the full window name. Single-window, balance-only, and ambiguous selections stay bare.
- For a provider-specific bare Session percentage, select Codex or Claude in Layout, remove the existing percentage,
  and add the **second Session %** chip from Usage (the provider's primary lane). This works with window labels enabled.
- For Codex or Claude weekly usage without a `W` prefix, select that provider in Layout, remove the existing percentage,
  and add the **second Weekly %** chip from Usage (the provider's secondary lane). The first **Weekly %** is a semantic
  window token and keeps its prefix; lane tokens omit it.
- The **Progress bars stacked** preset places Session and Weekly graphical bars beside their reset countdowns. Graphical bars follow the used/remaining preference; automatic balance values remain text, and older layout generations keep the matching percentage.
- A single leading provider icon can sit beside both rows in a two-line layout. Separate row icons, icon-only first rows, high-contrast rendering, and provider-colored rendering keep icons inline.
- Palette chips retain their natural label widths and wrap to the next row instead of squeezing longer names into
  equal-width columns.
- Small/Regular/Large controls the token font scale; Regular remains the default. Large uses 14-point single-line text
  and 10-point stacked text. Monospaced digits is an independent optional setting that defaults off; labels remain
  proportional. Show window labels is a separate optional setting that defaults on. These display preferences stay
  outside saved layout tokens, preserving V6 layouts and V5, V4, V3, V2, and legacy projections. Tight/Regular controls
  status-item padding. Compact stacked uses two tightly spaced lines
  sized to fit the menu bar. Stacked text, including combined-provider rows, uses medium weight for legibility at every size and digit style; single-line text keeps regular weight.

### Layout tokens

| Group | Tokens | Behavior |
| --- | --- | --- |
| Identity | Icon, Provider name, Account | Provider-scoped branding and identity |
| Usage | Session %, Weekly %, Auto %, Spend %, provider-specific %, Usage bar, graphical progress bars | Window percentage, compact three-glyph usage bar, or graphical bar; named Cursor and Antigravity allowances retain their own labels and show a dash when unavailable |
| Usage | Session pace, Weekly pace, Auto pace, Spend pace | Signed pace delta for that window |
| Time | Resets in, Reset at, Runs out | Relative reset, absolute reset, or pace estimate; explicit Session, Weekly, and Spend reset tokens are also available |
| Money | Balance, Cost today, Cost (History window), Spend, Spend / budget | Provider balance or remaining credits, local cost estimate, or provider-reported spend and budget. Cost (History window) is the total for the selected [History window](cost-reporting-periods.md), and cost thresholds compare that window's total |
| Structure | Separator dot, Space, Line break | Spacing and optional two-line composition |

Spend tokens use the provider-reported budget behind the Extra usage metric and honor **Show optional credits, spending & billing details**. They do not use prepaid balances or local cost estimates. Spend % carries the budget's currency symbol; credit-denominated caps have no currency prefix and no monetary amount. Spend pace requires a reported period and becomes available after 1% of that period. Existing layouts are unchanged; new installs include a **Spend over 90% used** conditional rule.

Layouts, overrides, and rules are stored in V6. Older builds read the V5 projection without Spend tokens or rules; V4 and earlier projections keep their existing compatibility behavior. Returning restores the full layout when its older copy is unchanged. Edits in an older build take precedence, while untouched overrides and Spend rules survive; clearing the older rule library deliberately clears all rules.

The pace tokens render the same delta the menu card shows as "in deficit"/"in reserve", in the compact signed form the
pre-0.45 **Both** display mode used: `+11%` means usage runs that far ahead of the sustainable rate, `-8%` that far
behind it, `0%` on pace. Each pace token reads its own window, so `Weekly pace` never borrows the session delta — unlike
`Runs out`, which always estimates from the weekly (or automatic) lane. Weekly and Spend pace can appear after 1% of
their periods has elapsed; Session, Auto, and Runs out keep the 3% threshold. A pace token renders an en dash while
unavailable; see [Pace tracking](#pace-tracking).

Enable **Color Pace Indicator** under **Menu Bar → Icon** to show usage behind pace in green and usage ahead of pace
in red. The setting defaults off and colors Session, Weekly, Auto, and Spend pace in both the menu bar and layout preview.
Zero and unavailable pace stay neutral. Stale colors dim, and high-contrast rendering uses the system label color.

The Time palette also offers explicit Session and Weekly reset countdowns and clocks. The existing Resets in and Reset
at tokens retain automatic-window behavior. Conditional branches can use the same explicit reset tokens. Layouts save
V6 data with a Spend-free V5 projection, plus V4, V3, V2, and legacy projections that preserve the older reset-token
compatibility rules.

Balance uses provider-reported amounts where available, including OpenRouter remaining credits and LithosAI prepaid
balance. Auto %
uses the same provider-aware automatic-window resolution as the legacy menu bar metric setting. If a snapshot
does not provide a token's data, that token renders an en dash while its siblings remain visible. Existing installs
derive their first layout from the prior style, display mode, metric, and reset settings; those legacy keys remain
untouched for downgrade safety, while a saved token layout takes precedence.
Custom layout saves keep older-readable projections so a downgrade can still load the layout; provider-specific
named percentages are omitted from those older projections without removing the rest of the layout.
Provider settings also offer a simple percent-window picker when the menu bar uses Icon and Percent and the provider
supports multiple windows. It writes a provider layout override while keeping custom mixed-window layouts visible as
Custom in the picker.

For Abacus, explicitly selecting Credits keeps the monthly allowance visible. With 250 of 1,000 credits used, it
shows `C 75%` remaining (or `C 25%` with Show usage as used). Its billing window and reset date still drive pacing;
Automatic keeps its existing percentage. Credits labels also apply to editor tokens, conditional metrics and pace
accessibility.


## Icon rendering
- 18×18 template image.
- Bar windows are provider/style-specific primary and secondary windows.
- Fill represents percent remaining by default; “Show usage as used” flips to percent used.
- Renderer/critter icons dim when last refresh failed and can render incident indicators; single-quota status badges attach
  to the visible meter. Brand display mode uses provider branding plus title text.
- Loading animation runs at a bounded frame rate and has a hard continuous-duration ceiling so provider hangs cannot keep
  the menu bar redrawing forever.
- The token renderer composes provider branding and text through the same attributed-title path used for high-contrast
  status items. Critter and bar styles keep their existing renderers.

## Menu card
- Cards with a history submenu show the active menu selection; deselecting the card clears it. Credits and other sections are separate menu items, so selecting usage does not highlight them.
- Two-column statistics headings wrap to keep the full localized label readable, including estimated current-window tokens.
- Provider-specific rows with resets (countdown by default; optional absolute clock display). Primary, secondary,
  tertiary, and extra windows render when the provider snapshot has data for them.
- Manual refresh updates the open card subtitle and persistent Refresh-row spinner in place. Repeated clicks share the
  active request, and the existing row geometry remains fixed through success or failure.
- Provider errors use up to three red lines, with inline backtick-delimited commands rendered in monospace and the copy control aligned to the first line. Copy preserves the original error text. Stale Claude usage has a separate, single-line secondary notice; Settings error previews retain the notice with the error.
- Codex credits can add a separate “Buy Credits…” menu action.
- Shared stats retain complete providers' model history when another provider is incomplete and mark the
  resulting model list as partial. A selected day never presents its models as a full-window ranking.
- Claude capped Extra Usage follows the used/remaining fill preference; spending amounts and “% used” copy stay unchanged.
- Codex OpenAI web extras: code review remaining and usage breakdown render when dashboard data is attached.
- Codex and Claude cost cards: a Recent windows list under the daily bars shows each quota window's
  range, cost, and tokens (Current window, Previous window, N windows ago), split at official and banked resets.
  Inferred boundaries are labeled estimated; incomplete local subtotals show ≥ and a partial-estimate note.
  Without weekly reset metadata, the existing calendar cost history remains visible.
- Token accounts: optional account switcher bar or stacked account cards (up to 6) when multiple manual tokens exist.
- Provider storage usage is opt-in from Advanced settings. When enabled, overview rows and provider detail cards can show
  local provider-owned storage totals, with a submenu for path breakdowns and copyable paths.

## Pace tracking

Pace compares your actual usage against the expected consumption rate for the current window. Most providers use an even-consumption budget; Codex can use historical pace data when historical tracking is available.

The **Work days** setting selects the weekly pace model. **Automatic** uses Codex historical pace when enough data is available. Historical daily credits follow calendar-day boundaries, including midnight daylight-saving transitions. Selecting 4, 5, or 7 days uses that explicit schedule for pace and ETA instead; QuotaKit continues collecting history in the background, but does not use historical predictions until the setting returns to Automatic.

- **On pace** – usage matches the expected rate.
- **X% in deficit** – you're consuming faster than the even rate; at this pace you'll run out before the window resets.
- **X% in reserve** – you're consuming slower than the even rate; you have headroom to spare.

When usage is in deficit, the right-hand label shows an estimated "Runs out in …" countdown. When usage will last until the reset, it shows "Lasts until reset".

Pace is calculated for any provider window with enough reset timing data and is hidden when less than 3% of the
window has elapsed.

## Preferences notes
- Advanced: “Disable Keychain access” turns off browser cookie import; paste Cookie headers manually in Providers.
- Advanced: “Show provider storage usage” enables background scans of known provider-owned local paths; QuotaKit only
  reports sizes and cleanup ideas, it does not delete files.
- Display: “Overview tab providers” controls which providers appear in Merge Icons → Overview (up to 6).
- If no providers are selected for Overview, the Overview tab is hidden.
- Providers → Claude: “Avoid Keychain prompts” selects the Security.framework reader's `Never prompt` policy.
- The lower-level “Keychain prompt policy” picker remains visible as the source of truth for Claude OAuth prompts.
- Providers → each provider: “Visible usage items” controls which reported metrics, credits, and titled detail sections appear in its Mac menu, Settings preview, and Overview. Hidden choices remain individually restorable while temporarily unavailable; “Restore Defaults” shows all items again.

Usage visibility is presentation-only: it does not change fetching, quota calculations, headroom ranking, or severity. Compact multi-account rows omit hidden quota labels from their constraint summary while continuing to rank against every quota. The choice is stored in provider config and shared through Mac provider-intent sync; the iPhone snapshot wire format and contents are unchanged.

## Widgets (high level)
- Widgets render shared usage snapshots for the supported widget families and
  provider picker; detailed pipeline in `docs/widgets.md`.

See also: `docs/widgets.md`.

Cost-history submenus keep tall charts in an app-owned scrollable viewport. The Token/Cost picker sits below the chart so hovering near the top does not trigger native menu auto-scrolling; it aligns with the chart's content edge.

### Menu bar metric

In Icon and Percent mode, the provider's **Menu bar metric** picker offers Auto, Session, Weekly, and declared named allowances: Cursor's Grok Bot and Antigravity's Gemini weekly and Claude/GPT weekly quotas. Choices remain available before a reading arrives and persist through the existing layout override. Named allowances retain their labels, preserve a real zero, and show an en dash for missing or unknown data. Balance, reset, conditional tokens, and other providers' layouts remain independent.

## Activity navigation and incomplete usage

Token activity uses appearance-aware colors and a slashed outline for unavailable history. Narrow annual grids scroll with labeled earlier/recent controls; keyboard navigation reveals the active date. Calendar columns retain chronological left-to-right order within right-to-left interfaces.

Usage & Spend preserves known daily request counts when another source cannot count requests, marking the subtotal with `≥`. Missing request counts do not make known token or cost totals partial. Incomplete imported model history retains known subtotals and does not produce misleading share rankings.

## Settings navigation and quota risk

Settings retains independent back/forward selection history and sidebar selections. Native header controls
share the detail header on macOS 26; macOS 14/15 retain the window title and put navigation above pane content.
The native title remains available to accessibility and the Window menu.

Automatic quota selection compares depletion risk using valid remaining usage and reset timing. Explicit
window choices remain pinned. Six work days uses Monday through Saturday and excludes Sunday in weekly
pace and session-forecast capacity. A corrected older session reset discards the earlier history segment;
three valid later completed samples can restore forecasting.

Fresh monochrome stacked text can use template rendering for native inactive-display dimming. Colored,
stale and high-contrast content keeps its appropriate rendering path. Dock updates follow startup and actual
window transitions; reset confetti stays click-through while particles finish falling.


### Monthly allowance daily target

Monthly allowance cards also show a daily target: remaining allowance divided by the local calendar days
until reset, counting today and any partial reset day (at least one day). A reset exactly at midnight does
not add another day. The target keeps the reported credits, requests, currency, or percentage units and
follows the existing pace visibility setting. Unknown usage, missing resets, and expired windows show no
target. This is a budget for the remaining period, not a measurement of today's usage or an alert threshold.
