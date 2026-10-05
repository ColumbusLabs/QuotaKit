# Langdock session export boundary

Status: `implementing` — source adaptation and hosted verification pending.

## Scope

Adopt the upstream selected-Edge-profile Langdock provider on Mac. Keep its measurements local because its personal-usage response does not establish a stable account identity. Preserve the existing iPhone quota catalog and shared CloudKit/notification contracts.

## Design

Append Langdock to the Mac registry and regenerate repository manifests without changing existing IDs. Preserve upstream explicit profile selection, cookie access gates, nonpersistent opaque sessions, and pre/post-request session ownership validation. Ownership fingerprints are live-only and never serialized or logged.

Apply the same session/export eligibility decision before iPhone envelope construction, token/multi-account capture, fleet account payload creation, and widget provider/account entries. Upstream widget-only exclusion does not cover QuotaKit's custom SyncCoordinator. Stable-account providers continue exporting normally. The shared raw-color catalog retains Mac palette parity for Langdock, without making it a mobile quota provider. No iPhone provider mark, quota subscription, app release note, build bump, or wire-schema migration is needed for this Mac-only provider.

## Required evidence

Hermetic fixtures prove valid Langdock measurements cannot enter iPhone envelopes, fleet CloudKit payloads (including nil identity/default-account cases), or widget entries, and stable-account providers still export. Generated registry/palette checks prove an append-only Mac catalog (91), unchanged iPhone quota catalog (73), and unchanged state-zone subscriptions (219). Hosted iOS/shared and Mac checks plus independent adversarial source review must pass on the final integration head. No real account, cookie, Keychain, or CloudKit probes.
