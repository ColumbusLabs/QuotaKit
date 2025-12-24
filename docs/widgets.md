---
summary: "WidgetKit snapshot pipeline for CodexBar widgets."
read_when:
  - Modifying WidgetKit extension behavior or snapshot format
  - Debugging widget update timing
---

# Widgets

## Snapshot pipeline
- `WidgetSnapshotStore` writes compact JSON snapshots to the app-group container.
- Widgets read the snapshot and render usage/credits/history states.

## Extension
- `Sources/CodexBarWidget` contains timeline + views.
- Keep data shape in sync with `WidgetSnapshot` in the main app.

See also: `docs/ui.md`.
