# Langdock session export boundary

Status: `done` — final exact-head implementation and hosted verification passed on `027900bcc75db61ab327e52bb926e11314c8bee1`; PR #226 merged as `d62d2c881bb8ce4192590723c28e0b5973eb57c9` ([hosted run](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37332130170)).

## Scope

Adopt the upstream selected-Edge-profile Langdock provider on Mac. Keep its measurements local because its personal-usage response does not establish a stable account identity. Preserve the existing iPhone quota catalog and shared CloudKit/notification contracts.

## Design

Append Langdock to the Mac registry and regenerate repository manifests without changing existing IDs. Preserve upstream explicit profile selection, cookie access gates, nonpersistent opaque sessions, and pre/post-request session ownership validation. Ownership fingerprints are live-only and never serialized or logged.

Apply the same session/export eligibility decision before iPhone envelope construction, token/multi-account capture, fleet account payload creation, and widget provider/account entries. Upstream widget-only exclusion does not cover QuotaKit's custom SyncCoordinator. Stable-account providers continue exporting normally. The shared raw-color catalog retains Mac palette parity for Langdock, without making it a mobile quota provider. No iPhone provider mark, quota subscription, app release note, build bump, or wire-schema migration is needed for this Mac-only provider.

## Verified evidence

Hermetic fixtures prove valid Langdock measurements cannot enter iPhone envelopes, fleet CloudKit payloads (including nil identity/default-account cases), or widget entries, and stable-account providers still export. Generated registry/palette checks verify an append-only Mac catalog (91), unchanged iPhone quota catalog (73), and unchanged state-zone subscriptions (219). The final exact-head hosted Mac, iOS/shared, Linux, lint, and Xcode compatibility gates passed, with independent adversarial source review clear. Final exact-head hosted CI run 37332130170 passed the applicable lint, Linux, macOS, iOS, and Xcode compatibility gates on PR #226 head `027900bcc75db61ab327e52bb926e11314c8bee1` ([run](https://github.com/ColumbusLabs/QuotaKit/actions/runs/37332130170)). PR #226 merged as `d62d2c881bb8ce4192590723c28e0b5973eb57c9`. Verified origin/main cursor and tail readback: `cursor=14567f0b6711ef38741cadd7ff20ef76a2053af2; fetched upstream=6a26b2e9b1b60471970deb6fe663f9e5f284e2ce; newer tail=20 DAG/7 non-merge commits outside the pinned reviewed range; UPSTREAM_VERSION=v0.69.0`. No real account, cookie, Keychain, or CloudKit probes.
