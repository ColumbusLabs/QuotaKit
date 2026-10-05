---
summary: "LithosAI provider: prepaid console balance and optional daily/monthly spend."
read_when:
  - Configuring LithosAI billing visibility
  - Troubleshooting LithosAI console sessions or spend data
---

# LithosAI Provider

Enable LithosAI in **Settings → Providers**. QuotaKit reads the active organization's prepaid balance and billing
details from `console.lithosai.cloud`, with optional daily and month-to-date spend in UTC. LithosAI does not provide a
quota window or reset event for QuotaKit to track.

Sign in to the console in Chrome and choose **Automatic**, or choose **Manual** and paste a Cookie header containing
both `__Host-console_session` and `__Host-console_csrf` from the same signed-in session. Automatic import is limited to
Chrome and follows QuotaKit's browser-access gate. **Off** disables cookie access. Manual cookies are sent only to the
LithosAI console origin; inference API keys cannot read console billing.

An explicit refresh from Cookie source or the provider menu may make one bounded Keychain permission retry for one
browser. Scheduled refreshes stay noninteractive. If access remains blocked, QuotaKit reports which permission needs
attention and points to explicit refresh or the Manual cookie option. A validated session can complete a refresh
without writing cookies to the persistent cache. An expired session is rejected and the next available session is
tried; console permission denials do not evict the session.

## Console requests and privacy

The bundled plugin makes read-only GET requests:

- `/api/me` supplies the user and active organization.
- `/api/billing` supplies `balanceNanos`, `hasCard`, and `onHold`.
- `/api/billing/spend?start=YYYY-MM-DD&end=YYYY-MM-DD` supplies the inclusive UTC month-to-date range.

Billing requests include the active organization ID in `X-Organization-Id`. QuotaKit's host derives `X-Console-Csrf`
from `__Host-console_csrf` in the selected cookie session and adds it only for requests to the declared HTTPS console
origin. Cookie values remain opaque to the plugin. Both cookies must match the request URL; user-installed plugins
cannot enable this policy.

## Values shown

QuotaKit presents the prepaid USD balance, payment-card state, account hold state, and optional today's and
month-to-date spend. Money values are converted from integer nanodollars (1 USD = 1,000,000,000 nanos). Very small
positive balances are labeled as less than one cent. If the spend report is unavailable or malformed, the balance stays
visible and spend is labeled unavailable rather than reported as zero.

The Mac menu card uses the same balance for its automatic money value and explicit **Balance** token. The iPhone
companion receives the balance and detail rows through QuotaKit's existing sync snapshot. LithosAI has no quota resets,
so it does not use iPhone quota-alert subscriptions.

On Linux, automatic browser import is unavailable; use a manual Cookie header in QuotaKit settings. A CLI fetch can use
the configured web source with `quotakit usage --provider lithosai --source web --json`.

The console protocol was documented by [Apoorv Darshan's CodexBar issue #3868](https://github.com/steipete/CodexBar/issues/3868)
and informed by the [LithosAI Bar reference client](https://github.com/apoorvdarshan/lithosai-bar). QuotaKit implements its
own plugin and uses synthetic fixtures; it does not import that client's code.
