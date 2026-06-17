# QuotaKit iOS Research

This directory contains research documents for QuotaKit iOS features and sync work.

## Status Legend

| Status | Meaning |
|--------|---------|
| `draft` | Feature is under research / investigation |
| `blocked-upstream` | Research done, waiting for upstream PR to merge before we can proceed |
| `ready` | Research done, ready to implement |
| `in-progress` | Currently being implemented |
| `done` | Research completed and feature has been implemented |
| `dropped` | Decided not to pursue this feature |

## Index

| # | Feature | Status | Blocker | File | Date |
|---|---------|--------|---------|------|------|
| 001 | Daily Provider Utilization Chart | `blocked-upstream` | [upstream PR #565](https://github.com/steipete/CodexBar/pull/565) | [001-daily-utilization-chart.md](001-daily-utilization-chart.md) | 2026-03-19 |
| 002 | Cost Share Card (One-Tap Share) | `done` | — | [002-cost-share-card.md](002-cost-share-card.md) | 2026-03-19 |
| 008 | iOS Data Architecture Refactor (CloudKit split + view caching + local persistence) | `ready` | — | [008-ios-data-architecture-refactor.md](008-ios-data-architecture-refactor.md) | 2026-04-18 |
| 009 | iOS 1.3.0 Implementation Plan (SwiftData + per-provider CloudKit + change tokens) | `ready` | — | [009-1.3.0-implementation-plan.md](009-1.3.0-implementation-plan.md) | 2026-04-18 |
| 018 | Generic Model Fallback Pricing (Tier-A resolver design + 27-provider survey) | `ready` | — | [018-model-fallback-pricing.md](018-model-fallback-pricing.md) | 2026-04-27 |
| 019 | Account Identity Multi-Version Merge (set-based identity + iOS union-find + L3 user-confirmed linkage + 23-case edge audit) | `ready` | — | [019-account-identity-multi-version-merge.md](019-account-identity-multi-version-merge.md) | 2026-04-27 |
| 021 | Mock-First Quality Infrastructure (32-mock injection + iOS visual + CI gating + PR template) | `done` | — | [021-mock-first-infrastructure.md](021-mock-first-infrastructure.md) | 2026-05-03 |
| 022 | v0.27.0 Upstream Sync + iOS 1.8.0 (7 new providers + Claude Admin API + Kiro overage + MiniMax billing history) | `in-progress` | — | [022-v027-upstream-sync-ios-180.md](022-v027-upstream-sync-ios-180.md) | 2026-05-19 |
| 024 | Cost Window Ledger (B path: iOS local per-day ledger so iOS window selection is independent of Mac historyDays) | `ready` | — | [024-cost-window-ledger/README.md](024-cost-window-ledger/README.md) | 2026-05-28 |
| 025 | v0.31.0 Upstream Sync + iOS 1.10.0 (0.29.1 deferred + 0.30.0/0.30.1/0.31.0 → DeepSeek usage card + Codex Spark/Antigravity lanes auto-passthrough + value fixes; 4-doc set: overview/design/dev+arch/testing) | `ready` | — | [025-v031-upstream-sync/00-overview.md](025-v031-upstream-sync/00-overview.md) | 2026-05-30 |
| 027 | QuotaKit Pro Gates (cost/history/share/merge/visible notification gates + launch tracking notes) | `done` | — | [027-quotakit-pro-gates.md](027-quotakit-pro-gates.md) | 2026-06-07 |
| 028 | iOS Widgets + QuotaKit Branding Cleanup (Pro-gated widgets backed by sanitized iOS cache + user-facing brand cleanup) | `done` | — | [028-ios-widgets-branding.md](028-ios-widgets-branding.md) | 2026-06-07 |
| 029 | Widget Thermos Fixes (provisioning, Pro reload, localization, upgrade migrations, snapshot hardening) | `done` | Phase 0 provisioning | [029-widget-thermos-fixes.md](029-widget-thermos-fixes.md) | 2026-06-07 |
| 030 | Mac Setup Handoff (Columbus Labs setup page + iPhone share/copy flow) | `done` | — | [030-mac-setup-handoff.md](030-mac-setup-handoff.md) | 2026-06-07 |
| 031 | Mac Pace Parity (deficit/reserve pace labels + expected-usage stripe on iOS cards/widgets) | `done` | — | [031-mac-pace-parity.md](031-mac-pace-parity.md) | 2026-06-07 |
| 032 | Remote Config OTA Guardrails (public Columbus Labs config for setup URL overrides, feature kill switches, and announcements) | `done` | — | [032-remote-config-ota-guardrails.md](032-remote-config-ota-guardrails.md) | 2026-06-07 |
| 033 | iOS Refresh Feedback (tappable sync chip, persistent refresh state, live last-synced age) | `done` | — | [033-ios-refresh-feedback.md](033-ios-refresh-feedback.md) | 2026-06-08 |
| 034 | Review Findings Fix Bundle (provider color parity, adaptive tints, sync accessibility, branding audit hardening) | `done` | — | [034-review-findings-fix-bundle.md](034-review-findings-fix-bundle.md) | 2026-06-09 |
| 037 | Provider Order + Widget Provider Choice (inline Usage ordering + global app-selected widget provider) | `done` | — | [037-provider-order-widget-choice.md](037-provider-order-widget-choice.md) | 2026-06-17 |
