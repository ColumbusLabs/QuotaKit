# Feature Research

This directory contains research documents for features being considered for CodexBar Mobile (iOS).

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
