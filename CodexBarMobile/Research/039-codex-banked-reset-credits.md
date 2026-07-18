# 039 — Codex banked reset credits on iPhone

Status: done

## Goal

Show an account's banked Codex rate-limit resets in the iPhone provider detail
screen, including the backend-authoritative available count and the exact
expiration date, year, time, and time zone for every available detail row.

This is a read-only companion surface. It does not expose reset consumption,
does not add widget data, and is not gated behind QuotaKit Pro.

## Backend and wire evidence

The Mac Codex fetch path already exposes `SyncCodexResetCredits` in the shared
provider payload. Its `availableCount` is authoritative; the accompanying
`credits` array can be partial. `ProviderUsageSnapshot.codexResetCredits` is an
optional, Codable field inside the existing compressed provider payload, so
this addition requires neither a CloudKit Production schema field nor a
provider payload-version bump.

## Mobile design

- CloudKit multi-Mac merge takes the latest non-nil reset-credit snapshot for a
  logical Codex account. It never unions credit rows or sums available counts.
- SwiftData mirrors the optional value as a JSON blob. Nil remains compatible
  with existing stores and older Mac payloads, and an update can clear it.
- Ghost filtering retains a Codex provider with available reset inventory even
  when it has no ordinary rate windows.
- The provider-detail dispatcher adds a small, value-driven reset-credit card
  for Codex accounts with a positive authoritative count.
- Detail rows include only currently available, unexpired credits, ordered by
  earliest known expiration. Credits with no expiration follow dated rows.
- When fewer current detail rows exist than the authoritative count, the card
  explicitly reports that only part of the expiration detail is available.
- Exact expiration formatting uses the user's locale and includes the year,
  clock time through seconds, and current time-zone name.

## Compatibility

- Older Mac payloads decode with `codexResetCredits == nil` and show no card.
- Older iPhone builds ignore the additive optional payload key.
- Existing SwiftData stores lightweight-migrate because the blob is optional.
- Inventory remains account-scoped through the existing provider/account
  composite key.

## Verification

Focused coverage is required for:

- latest-non-nil multi-device merge without union or summation;
- SwiftData encode, decode, update-to-nil, and store reopen;
- reset-credit-only ghost retention;
- dispatcher visibility and card date formatting/rendering;
- shared filtering, authoritative-count, and ordering semantics;
- localization audit plus iOS test build.

Mark this document `done` only after those checks pass.
