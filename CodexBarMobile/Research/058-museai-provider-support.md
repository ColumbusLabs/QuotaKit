# MuseAI provider support

**Status:** `in-progress` — implementation is in place; focused Mac and iOS verification remains pending.

## Goal

Add Muse (muse.ai) as a distinct quota provider across the Mac app, CloudKit notification catalog, iPhone app, and provider-selection surfaces. The existing `muse` identifier is Muse Code and remains unchanged.

## Implementation

- Register `museai` as the final `UsageProvider` case and generate the descriptor and implementation manifests. Its Mac implementation uses MuseAI's cookie-backed weekly quota source.
- Append `museai` to the shared quota push list, preserving all existing subscription zone names. The catalog now contains 72 quota providers and 216 state subscriptions.
- Add the MuseAI icon and color to iPhone branding, include it in quota-card coverage, and add it to the Burn Down widget's provider choices.
- Add the provider to the existing 1.11.4 release-notes block, the current iOS changelog entry, and all supported iOS localizations.

## Verification

Hosted GitHub CI owns the Mac and iOS tests, lint, manifest generation, and iOS project regeneration checks for this integration batch. Local builds and tests are intentionally omitted. Keep this research item `in-progress` until the root task confirms green CI. Provider validation uses parser fixtures and mocked HTTP only; real browser cookies and Keychain sessions are out of scope.
