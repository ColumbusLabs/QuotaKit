# iOS Refresh Feedback

Status: done  
Date: 2026-06-08

## Summary

The Usage and Cost tabs already supported pull-to-refresh, but the visual
feedback disappeared as soon as the pull control collapsed. The synced-time chip
also used a static relative date render, so it could sit at "3 seconds ago" for
minutes without a SwiftUI invalidation.

This change makes the sync chip an explicit refresh control and drives its age
labels from `TimelineView`. The displayed time remains anchored to the
Mac-generated `syncTimestamp`; iOS fetch completion time is not treated as a
confirmed sync.

## Decisions

- Store `SyncStatus.synced(lastConfirmedSync:)` as a timestamp, not a frozen
  duration.
- Derive all visible age strings with a deterministic formatter that accepts
  `now` for tests and `TimelineView` for live UI.
- Keep interactive full refreshes visibly `.syncing` until the coalesced
  CloudKit refresh completes.
- Show failed manual refreshes as stale-but-usable when a previous snapshot is
  still available.
- Founder Pro access stays on the official StoreKit path via App Store Connect
  offer codes; no local Pro backdoor is added.

## Verification

- Unit coverage checks second-by-second ticking, minute/hour/day thresholds,
  refreshing copy, failed-refresh copy, and stale-state calculation from an
  injected clock.
