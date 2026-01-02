# Augment Cookie Auto-Refresh Fix

## ⚠️ IMPORTANT: You Need to Log In to Augment

Based on the debug logs, your Augment session is **expired in your browser**. The automatic retry logic is working correctly, but it can't help if your browser session is also expired.

**To fix this:**
1. Open https://app.augmentcode.com in Chrome (or your preferred browser)
2. Log in with your Augment credentials
3. Once logged in, CodexBar will automatically detect and use the fresh cookies
4. The automatic retry logic will keep your session fresh going forward

## Changes Made

### 1. Added Newly Discovered Session Cookie Names
**Added** `session` and `web_rpc_proxy_session` to the known session cookie names list (lines 14-28 of AugmentStatusProbe.swift). These are the actual cookies used by Augment as of 2026-01-02.

### 2. Improved Cookie Detection (AugmentStatusProbe.swift)
**Problem**: The cookie importer was too strict - it would only use cookies if they matched known session cookie names (like `auth0`, `auth0_compat`, etc.). If Augment changed their cookie names or used different ones, CodexBar would fail with "No Augment session cookie found" even though cookies existed.

**Solution**: Modified the cookie detection logic to be more lenient:
- Now accepts ANY cookies found for `augmentcode.com` domains
- Still logs which cookies are found for debugging
- Relies on the automatic retry logic to handle expired sessions
- If cookies are expired, the automatic retry will re-import fresh cookies from the browser

**Code change** (lines 54-74):
```swift
// Before: Only returned cookies if they matched known session cookie names
// After: Returns ANY cookies found, with helpful logging
if !matchingCookies.isEmpty {
    log("✓ Found known Augment session cookies in \(source.label): ...")
    return SessionInfo(cookies: httpCookies, sourceLabel: source.label)
} else if !httpCookies.isEmpty {
    // Even if we don't recognize the cookie names, try them anyway
    log("⚠️ Found \(httpCookies.count) cookies in \(source.label) but none match known session cookies")
    log("   Cookie names found: \(cookieNames)")
    log("   Attempting to use these cookies anyway - will auto-refresh if expired")
    return SessionInfo(cookies: httpCookies, sourceLabel: source.label)
}
```

### 2. Automatic Session Refresh Already Implemented
The code already has excellent automatic retry logic (lines 327-385):
1. Attempts to fetch usage with current cookies
2. If session expires (HTTP 401), automatically imports fresh cookies from browser
3. Retries the request once with fresh cookies
4. If still failing, shows helpful error message

## How to Use

### Enable Augment in CodexBar
1. Click the CodexBar menu bar icon
2. Click "Preferences..."
3. Go to the "Providers" tab
4. Find "Augment" in the list and check the box to enable it
5. Make sure "Cookie source" is set to "Automatic" (default)

### Verify It's Working
1. Make sure you're logged into https://app.augmentcode.com in your browser (Chrome, Arc, Safari, etc.)
2. CodexBar will automatically import cookies from your browser
3. If cookies expire, CodexBar will automatically re-import fresh ones
4. Check the Console.app logs for detailed debugging info (filter by "CodexBar" or "augment")

### Troubleshooting

**"No Augment session cookie found"**
- Make sure you're logged into app.augmentcode.com in a supported browser
- Supported browsers (in order): Arc, Chrome, Brave, Edge, Safari, Firefox, Opera
- Try logging out and back in to Augment
- Check Console.app logs to see which cookies were found

**"Session has expired" error**
- This should auto-recover now! The code will automatically re-import cookies
- If it persists, your browser session at app.augmentcode.com is also expired
- Log in again at https://app.augmentcode.com

**Still not working?**
- Check Console.app logs (filter by "CodexBar" or "augment")
- Look for lines like:
  - `[augment-cookie] Found X cookies in [browser]: ...`
  - `[augment] Attempting API request with cookies from ...`
  - `[augment] ⚠️ Session expired (HTTP 401), attempting automatic cookie refresh...`
- Share these logs for further debugging

## Technical Details

### Cookie Import Order
CodexBar tries browsers in this order (from `ProviderBrowserCookieDefaults.swift`):
1. Arc
2. Chrome
3. Brave
4. Edge
5. Safari
6. Firefox
7. Opera

### Cookie Domains Searched
- `augmentcode.com`
- `login.augmentcode.com`
- `.augmentcode.com`

### Known Session Cookie Names
The code knows about these cookie names (but will now accept others too):
- `session` - Main session cookie (discovered 2026-01-02)
- `web_rpc_proxy_session` - Web RPC proxy session (discovered 2026-01-02)
- `_session` - Legacy session cookie
- `auth0` - Auth0 session
- `auth0.is.authenticated` - Auth0 authentication flag
- `a0.spajs.txs` - Auth0 SPA transaction state
- `__Secure-next-auth.session-token` - NextAuth secure session
- `next-auth.session-token` - NextAuth session
- `__Host-authjs.csrf-token` - AuthJS CSRF token
- `authjs.session-token` - AuthJS session

### API Endpoints
- Credits: `https://app.augmentcode.com/api/credits`
- Subscription: `https://app.augmentcode.com/api/subscription`

## Next Steps

If you're still having issues:
1. Check if the cookies are being found (Console.app logs)
2. Verify the cookie names match what Augment actually uses
3. Test with manual cookie mode to isolate the issue
4. Share Console.app logs for further debugging

