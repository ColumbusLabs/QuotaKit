---
summary: "Cursor support in CodexBar: cookie-based API fetching and UX."
read_when:
  - Debugging Cursor usage parsing
  - Adjusting Cursor provider UI/menu behavior
  - Troubleshooting cookie import issues
---

# Cursor support (CodexBar)

Cursor support is implemented: CodexBar can show Cursor usage alongside other providers. Unlike CLI-based providers, Cursor uses web-based cookie authentication.

## UX
- Settings → Providers: toggle for "Show Cursor usage".
- No CLI detection required; works if browser cookies are available.
- Menu: shows plan usage, on-demand usage, and billing cycle reset time.

### Cursor menu-bar icon
- Uses the same two-bar metaphor as other providers.
- Brand color: teal (#00BFA5).

## Data path (Cursor)

### How we fetch usage (cookie-based)

1. **Primary: Browser cookie import**
   - Safari: reads `~/Library/Cookies/Cookies.binarycookies`
   - Chrome: reads encrypted SQLite cookie DB from `~/Library/Application Support/Google/Chrome/*/Cookies`
   - Firefox: reads SQLite cookie DB from `~/Library/Application Support/Firefox/Profiles/*/cookies.sqlite`
   - Requires cookies for `cursor.com` + `cursor.sh` domains

2. **Fallback: Stored session**
   - If browser cookies unavailable, uses session stored via "Add Account" login flow
   - WebKit-based browser window captures cookies after successful login
   - Session persisted to `~/Library/Application Support/CodexBar/cursor-session.json`

### API endpoints used
- `GET /api/usage-summary` — plan usage, on-demand usage, billing cycle
- `GET /api/auth/me` — user email and name

### What we display
- **Plan**: included usage percentage with reset countdown
- **On-Demand**: usage beyond included plan limits (when applicable)
- **Account**: email and membership type (Pro, Enterprise, Team, Hobby)

## Cookie import details

### Safari
- Parses `binarycookies` format (big-endian header, little-endian pages)
- May require Full Disk Access permission

### Chrome
- Decrypts cookies using "Chrome Safe Storage" key from macOS Keychain
- Prompts for Keychain access on first use
- Supports multiple Chrome profiles

### Firefox
- Reads `cookies.sqlite` (no Keychain prompt)
- Supports multiple Firefox profiles

## Notes
- No CLI required: Cursor is entirely web-based.
- Session cookies typically valid for extended periods; re-login rarely needed.
- Provider identity stays siloed: Cursor email/plan never leak into other providers.

## Debugging tips
- Check browser login: visit `https://cursor.com/dashboard` in Safari/Chrome/Firefox to verify signed-in state.
- Safari cookie permission: System Settings → Privacy & Security → Full Disk Access → enable CodexBar.
- Chrome Keychain prompt: allow CodexBar to access "Chrome Safe Storage" when prompted.
- Settings → Providers shows the last fetch error inline under the Cursor toggle.
- "Add Account" opens a WebKit browser window for manual login if cookie import fails.

## Membership types
| API value | Display |
|-----------|---------|
| `pro` | Cursor Pro |
| `hobby` | Cursor Hobby |
| `team` | Cursor Team |
| `enterprise` | Cursor Enterprise |
