# Codex Rolling Weekly Refresh Publication

**Status:** done
**Date:** 2026-08-13

## Problem

Codex can advance its rolling weekly boundary before the previously reported reset time. The existing reset-confirmation guard treated that valid, two-sample low-usage response as unsafe and retained the old snapshot indefinitely. Cost data could still update through a separate path, leaving the mobile quota percentage stale.

## Design

Publish a new Codex snapshot when the low weekly usage and advanced boundary are confirmed by two matching, current responses. Carry a publication policy into reset detection so this specific early rolling-window case updates quota and syncs normally without a false early weekly-reset event. Existing two-minute reset-boundary tolerance remains unchanged. Manual resets with explicit reset-credit evidence remain eligible for their existing immediate reset behavior.

The policy is persisted with the existing reset-detector state. Older state decodes with the new flag disabled, so no migration is required.

## Verification

- Confirmation tests cover validated early rolling windows, malformed or stale responses, account mismatches, boundary regressions, and manual reset credits.
- Publication tests assert the confirmed snapshot replaces the stale visible snapshot, clears its error, and records normal plan-utilization history without a reset event.
- Reset-detector tests assert a premature rolling boundary does not emit a reset event and remains compatible with the existing boundary-tolerance behavior.
