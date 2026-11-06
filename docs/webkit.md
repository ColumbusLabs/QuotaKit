---
summary: "WebKit usage in QuotaKit: WebView hosts, cookie stores, and teardown guidance."
read_when:
  - Touching WebKit-backed login windows or offscreen scraping
  - Debugging WebKit teardown crashes (especially x86_64)
  - Changing WebKit window lifecycle behavior
---

# WebKit usage

QuotaKit uses WebKit in two places:
- Visible purchase windows (e.g. credits purchase).
- Offscreen WebViews for OpenAI dashboard scraping.

## Persistent data and cache maintenance

WebKit keeps account sessions in QuotaKit’s app-specific WebsiteDataStore directory.
Named stores use a deterministic UUID derived from normalized email and the Codex source scope
(managed account ID or profile home). The default store holds sessions without a known account email.
Cookies, local storage and IndexedDB remain available across refreshes and app launches.

At launch, QuotaKit clears only WebKit disk and memory caches in existing named stores, including stores whose
account mapping is unknown. It does not create a default store just for maintenance. Background dashboard views
request the same cleanup when released, including the default store, at most once per store per day.
Same-day refreshes retain HTTP asset reuse; the first refresh after cleanup may
download those assets again. Cookies, local storage and IndexedDB are excluded from this maintenance.

Automatic maintenance skips WebKit stores in test processes. Tests exercise cleanup through fake stores instead,
so app-launch tests never enumerate or modify persistent WebKit data.

Ordinary dashboard leases release their WebView after each refresh. Cookie validation can retain a
loaded page for a single immediate handoff, expiring after five seconds. WebKit controls when its helper
processes exit; releasing a view is not a guarantee that its process immediately disappears.

## Teardown helper

Use `WebKitTeardown` whenever a `WKWebView` + `NSWindow` should be torn down or hidden.
It centralizes Intel-friendly cleanup:
- Stops loading and clears delegates.
- Delays teardown so WebKit can unwind callbacks.
- Keeps owners retained briefly on x86_64 to avoid autorelease crashes.

## When to use

- Any WebKit window that closes after a flow (login, purchase, etc.).
- Offscreen WebView hosts that hide/close after scraping.

## Notes

- For login flows that persist cookies manually, prefer `WKWebsiteDataStore.nonPersistent()`.
- Keep window `isReleasedWhenClosed = false` when teardown is deferred.
- Avoid closing WebViews directly; route cleanup through the helper.
