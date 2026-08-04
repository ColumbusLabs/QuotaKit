# Provider Daily Spend Model Details

Status: done

## Goal

On the provider detail screen, selecting a Daily Spend bar should show the
selected day's total cost/tokens and the per-model cost/token breakdown that
the Mac cost-history view exposes.

## Contract

- Use the existing `SyncDailyPoint.modelBreakdowns` payload; no wire-schema or
  SwiftData migration is required.
- Select the newest valid day initially. Taps and horizontal scrubbing update
  the selected day and preserve it after the gesture ends.
- Sort model rows by cost descending, then model tokens descending, then label.
- Show model tokens only when the payload attributes them. Never allocate a
  day's aggregate tokens proportionally from model cost.
- Preserve optional Codex Standard/Fast cost and token fields and estimated
  pricing state.
- Keep the detail viewport stable while scrubbing, with four visible rows and
  scrolling for additional models.

## Compatibility and merge behavior

Older Mac payloads may contain model cost without model tokens. Multi-Mac
cost-summary merging must retain model token, Standard/Fast, and estimated
metadata when combining same-day model labels.

## Verification

- Presentation ordering/fallbacks, stable viewport sizing, accessibility
  values, and latest-day selection are covered by mobile unit tests.
- Same-day multi-Mac metadata, legacy compatibility, and split-tier merging are
  covered by CloudKit merge tests.
- The preview-backed UI test covers the chart selection surface and model rows;
  the generic iOS device test build compiles all unit/UI test bundles.
- The full lint/localization gate and repository test gate pass. Simulator
  execution remains host-blocked because no iOS simulator runtime is available.
