# 038 - Mac Battery Status

Status: done

## Goal

Add a small iPhone-only sync surface for Mac battery state. The Mac app should
capture and publish its current battery percentage and power state, but it should
not add a Mac UI affordance for this side addition.

## Placement

The mobile app surfaces the value in Settings -> About & Sync -> Devices. Each
device row keeps its existing sync time and provider count, then adds a compact
battery icon plus text such as `82%`, `82% charging`, or `82% plugged in` when
the Mac has a displayable battery reading.

## Sync Design

- Mac snapshots include optional `powerStatus` for backward compatibility with
  legacy monolithic records.
- Mac also writes a standalone `DeviceStatus` record into `DeviceProvidersZone`
  so battery-only changes can reach iPhone through the existing zone
  subscription without requiring a provider data change.
- iPhone full refresh, incremental refresh, and widget background refresh fetch
  and overlay `DeviceStatus` onto device metadata.
- Unknown future power-state strings decode as `.unknown` so older mobile builds
  skip or degrade the battery label instead of dropping the whole payload.

## Verification

Implemented with focused sync-model, cache, coordinator, widget-refresh, and
localization coverage. Build verification is recorded in the implementation
handoff.
