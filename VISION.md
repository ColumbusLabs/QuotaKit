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
