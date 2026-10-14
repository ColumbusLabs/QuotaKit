---
summary: "Command Code provider notes: API-key and browser-cookie authentication, plus usage-window parsing."
read_when:
  - Debugging Command Code cookie import or usage parsing
  - Updating Command Code billing or credit display
  - Adjusting Command Code provider UI/menu behavior
---

# Command Code

QuotaKit surfaces [Command Code](https://commandcode.ai) monthly USD credits next
to your other AI coding providers.

## Data source

- `https://api.commandcode.ai` billing endpoints: `/alpha/billing/*` with a
  Command Code API key, or `/internal/billing/*` with the signed-in web session.
- The provider reads 5-hour and weekly rolling limits alongside monthly credit
  usage, plan allowance, remaining credits, and billing-cycle reset timing when
  the account data is available.

## Authentication

Command Code supports an API key, browser cookies, or a manually pasted cookie header. **Auto** uses a configured API
key first and otherwise uses browser cookies. Choose **API key** or **Browser cookies** under **Usage source** to pin the
source; a rejected API key reports an error and does not switch to a different account.

### API key

Enter the key in **Settings → Providers → Command Code → API key** or set `COMMAND_CODE_API_KEY`. The settings value is
stored in QuotaKit's config file; see [provider fields](configuration.md#provider-fields). The `cmd login` key in
`~/.commandcode/auth.json` is not read by QuotaKit. API-key usage works on Linux without browser cookies.

For CLI usage, configure the key and run `quotakit usage --provider commandcode --json`. Use `--source api` to require
the API key or `--source web` to require browser or manual cookies.

### Browser cookies

1. Sign in to `https://commandcode.ai` in a supported browser.
2. Open Settings -> Providers -> Command Code.
3. Enable Command Code and leave Cookie source on Auto, or switch to Manual
   and paste a `Cookie:` header/cURL capture from Command Code, or just the session token value.

Bare tokens use the production cookie name `__Secure-commandcode_prod_.session_token`.
Explicit cookie pairs and full headers keep their names and additional cookies, including legacy better-auth names.

Automatic import looks for better-auth session cookies from `commandcode.ai` and
`www.commandcode.ai` in the shared supported-browser order. It validates each
session before reading the next browser, so an expired session does not mask a
later active one. Background refreshes never request Keychain permission; use an
explicit refresh to authorize a bounded retry if browser access is denied.

For cookie authentication on Linux, set `cookieSource` to `manual` and provide
the Command Code `Cookie` header in `cookieHeader`. Auto uses that header when no
API key is configured; choose Web to use cookies even when a key is present.
Automatic browser import is macOS-only.

## Display

- The menu bar item and provider card use the Command Code icon and label.
- The primary and secondary rows show 5-hour and weekly rolling usage.
- The tertiary row shows monthly credits used/remaining.
- Widgets do not expose Command Code in the provider picker yet.

## Related files

- `Sources/CodexBarCore/Providers/CommandCode/` - descriptor, cookie import,
  billing fetcher, snapshot mapping, and plan catalog.
- `Sources/CodexBar/Providers/CommandCode/` - settings store bridge and
  provider settings UI.
- `Tests/CodexBarTests/CommandCode*Tests.swift` - parser, cookie, settings,
  and icon coverage.
