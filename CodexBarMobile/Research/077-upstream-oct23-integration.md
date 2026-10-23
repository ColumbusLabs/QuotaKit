# 077 — October 23 upstream integration

Completion and verification status: [authoritative issue #260 record](https://github.com/ColumbusLabs/QuotaKit/issues/260). This design is done only when that record confirms exact-head hosted qualification and merge; implementation alone is not completion.

Port trusted CodexBar range 8de11fff..7683b7367 with all 106 existing providers preserved and Soniox/Trae CN added. Use existing optional shared billing/budget fields for iPhone compatibility and keep subscription/notification eligibility tied to measured usage. Keep QuotaKit identity, CloudKit/App Group/StoreKit/recovery contracts, versions and build numbers. No distribution.

Cursor’s promoted weekly pool must keep its weekly identity across Mac sync labels, iPhone warning thresholds and widget lane selection. For phone warning settings, override the primary slot only for Cursor’s single seven-day shared pool; preserve all other providers’ Mac slot semantics, including Kimi’s seven-day primary and five-hour secondary. Widgets prefer optional typed identity, infer a seven-day cadence only when untyped, and retain legacy fallback for unknown windows without enabling additional warning lanes. Separate Cursor billing-cycle pace from semantic identity, and normalize older monthly Cursor Plan/Auto/API/Requests/Total payloads only when a known non-weekly cadence proves the typed weekly identity stale. Resets and the wire schema remain unchanged.

Separate plugin hook/session baselines preserve the fork’s existing Codex/Claude account state; current request/config/runtime guards, privacy, throttling and lifecycle cleanup remain mandatory. Account logging must be redacted and Copilot login uses injected synthetic tests. Claude cache schema/report semantics rebuild stale Cowork costs while preserving Codex cache compatibility.

Full per-commit decisions and verification design: [integration ledger](../../docs/upstream-sync-2026-10-23.md). Hosted CI and independent adversarial source review qualify the result; no routine local builds/tests or real-account probes.

Native Settings keeps content-width persistence across divider changes, collapse and new views. The hosted regression test selects the arranged pane containing sidebar content, because raw split-view subview order can differ; exact widths and the original settling deadline remain enforced.
