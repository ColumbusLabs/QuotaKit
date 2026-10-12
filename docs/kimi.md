---
summary: "Kimi provider notes: cookie auth, quotas, and rate-limit parsing."
read_when:
  - Adding or modifying the Kimi provider
  - Debugging Kimi cookie import or usage parsing
  - Adjusting Kimi menu labels or settings
---

# Kimi Code Provider

Tracks usage for [Kimi For Coding](https://www.kimi.com/code) in QuotaKit.

Kimi Code is distinct from the Moonshot/Kimi Open Platform. China-issued Open Platform keys and balance
belong under **Moonshot / Kimi Open Platform** with the China mainland region selected; they are not Kimi
Code subscription credentials.

## Features

- Displays weekly request quota (from membership tier)
- Shows current 5-hour rate limit usage
- Enriches Code API/CLI usage with the monthly membership pool when a web session is available
- Automatic menu-bar usage prioritizes an exhausted monthly Total usage pool over reset Code windows; explicit window selections remain authoritative
- API-key, Kimi Code CLI, automatic cookie, and manual cookie authentication methods
- Automatic refresh countdown

## Setup

Select **Region** in Settings → Providers → Kimi before configuring credentials. **China (kimi.com)** is
the default for existing installs; **International (kimi.ai)** selects the overseas service. The selection
controls Code API and web requests, cookie discovery, Open Console, and Usage Dashboard. Use credentials
issued for the selected region.

The app and CLI share the `providers[].region` config key:

```json
{"id":"kimi","region":"international","source":"api","apiKey":"<REDACTED>"}
```

Use `"china"` or omit `region` to retain the default. The regional Code API hosts are `api.kimi.com` and
`api.kimi.ai`; the web and console hosts are `www.kimi.com` and `www.kimi.ai`. Examples below use China URLs.

Choose one of four authentication methods:

### Method 1: Kimi Code API Key (Recommended)

Create an API key in the [Kimi Code Console](https://www.kimi.com/code/console), then save it in QuotaKit:

```bash
quotakit config set-api-key --provider kimi --api-key "kimi-api-key-here"
```

Or provide it through the environment:

```bash
export KIMI_CODE_API_KEY="kimi-code-api-key-here"
```

QuotaKit calls the selected region's `/coding/v1/usages` API with the key. Set
`KIMI_CODE_BASE_URL` only when testing a compatible HTTPS proxy or alternate host with an explicit API key.
QuotaKit never forwards a Kimi Code CLI credential to an endpoint override or to the International host.
Numeric legacy fields outside the integer range decode safely; unusable request counts do not create quota windows.

Both the older count-based response and the newer `usages` ratio pools are supported. Ratio pools supply
the 5-hour, weekly, and monthly Total usage windows they provide. When reliable legacy counts describe
the same duration and reset time (within two seconds), the more-exhausted reading wins, even when a
monthly pool is present or the ratio is nonzero. Equal readings retain the ratio pool's precision and
metadata; mismatched or unknown reset periods never borrow counts. Missing windows stay absent, and
ratio percentages do not imply request counts. The monthly Total usage pool is available directly from
the Code API, without requiring browser authentication, and optional web enrichment cannot replace it.
Legacy rate-limit counts remain available when no 5-hour ratio is reported.

### Method 2: Kimi Code CLI

In the default China region, if you are signed in with the official Kimi Code CLI, Auto mode can reuse its fresh
access token from `~/.kimi-code/credentials/kimi-code.json`. QuotaKit sends the same device identity headers as the CLI,
including the local hostname, OS details, and stable `~/.kimi-code/device_id` value. If that device ID is
missing, QuotaKit creates it with private file permissions to match the official client.

QuotaKit treats CLI-owned authentication as read-only: it never uses the refresh token and never rewrites
the credential file. When the access token expires, sign in again with Kimi Code CLI or configure an API
key. Set `KIMI_CODE_HOME` only when the official CLI uses a non-default home directory.

Custom `KIMI_CODE_BASE_URL`, `KIMI_CODE_OAUTH_HOST`, and `KIMI_OAUTH_HOST` values disable CLI credential
reuse; use an explicit API key for endpoint-override testing.
The current CLI credential file does not identify its issuing host, so switching to International disables
automatic CLI credential reuse. Configure an International API key or use a `kimi.ai` web session instead.

### Method 3: Automatic Discovery

**No setup needed!** If you're already logged in to Kimi in Arc, Chrome, Safari, Edge, Brave, or Chromium:

1. Open QuotaKit settings -> Providers -> Kimi
2. Set "Cookie source" to "Automatic"
3. Enable the Kimi provider toggle
4. QuotaKit will automatically find your session

Automatic mode prefers the current China Kimi Desktop access token from its primary Local Storage profile.
Expired or invalid Desktop JWTs are skipped; if the Kimi service rejects a Desktop session, the Web source
continues through browser profiles instead of stopping.

For China, Desktop discovery reads only the exact `https://www.kimi.com` / `access_token` record in
`~/Library/Application Support/kimi-desktop/Local Storage/leveldb`. The shared reader follows the current
LevelDB manifest and sequence numbers, honors deletions, and rejects incomplete or changing reads and
symlinked profile paths. Only a bare, unexpired access JWT with the `kimi.com` audience is accepted.
QuotaKit does not scan historical tokens, import refresh tokens, or fall back to old China Desktop cookies.

The acquired Desktop session is checked again before each web request. A deleted, replaced, expired, or
unreadable session stops further requests with that credential. Confirm the intended account is signed in
to Kimi Desktop, then refresh QuotaKit to acquire it again. Successful Code API or CLI quota results remain
available when this optional membership enrichment is unavailable. These local checks do not verify JWT
signatures or revoke requests already sent; the Kimi service authenticates the token.

International retains its existing read-only Desktop cookie discovery. Its Cookies database uses
WAL-aware SQLite reads, with an immutable fallback for idle WAL-mode databases that have no sidecars.
International Desktop Local Storage is not imported, and QuotaKit never creates or modifies Desktop
database files.

For the selected region, Automatic mode also reads `access_token` from Chromium browser local storage
through the shared browser catalog after cookie discovery. Tokens stay bound to the selected Kimi origin;
expired or malformed tokens are skipped. QuotaKit never reads or refreshes browser refresh tokens. Open
Kimi in your browser to renew an expired session, or use a Kimi Code API key for unattended use.
Safari and Firefox local storage are not imported.

**Note**: Reading browser cookies requires Full Disk Access (System Settings -> Privacy & Security -> Full Disk Access -> QuotaKit).

### Method 4: Manual Token Entry

For advanced users or when automatic import fails:

1. Open QuotaKit settings -> Providers -> Kimi
2. Set "Cookie source" to "Manual"
3. Visit `https://www.kimi.com/code/console` in your browser
4. Open Developer Tools (F12 or Cmd+Option+I)
5. Go to **Application** → **Cookies**
6. Copy the `kimi-auth` cookie value (JWT token)
7. Paste it into the "Auth Token" field in QuotaKit

### Multiple Web Accounts

In Settings → Providers → Kimi, use **Kimi accounts** to save labeled `kimi-auth` tokens or Cookie headers.
Select an account in the shared account editor; the CLI also supports `--account <label>`,
`--account-index <index>`, and `--all-accounts`. Saved accounts use the selected Kimi region and each
request sends only that account's cookie. Selecting one temporarily uses the web source and manual cookie
settings without changing your saved usage-source or cookie-source preferences. An invalid account fails
on its own and cannot fall back to another cookie, API key, or browser session.

Saved accounts work with the HTTP web endpoint on Linux and do not need browser-cookie import support.
The account list uses the existing `providers[].tokenAccounts` configuration; Kimi and Kimi Open Platform
credentials remain separate. Add accounts issued for the selected region because a single Kimi provider
setting cannot mix China and International sessions. Kimi usage responses do not currently provide account
emails, so QuotaKit uses each saved account's label as the existing token-account sync identity. Distinct,
non-empty labels can sync as separate iPhone entries; if labels collide after case/whitespace normalization,
sync safely keeps only the selected account for that push. Labels containing `|` remain supported by the
existing record-name format and iPhone deletion parser.

### Cookie Environment Variable

Alternatively, set the `KIMI_AUTH_TOKEN` environment variable:

```bash
export KIMI_AUTH_TOKEN="jwt-token-here"
```

## Authentication Priority

When multiple sources are available, QuotaKit uses this order:

1. API key (`providers[].apiKey` or `KIMI_CODE_API_KEY`) in Auto mode
2. Fresh Kimi Code CLI access token (`~/.kimi-code/credentials/kimi-code.json`)
3. Manual cookie/token (from Settings UI) when web fallback is used
4. Cookie environment variable (`KIMI_AUTH_TOKEN`)
5. Current China Kimi Desktop Local Storage access token (International retains its `kimi-auth` cookie)
6. Browser cookies (Arc → Chrome → Safari → Edge → Brave → Chromium)
7. Chromium local storage `access_token` for the selected region

For Code API and CLI results, sources 3–7 are best-effort enrichment only: the required Code usage remains
available if the membership request fails. Setting **Cookie source** to **Off** disables this enrichment and
does not inspect Kimi Desktop or browser cookies.

**Note**: Browser cookie import requires Full Disk Access permission.

Setting **Cookie source** to **Off** prevents browser import on every Kimi path. Context-free token resolution is
limited to explicit environment values; only the provider's settings-aware web strategy may inspect browsers.

## API Details

### Kimi Code API key

**Endpoint**: `GET https://api.kimi.com/coding/v1/usages`

**Authentication**: Bearer token (from `providers[].apiKey`, `KIMI_CODE_API_KEY`, or a fresh Kimi Code CLI credential)

**Response**:
```json
{
  "usage": {
    "limit": "2048",
    "used": "214",
    "remaining": "1834",
    "resetTime": "2026-01-09T15:23:13.716839300Z"
  },
  "limits": [{
    "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
    "detail": {
      "limit": "200",
      "used": "139",
      "remaining": "61",
      "resetTime": "2026-01-06T13:33:02.717479433Z"
    }
  }]
}
```

### Kimi web cookie fallback

**Endpoint**: `POST https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages`

**Authentication**: Bearer token (from `kimi-auth` cookie)

**Response**:
```json
{
  "usages": [{
    "scope": "FEATURE_CODING",
    "detail": {
      "limit": "2048",
      "used": "214",
      "remaining": "1834",
      "resetTime": "2026-01-09T15:23:13.716839300Z"
    },
    "limits": [{
      "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
      "detail": {
        "limit": "200",
        "used": "139",
        "remaining": "61",
        "resetTime": "2026-01-06T13:33:02.717479433Z"
      }
    }]
  }]
}
```

## Membership Tiers

| Tier | Price | Weekly Quota |
|------|-------|--------------|
| Andante | ¥49/month | 1,024 requests |
| Moderato | ¥99/month | 2,048 requests |
| Allegretto | ¥199/month | 7,168 requests |

All tiers have a rate limit of 200 requests per 5 hours.

## Troubleshooting

### "Kimi auth token is missing"
- Ensure "Cookie source" is set correctly
- If using Automatic mode, verify you're logged in to Kimi in your browser
- Grant Full Disk Access permission if using browser cookies
- Try Manual mode and paste your token directly

### "Kimi auth token is invalid or expired"
- Your token has expired. Paste a new token from your browser
- If using Automatic mode, log in to Kimi again in your browser

### "Kimi Desktop session changed before the request was sent"
- Confirm the intended account is signed in to Kimi Desktop, then refresh QuotaKit.
- The next refresh reads the current session again; no restart is needed.

### "No Kimi session cookies found"
- You're not logged in to Kimi in any supported browser
- Grant Full Disk Access to QuotaKit in System Settings

### "Failed to parse Kimi usage data"
- The API response format may have changed. Please report this issue.

## Implementation

- **Core files**: `Sources/CodexBarCore/Providers/Kimi/`
- **UI files**: `Sources/CodexBar/Providers/Kimi/`
- **Login flow**: `Sources/CodexBar/KimiLoginRunner.swift`
- **Tests**: `Tests/CodexBarTests/KimiProviderTests.swift`
