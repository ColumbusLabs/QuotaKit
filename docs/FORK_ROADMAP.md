---
summary: "QuotaKit roadmap and product ownership notes."
read_when:
  - Planning QuotaKit product work
  - Reviewing milestones
  - Separating product work from upstream sync work
---

# QuotaKit Roadmap

QuotaKit is the Columbus Labs product for AI quota, usage, and spend tracking
across Mac and iPhone.

## Current Product Priorities

- Keep the Mac setup flow clear and branded through
  `https://columbus-labs.com/quotakit/mac`.
- Keep iPhone onboarding framed as a Mac setup handoff, not an iPhone download
  flow.
- Preserve local-first provider collection and private iCloud sync.
- Improve Pro widgets, alerts, cost history, and share cards without exposing
  sensitive provider data.
- Keep upstream provider fixes flowing in without inheriting upstream release or
  support surfaces.

## Near-Term Work

- Verify release scripts against the Columbus Labs GitHub release flow.
- Finalize QuotaKit Mac signing, notarization, and Sparkle appcast publishing.
- Keep iOS TestFlight/App Store notes aligned with the current QuotaKit product
  surface.
- Continue tightening public docs and support links as the first Columbus Labs
  releases go live.

## Medium-Term Work

- Expand provider detail surfaces where synced data already exists.
- Improve cost history and model mix explanations.
- Continue widget polish and entitlement-state reliability.
- Add focused provider improvements when they fit the privacy model.

## Sync And Upstream

Use `docs/UPSTREAM_STRATEGY.md` for inherited upstream review. Upstream work is a
source of fixes and provider support; QuotaKit product identity, releases, setup,
support, and sync policy remain Columbus Labs-owned.
