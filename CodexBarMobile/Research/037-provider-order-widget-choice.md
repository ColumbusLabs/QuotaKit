# Provider Order + Widget Provider Choice

Status: done
Date: 2026-06-17

## Summary

QuotaKit iOS now lets users organize provider groups from the Usage tab and
choose the provider shown in all QuotaKit widgets. Widgets stay on
`StaticConfiguration`; the app writes provider preferences to app-group defaults
and reloads WidgetKit timelines after changes.

## Decisions

- Keep provider choice global across all widgets instead of adding per-widget
  AppIntent configuration.
- Store provider preferences in app-group defaults so the iOS app and widget
  extension read the same state.
- Persist provider order by providerID at the provider-group level; account tabs
  inside a provider keep their existing order.
- Treat a missing or invalid widget provider selection as a fallback to the
  saved provider order, then the current snapshot order.
- Apply preferences both when publishing widget snapshots and when the widget
  reads an already-saved snapshot, so app changes are reflected immediately.

## Verification

- Preference-store tests cover round-trip, sanitization, app-group isolation,
  ordering, and fallback selection.
- Widget snapshot tests cover selected-provider priority, saved-order fallback,
  and read-time preference application.
- View smoke coverage renders the Usage list with the new controls through the
  existing QuotaKit Pro smoke tests.
- Changelog and in-app release notes mention widget provider choice and inline
  provider ordering.
