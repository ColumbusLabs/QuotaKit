---
summary: "Track a Charm Hyper account's current Hypercredits balance on Mac and iPhone."
read_when:
  - Setting up Charm Hyper in QuotaKit
  - Reviewing Hyper session or API-key behavior
---

# Charm Hyper

QuotaKit can show the current Hypercredits balance for a Charm Hyper account. The provider is opt-in and reports the
balance as credits; it does not convert Hypercredits into currency or infer a quota window.

## Set up a source

Enable Charm Hyper under **Settings → Providers**, then choose a source:

- **Automatic** uses the selected Chrome session first and falls back to an API key when available.
- **Manual** uses a saved Cookie header from a signed-in `hyper.charm.land` request, then falls back to an API key.
- **Off** disables browser cookies; an API key can still be used.
- **Web** is session-only. **API** skips cookies and uses the API key.

API keys can be stored in QuotaKit's secure provider settings or supplied with `HYPER_API_KEY`. Browser cookies and API
keys are sent only to `https://hyper.charm.land/v1/credits`. If Hyper rejects a cached automatic session, QuotaKit
invalidates that session before trying the API-key fallback.

The balance is shown on Mac and included as an optional field in the existing iCloud provider snapshot so the iPhone
can render the same credits balance. Older synced snapshots without this field remain readable.
