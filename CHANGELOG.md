# Changelog

Notable QuotaKit Mac and cross-platform release changes are documented here.

Older upstream history is intentionally preserved in Git, but this file now focuses
on Columbus Labs QuotaKit releases and product-facing changes.

## Upcoming

### Changed

- Synced upstream CodexBar Mac improvements through `0.35.1` development
  (`1d39e0ca..2e4b3556`), including Antigravity quota-summary pooling,
  transient launch retries, Linux HTTP probing, Gemini API-key auth recognition,
  MiMo balance/token usage, local session-log fallback, prompt refresh failures,
  browser-cookie isolation hardening, weekly pace work-day configuration,
  open-menu usage refresh, status-menu appearance fixes, editable cost-history
  settings, Command Code credit resilience, and release dSYM/Sparkle signing-path
  validation helpers.

## 0.32.4.5 / iOS 1.11.1 — 2026-06-11

### Changed

- Synced trusted upstream CodexBar Mac improvements after `v0.32.4`, including
  Codex account/auth hardening, MiniMax quota fixes, menu performance updates,
  merged provider-switching hang fixes, Claude probe cleanup,
  Antigravity/Alibaba/Cursor fixes, and additional Mac localizations.
- Synced upstream CodexBar Mac improvements through `0.33.1` development,
  including a security fix that blocks credentialed provider redirects leaving
  the original HTTPS origin, a new Devin usage provider, Cursor legacy
  request-quota and Full Disk Access hint fixes, Copilot unlimited chat quota
  display, Codex cost visibility without quotas, updated Claude usage pricing
  and web session recovery, Doubao false-exhaustion fixes, cost scanner
  threading and cancellation overhauls, broad menu performance and
  width-stability work, a configurable terminal app for Open Terminal, expanded
  MiMo browser support, and Japanese localization.

## 0.32.4.4 / iOS 1.11.1 — 2026-06-08

### Fixed

- Show the QuotaKit app symbol in the Mac menu bar before the first quota
  snapshot is available, instead of rendering an empty initial status item.
- Updated the menu bar visibility guidance to use QuotaKit product naming.

## 0.32.4.3 / iOS 1.11.1 — 2026-06-08

### Fixed

- Renamed the shipped Mac app bundle, executable, widget extension, and bundled
  CLI helper to QuotaKit-branded runtime names.
- Added a signed Mac disk image with a drag-to-Applications install window for
  direct downloads.

### Notes

- Sparkle updates continue to use the signed ZIP enclosure for compatibility;
  direct website downloads use the new DMG installer.

## 0.32.4.2 / iOS 1.11.1 — 2026-06-07

### New

- Published the first Columbus Labs Mac download for QuotaKit.
- Added a signed and notarized universal macOS build for Apple silicon and Intel Macs.
- Added the Mac setup page at `https://columbus-labs.com/quotakit/mac`.

### How it works

- Install QuotaKit on your Mac, move it to Applications, and turn on iCloud Sync.
- The iPhone app reads synced AI quota, usage, cost, history, widget, and alert
  summaries from iCloud after the Mac app is set up.
- Provider credentials and browser sessions stay local to the Mac. QuotaKit syncs
  sanitized usage summaries, not provider secrets.

### Notes

- Mac updates are distributed through GitHub Releases and Sparkle.
- This release pairs the Mac app with iOS 1.11.1.

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
