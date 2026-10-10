---
summary: "Langdock personal included-usage limits from a selected Edge, Chrome, or Safari profile."
provider_id: langdock
provider_name: Langdock
provider_source: Selected Edge, Chrome, or Safari profile → personal included session and weekly limits (`web`, macOS).
plugin_scope: Host-owned selected browser profile, live session revalidation, and personal tRPC limits on both engines; no quota history or widgets.
read_when:
  - Setting up Langdock in QuotaKit
  - Debugging Langdock profile or cookie access
---

# Langdock

QuotaKit reads the personal included-usage limits shown on Langdock's account Usage page. This
provider is disabled by default and supports macOS Edge, Chrome, and Safari profiles.

1. Sign in to Langdock in the Edge, Chrome, or Safari profile you want to monitor.
2. In QuotaKit's Langdock provider settings, choose the browser and signed-in profile.
   QuotaKit never chooses the first available profile automatically.
3. Enable Langdock, then refresh. The CLI equivalent is
   `quotakit usage --provider langdock --source web`.

QuotaKit reads only that profile's applicable `langdock.com` and `app.langdock.com` cookies.
Decrypted session values stay in memory and are not cached by QuotaKit. The existing SweetCookieKit
importer uses temporary copies of Chromium cookie databases while reading them; Safari cookies are
read from the selected concrete cookie file. This provider does not introduce another credential
store or switch to another profile if the selection is missing or its session expires. Chromium
decryption follows QuotaKit's existing Keychain access gates. Safari does not require a Keychain
prompt acknowledgement; macOS Full Disk Access may be needed to read Safari's cookie file.

If usage disappears after a restart, verify the saved browser and **Browser profile** selections in
QuotaKit; for Edge or Chrome, compare the selected profile with the path shown by `edge://version`
or `chrome://version`. An Edge or Chrome cookie-access error calls for a manual
Langdock refresh and a check of QuotaKit's Keychain access setting. If QuotaKit reports that it
cannot read a Chromium profile, check **Privacy & Security → Files & Folders** for the exact app
bundle being run. Development builds must use the matching signing identity before accessing
existing Keychain items. If Safari access is denied, grant Full Disk Access to that QuotaKit bundle.
A missing cookie store remains a separate profile or browser-data problem; QuotaKit does not try
another profile.

Langdock reports a five-hour session percentage and a seven-day weekly percentage. A disabled
session limit hides the session bar. Missing reset dates remain unknown. If Langdock returns a
valid response without included plan usage, QuotaKit shows “No included usage limits available.”
Extra Usage, workspace-wide billing, widgets, and stored quota history are outside this integration.
Stored history remains disabled because the usage response does not establish a stable account identity.
Session-bound measurements are also excluded from saved widgets, fleet CloudKit account exports, and iPhone sync. Langdock is not added to iPhone quota-alert subscriptions.

## Session ownership and refreshes

Each refresh checks the selected profile's session before and after the HTTP request. An in-memory
session fingerprint prevents a response from an earlier login from being published after a detected
session change. It is excluded from serialized snapshots and logs. A transient request failure can
retain the last measurement only when the current session still matches; its original age and an
error remain visible. A session change or an unverifiable session clears the old measurement.
Changes in the selected browser are detected on the next refresh; this provider does not monitor browser logins continuously.

QuotaKit uses its configured refresh interval. A manual refresh requests another server measurement;
the Langdock page and QuotaKit can differ while one is displaying an earlier measurement. The separate
pace/reserve indicator is QuotaKit's estimate, not an additional Langdock quota.

## Compatibility and review notes

- The request uses Langdock's internal `usageSettings.getPersonalUsage` web endpoint on
  `https://app.langdock.com`. It is not a documented public API and may change independently of QuotaKit.
- Missing `planUsage` is supported. A separately hidden Usage page has not been independently verified;
  the provider does not assume that a successful HTTP response proves page visibility.
- No administrator privileges, manual token entry, or access to the Langdock desktop app are needed.
- The bundled `langdock.ts` plugin owns requests, parsing, and error classification on JavaScriptCore and QuickJS.
  The generic host enforces selected-profile imports and post-request ownership checks; scripts never receive
  cookie values or session fingerprints. The `browserProfileID` provider config field stores the selection.
- The monochrome mark comes from the official [Langdock brand kit](https://langdock.com/brand-kit).
