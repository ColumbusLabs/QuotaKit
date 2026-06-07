# 031 — Mac Pace Parity

- **Status:** `done`
- **Date:** 2026-06-07
- **Scope:** Mac sync bridge, iOS usage cards, provider detail cards, and widgets

## Problem

The Mac menu card shows quota pace — for example “in deficit”, “in reserve”, “runs out in”, and “lasts until reset” — so users can see whether current usage is ahead of or behind the reset-window pace. iOS only showed percent used/remaining and reset timing, which made the phone view less useful than the Mac view.

## Decision

Sync the Mac-resolved pace result with each eligible rate window instead of recomputing it on iPhone. This keeps iOS aligned with Mac’s session, weekly, Abacus, and Codex historical pace behavior.

## Implementation

- `SyncRateWindow` now carries optional `SyncUsagePace` metadata with Mac-rendered labels and numeric expected/actual usage.
- Mac `SyncCoordinator` populates session and weekly pace using the same `UsagePaceText` / `UsageStore.weeklyPace` paths as the menu card.
- iOS usage cards render the pace label pair and a Mac-style expected-usage stripe on the bar.
- Widgets cache and render pace text in small, medium, and accessory rectangular families.

## Validation

- Shared model round-trip and old-payload decode tests cover the additive pace field.
- Mac mapper tests pin session deficit and weekly reserve text.
- iOS display tests cover used/remaining marker placement and on-track marker suppression.
