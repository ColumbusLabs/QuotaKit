---
summary: "Menu bar UI, icon rendering, and menu layout details."
read_when:
  - Changing menu layout, icon rendering, or UI copy
  - Updating menu card or provider-specific UI
---

# UI & icon

## Settings
- App copy, credential-expiry alerts, share cards, number formatting, and layout direction follow the selected app language. Widgets use the system language independently. All 23 supported languages have app catalogs and generated widget catalogs. After editing app translations or widget lookup keys, run `node Scripts/sync-widget-locales.mjs`; hosted lint verifies key coverage, format arguments, plural branches, and generated resources.
- Usage & Spend charts group longer periods by week or month, drill into days and hours, and isolate individual sources. The amount inspector uses the reporting calendar and labels totals as recorded spend; measured zero, unavailable, and incomplete amounts remain distinct.
- Codex settings show saved accounts with separate quota snapshots. Viewing or refreshing an account does not switch the active account; local usage remains tied to the current Codex profile.
- Usage & Spend keeps Refresh beside the title and places the period picker on its own bounded row so narrow preference panes retain readable controls.
- Hooks fields expose distinct threshold, executable, and argument accessibility labels.
- Agent session menus can hide unreachable hosts; the option defaults off.
- Compact account expansion choices persist locally across menu closes; temporary tail expansion does not.
- The Help command opens QuotaKit’s README.
- General → Default terminal supports installed Terminal, iTerm, Ghostty, and stable Warp. Terminal is the default and fallback. Warp launches target its app directly and use owner-only temporary tab configs, removed after one minute; interrupted-launch leftovers are cleaned on the next app start.
- Provider accent colors use the hex field and color picker; the picker previews the selected color, while Reset restores the provider default without a duplicate swatch.

## Menu bar
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
- Palette chips retain their natural label widths and wrap to the next row instead of squeezing longer names into
  equal-width columns.
- Small/Regular controls the token font scale. Tight/Regular controls status-item padding. Compact stacked uses two
  tightly spaced lines sized to fit the menu bar.

### Layout tokens

| Group | Tokens | Behavior |
| --- | --- | --- |
| Identity | Icon, Provider name, Account | Provider-scoped branding and identity |
| Usage | Session %, Weekly %, Auto %, provider-specific %, Usage bar | Window percentage or a compact three-glyph usage bar; named Cursor and Antigravity allowances retain their own labels and show a dash when unavailable |
| Usage | Session pace, Weekly pace, Auto pace | Signed pace delta for that window |
| Time | Resets in, Reset at, Runs out | Relative reset, absolute reset, or pace estimate |
| Money | Balance, Cost today, Cost 30d | OpenRouter credit balance, or local cost estimate for the selected period |
| Structure | Separator dot, Space, Line break | Spacing and optional two-line composition |

The pace tokens render the same delta the menu card shows as "in deficit"/"in reserve", in the compact signed form the
pre-0.45 **Both** display mode used: `+11%` means usage runs that far ahead of the sustainable rate, `-8%` that far
behind it, `0%` on pace. Each pace token reads its own window, so `Weekly pace` never borrows the session delta — unlike
`Runs out`, which always estimates from the weekly (or automatic) lane. A pace token renders an en dash while pace is
unavailable, including the first 3% of a window; see [Pace tracking](#pace-tracking).

Enable **Color Pace Indicator** under **Menu Bar → Icon** to show usage behind pace in green and usage ahead of pace
in red. The setting defaults off and colors Session, Weekly, and Auto pace in both the menu bar and layout preview.
Zero and unavailable pace stay neutral. Stale colors dim, and high-contrast rendering uses the system label color.

The Time palette also offers explicit Session and Weekly reset countdowns and clocks. The existing Resets in and Reset
at tokens retain automatic-window behavior. Conditional branches can use the same explicit reset tokens. Layouts save
V4 data and older-readable V3, V2, and legacy projections that omit explicit reset tokens so older app versions can
still load supported tokens.

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
