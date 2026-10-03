---
summary: "LithosAI provider: prepaid console balance and optional daily/monthly spend."
read_when:
  - Configuring LithosAI billing visibility
  - Troubleshooting LithosAI console sessions or spend data
---

# LithosAI Provider

QuotaKit reads the prepaid balance and billing details for the active organization in your LithosAI console. It can
also show optional daily and month-to-date spend in UTC. This is a balance and billing view; LithosAI does not provide
a quota window or reset event for QuotaKit to track.

Sign in to `console.lithosai.cloud` in Chrome and choose **Automatic**, or choose **Manual** and paste a Cookie header
containing both `__Host-console_session` and `__Host-console_csrf` from the same session. Automatic import is limited
to Chrome to avoid unrelated browser prompts. **Off** disables cookie access. Manual cookies are sent only to the
LithosAI console origin.

QuotaKit uses the console's active organization, showing its current prepaid USD balance, card status, and account
hold status. Daily and monthly spend are optional; if that report is unavailable, the balance remains visible and the
spend rows show as unavailable rather than implying zero usage. Billing values are converted from integer nanodollars.
Very small positive balances are labeled as less than one cent.

The Mac menu card presents the prepaid balance and notes that the billing ledger can lag current-cycle spend. The
iPhone companion receives the same balance and detail rows through the existing QuotaKit sync snapshot. LithosAI has no
quota resets, so it does not use iPhone quota-alert subscriptions.
