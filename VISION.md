# Vision

QuotaKit is the local-first control surface for AI provider limits, usage, spend,
status, and reset windows.

The product should stay practical: fast refreshes, clear quota state, private local
collection, iCloud sync to iPhone, and provider coverage that earns its complexity.

## Product Principles

- Track usage locally whenever possible.
- Sync only the data needed for the iPhone companion experience.
- Keep provider credentials, browser sessions, and local logs out of Columbus Labs
  infrastructure.
- Prefer shared provider-driven UI over one-off screens.
- Make setup flows Mac-first and clear, especially when the iPhone app depends on
  Mac-collected data.

## Merge By Default

- Bug fixes with clear cause and bounded risk.
- Performance improvements that do not add unnecessary complexity.
- New model/provider support that follows existing descriptor, strategy, settings,
  sync, and test patterns.
- Small UI and UX improvements.
- Documentation fixes that clarify the QuotaKit product boundary.

## Needs Sign-Off

- New product features.
- Package, dependency, or toolchain changes.
- Broad refactors or architecture changes.
- Behavior changes affecting provider auth, data storage, releases, sync, or user
  privacy.
- Provider additions that need new host APIs, bespoke UI, broad filesystem access,
  or unclear auth/privacy behavior.
- Changes that add meaningful maintenance complexity.

## Platform Scope

- macOS is the home of the UI: the menu bar app, widgets, and any future native surfaces.
- The CLI (`quotakit`) is cross-platform: macOS and Linux are supported today, with feature parity for usage, cost, serve, and hooks wherever platform APIs allow.
- Windows is an aspiration, not a commitment: if Swift's Windows support matures enough to stop fighting us, shipping the CLI (and eventually more) there would be welcome. Contributions keeping the core portable are valued now.
- Desktop-environment integrations beyond macOS (KDE widgets, GNOME extensions, etc.) belong in separate, community-maintained projects consuming `quotakit serve` or `quotakit usage --json`; we link good ones from the README rather than absorbing them.
