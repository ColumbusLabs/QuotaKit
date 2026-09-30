---
summary: "Retired Crof provider compatibility for historical iCloud records and preserved configuration."
read_when:
  - Reviewing historical Crof sync records or stored settings
---

# Crof support retired

QuotaKit no longer provides live Crof usage on macOS. Crof is absent from the active provider catalog and has no
current settings, credential import, or usage-fetch path. This page documents data compatibility only.

## Preserved compatibility

- The shared Crof provider identifier remains available for historical iPhone and iCloud records. Those records are
  retained as opaque data so existing sync data can roundtrip without the Mac app interpreting or deleting it.
- Configuration for unavailable providers is preserved as opaque data during config read/write. Existing Crof-specific
  values may therefore roundtrip, but they do not expose Crof in Settings, trigger a request, or restore live support.
- The iPhone and shared sync compatibility data remain in place for records created before the macOS provider was
  retired. New live Crof usage is not produced by QuotaKit.

## Historical behavior

Before retirement, the macOS provider queried `GET https://crof.ai/usage_api/` with a bearer API key and read the
`credits` field plus optional `requests_plan` and `usable_requests` fields. That describes the former implementation;
QuotaKit no longer makes this request.
