# Changelog

Notable QuotaKit Mac and cross-platform release changes are documented here.

Older upstream history is intentionally preserved in Git, but this file now focuses
on Columbus Labs QuotaKit releases and product-facing changes.

## 2026-06-07 — QuotaKit Public Repo Cleanup

### Changed

- Reframed the public repository around QuotaKit and Columbus Labs.
- Updated release scripts, appcast metadata, setup links, support links, and About
  surfaces to point at `ColumbusLabs/QuotaKit` and `columbus-labs.com/quotakit/mac`.
- Replaced inherited fork/setup documentation with QuotaKit-specific guidance.
- Removed stale standalone localized release-note artifacts that no longer represent
  the current product surface.

### Notes

- Historical upstream commits and contributor attribution remain in Git history.
- Internal target names such as `CodexBar` and `CodexBarCore` are still implementation
  identifiers; they are not the public product name.

## 0.32.4.1 / iOS 1.11.1 — 2026-06-07

### Changed

- Added the Columbus Labs Mac setup handoff at
  `https://columbus-labs.com/quotakit/mac`.
- Updated iOS onboarding and update prompts so iPhone users share or copy the setup
  page instead of being sent directly to a GitHub download page.
- Kept the actual Mac artifact distribution on GitHub Releases while making the
  user-facing handoff branded and Mac-first.

## 0.32.4.1 / iOS 1.11.0 — 2026-06-03

### Changed

- Paired the Mac app with iOS 1.11.0.
- Improved synced provider data quality and iPhone navigation with provider search.
- Kept CloudKit and sync wire formats compatible across mixed Mac and iPhone versions.

## 0.31.0.2 / iOS 1.10.0 — 2026-06-02

### Fixed

- Forced cost caches to re-scan after the parser update so Codex and Claude cost
  cards report fresh values instead of stale cached attribution.

## 0.31.0.1 / iOS 1.10.0 — 2026-05-30

### Added

- Added DeepSeek web-session usage and cost summaries on iOS.
- Added synced Codex Spark and Antigravity quota lanes.
- Improved cost cards with request counts and synced currency display.

## 0.29.0.1 / iOS 1.9.0 — 2026-05-27

### Added

- Added synced support for Azure OpenAI, Alibaba Token Plan, and T3 Chat.
- Added cost-history improvements, model breakdowns, and provider detail updates.

### Notes

- Older product and upstream release details remain available in repository history.
