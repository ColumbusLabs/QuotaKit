# Changelog — CodexBar Mobile (iOS)

All notable changes to the CodexBar iOS companion app will be documented in this file.

## [1.3.0 (83)] — 2026-04-23 — dev build · 4-agent perfect-pass fixture extension

**Commit 3 of the post-Build-80 perfect-pass.** Agent C's analysis of `SwiftDataBridgeTests / DualZoneReaderTests / SnapshotCacheTests` found each had zero coverage of production-shaped data: long-idle gaps, cross-reset-boundary same-hour entries, all-zero-but-tracked patterns, bursty-active vs stale-idle multi-device combinations. Build 80 fixed this for `CloudKitMergeTests` only. This build extends the same treatment to the other 3 files and shares the fixture helpers.

### Tests (Agent C · realistic-distribution fixtures)

**New `CodexBarMobileTests/Fixtures/TestFixtures.swift`**: shared helpers so the 4 test files don't re-implement the same realistic patterns.
- `burstySessionSeries(anchor:daysCount:peakHour:peakPercent:deviceOffsetMinutes:)` — moved up from CloudKitMergeTests. UTC calendar deliberately (DST-proof — an earlier `Calendar.current` version would make 720 → 719 on Europe/Paris spring-forward).
- `allZeroSessionSeries(anchor:daysCount:)` — idle-device pattern; must survive every persistence layer.
- `crossResetBoundaryEntries(anchor:)` — two entries in same clock hour, different reset windows.
- `multiAccountProviders(id:emails:lastUpdated:)` — same provider with N distinct accountEmails.

**`SwiftDataBridgeTests` +3 cases**:
- `realisticAllZeroUtilizationRoundtrip`: 720 zero entries survive upsert → fetch. A "prune zero-only as uninteresting" regression would drop the count below 720.
- `realisticCrossResetBoundaryPreservedInStorage`: two entries in same clock hour, different `resetsAt` — both survive. A compositeKey collapse to `(series, capturedAt.hour)` would silently drop one.
- `realisticMultiAccountSameProviderPreserved`: alice + bob on codex → 2 rows, not 1. Regression to providerID-only keying would collapse them.

**`DualZoneReaderTests` +2 cases**:
- `reconstructLongIdlePlusFreshMixedTimestamps`: same device wrote 30-day-old Codex + 7-day-old Claude. Reconstruct preserves both, sorts newest-first, device syncTimestamp = freshest (not min).
- `priorityEmptyPerProviderKeepsLegacyIntact`: empty per-provider + populated legacy → legacy survives as-is. Guards the transient-zone-error fallback path.

**`SnapshotCacheTests` +2 cases**:
- `burstyActiveAndIdleStaleBothPresent`: Mac A fresh (t3) + Mac B stale (t1), same account. Both survive cache; a "drop stale" regression would show 1.
- `multiAccountDeltaOnlyUpdatesTargetAccount`: seed alice + bob at t1, delta alice to t2, bob untouched at t1. Guards against re-keying by providerID alone.

### Test totals
- Pre-Build-83: 81 tests
- Post-Build-83: 88 tests
- All pass; SwiftLint 0; Codex review: clean.

### Audit progress (post Build 83)
- Round 1 (cross-view): ✅ complete (Builds 77, 78, 81)
- Round 2 (multi-device fields): ✅ complete (Builds 77, 78, 81) — `providerName` / `deviceName` ⚠️ documented as rare-edge-case or cosmetic, not patched
- Round 3 (test data distribution): ✅ complete (Builds 80, 83)
- Round 4 (boundary conditions): ✅ documented as intentional / safe
- Round 5 (Codable resilience): ✅ complete (Build 79)

### Deferred to Build 84 (doc-only)
- `Research/015-mac-symmetry-audit.md` recording Agent A's 5 Mac-side findings (`accounts.first` non-deterministic · `Widget providers.first` · `SyncCoordinator "_"` placeholder · Perplexity multi-account no-email-split · OpenAIDashboard dayKey `TimeZone.current` formalization) for future upstream PR. No code change; just documents what we found for when upstream owners (steipete) review.

## [1.3.0 (82)] — 2026-04-23 — dev build · 4-agent perfect-pass P1 polish

**Commit 2 of the post-Build-80 perfect-pass.** Agent B flagged 5+ places where `formatUSD` / `formatTokens` were duplicated across views with subtly different signatures (some returned `"N/A"` for nil, some `"—"`, some crashed). Any future locale / precision / unit-label tweak would need coordinated edits — drift risk. Centralized.

### Fixed — Formatter duplication (Agent B · P1)
- **New `CodexBarMobile/Models/CostFormatting.swift`**: single source of truth `enum CostFormatting` with `usd(_ value: Double)`, `usd(_ value: Double?)`, `tokens(_ count: Int)`, `tokens(_ count: Int?)`. All four variants use `"—"` for nil uniformly.
- `ContentView` (Cost tab + RawDailyPointRow) — 3 call sites routed through `CostFormatting`.
- `ProviderDetailView` — `formatUSD` / `formatTokens` are now 1-line thin wrappers calling `CostFormatting`.
- `ProviderUsageView` — same thin-wrapper shape.
- `CostShareCardView` / `CyberShareCardView` — `formatUSD` unified. `formatTokens` kept local because share cards use a visually compact format (no "tokens" label suffix — the label is implied by card layout). Divergence documented in a source comment.
- Deliberately NOT touched: `RawProviderDetailView.formatCost/Tokens` (developer tool, uses `"N/A"` by design for debug legibility; not user-facing).

### Tests
- `CodexBarMobileTests/CostFormattingTests.swift`: 9 cases pinning the central contract — USD formatting structural properties (locale-independent), optional → "—" behavior, token K/M threshold transitions. Any regression that rewrites the central formatter without updating K/M boundaries or nil handling fails these.

### Not in this commit (Build 83–84)
- **Build 83**: SwiftDataBridgeTests / DualZoneReaderTests / SnapshotCacheTests realistic-distribution fixtures (Agent C's 9 proposed fixtures + shared `TestFixtures.swift`). 3 P1 + 6 P2.
- **Build 84**: `Research/015-mac-symmetry-audit.md` recording Agent A's 5 Mac-side findings for future upstream PR.
- Agent B's remaining ⚠️: Budget `usedAmount` semantics docs, Preview fixture drift, `deviceName` single-vs-merged marker — deferred; all cosmetic, no user-visible correctness risk.
- Agent A's Mac-side bugs (`accounts.first`, `providers.first`, `SyncCoordinator` `"_"` placeholder, Perplexity multi-account) — remain Mac-only; we don't patch `Sources/` per project rule.

## [1.3.0 (81)] — 2026-04-23 — dev build · 4-agent perfect-pass P0 fixes

**Context**: After Build 80 (3-commit systematic audit), I did an honest self-audit and found 14 gaps. User asked for "perfect". Dispatched 4 parallel research agents: Mac-side symmetry / cross-view all-pairs / test-fixture-distribution-3-files / performance-concurrency-a11y. The 4 agents found **4 new ❌ bugs** that the earlier audit missed. This build fixes all 4.

### Fixed — Cross-view consistency (Agent B)
- **`ProviderUsageView.costTeaserText` still read `sessionCostUSD` directly** — Build 78 fixed the `ProviderDetailView` "Today" card but missed this sibling call site. Usage-tab teaser and detail-page "Today" diverged mid-day. Now routes through `cost.todayTotals()` — same class-of-bug as Build 77's Codex-0% aggregate/detail mismatch, now closed across every known reader.
- **`UtilizationAggregateView.providerShareRow` ignored the "Show remaining usage" toggle**. Every other card on the Usage tab flips between "86% used" and "14% remaining"; the share row was hardcoded "% avg use". Added `@AppStorage(MobileSettingsKeys.showRemainingUsage)` matching `UsageCardView`'s declaration (legacy-key migration default included), plus a localized `%.0f%% avg remaining` format with zh-Hans / zh-Hant / ja translations.

### Fixed — Thread safety (Agent D, P0)
- **`SyncCostSummary.iso8601DayKeyFormatter` was a shared `static let DateFormatter`** — documented thread-unsafe on iOS. `todayTotals(now:)` is reachable from both view-body rendering (main actor) and sync-observer paths, so concurrent `string(from:)` calls could crash. Replaced with a per-call factory (`iso8601DayKeyFormatter()`) exposed via a thread-safe `iso8601DayKey(for:)` helper. Also explicitly set `.timeZone = .current` so the contract matches Mac-side `SyncCoordinator.daily[].dayKey` regardless of any future DateFormatter default shifts.
- Agent A's Mac-symmetry audit flagged Mac `OpenAIDashboardModels.swift:93` uses `TimeZone.current` + POSIX locale + "yyyy-MM-dd" — iOS's behavior (prior build) was equivalent since DateFormatter's default timeZone IS `.current`. Making it explicit on iOS pins the contract.

### Fixed — i18n (Agent D, ⚠️)
- **`UtilizationAggregateView` chart date labels were hardcoded `Locale(identifier: "en_US")` with `dateFormat = "M/d"`**. Japanese / Chinese users saw English month-day ordering regardless of interface locale. Switched to `setLocalizedDateFormatFromTemplate("Md")` + `.current` locale so the format follows the user's interface language naturally.

### Tests
- `SubscriptionUtilizationCompatTests` +1: `dayKeyConcurrentCallsSafe` — spawns 64 concurrent `Task`s each computing 30 day keys; asserts all match the single-threaded reference. Would have crashed with `EXC_BAD_ACCESS` pre-fix under the shared DateFormatter.
- Updated existing `todayTotals*` test to drop the removed `hasAnyValue` accessor (YAGNI — only one test was using it).

### Data-structure polish (part of broader Build 82 plan; one bit landed here)
- Removed `SyncCostSummary.TodayTotals.hasAnyValue` — only ever used by one test; callers who need it can inline `costUSD != nil || tokens != nil`. Reduces the API surface.

### Agent A / Mac symmetry — deferred to Build 84 as research doc
- Found 5 Mac-side bugs: accounts.first / providers.first non-deterministic ordering (Widget + Account Switcher) · Perplexity multi-account no accountEmail split · SyncCoordinator `"_"` placeholder for nil email creating ghost CKRecords · dayKey format OK (current policy). These are Mac-only; per project rules (`Sources/` / `Tests/` belong to upstream, read-only for us), they'll land in `Research/015-mac-symmetry-audit.md` for a future upstream PR, not a direct Mac-side patch.

## [1.3.0 (80)] — 2026-04-23 — dev build · 5-round systematic audit follow-up (commit 3/3)

**Commit 3 of 3** addressing the 5-round audit. Closes out Round 3 (测试数据分布 audit): every pre-Build-78 merge test ran on "toy" data (`usedPercent: 50.0`, `costUSD: $1.50`, three entries). Round 3 found every test file had **zero coverage** for long idle / cross-reset boundary / cross-date / deliberately disordered input / all-zero-but-tracked patterns. This commit adds realistic-distribution fixtures that re-exercise the existing merge paths with data shaped like real 30-day usage.

### Tests (Fix D · realistic-distribution regression fixtures)
- `CloudKitMergeTests.swift` +6 cases covering distributions the pre-audit suite never touched:
  - `mergedUtilizationBurstyDistributionPreservesPeaks` — two Macs each with 30 days of hourly Codex samples (peak once per day + 23 zeros, same pattern that surfaced the Build 77 Codex-0% bug). Asserts 720 buckets, monotonic hour order, 30 preserved peak entries at the expected value. Fixture uses a **UTC calendar** so DST transitions in the tester's local timezone (e.g. Europe/Paris spring-forward) can't make the test flaky by producing 719 buckets instead of 720.
  - `mergedUtilizationCrossResetBoundarySeparatesBuckets` — pre- and post-reset entries in the same clock hour, across **two Macs** to force the dedup path (single-Mac passthrough bypasses `dedupByHour`). Pins the `BucketKey(hourSlot, resetEpoch)` separation that prevents `90% ↔ 5%` from collapsing to `47.5%`.
  - `mergedUtilizationDisorderedInputProducesSortedOutput` — two Macs each with entries deliberately shuffled. Merged output is hour-sorted. Also documents that single-Mac passthrough (providers.count == 1) intentionally returns the original snapshot as-is without sorting — downstream consumers bucket into dicts so sortedness is only a multi-device merge property.
  - `mergedUtilizationLongIdleGapPreservesHistory` — Mac A has entries from 30 days ago, Mac B has fresh entries. Merger preserves both; no "stale filter" regression.
  - `mergedUtilizationAllZeroPatternPreserved` — 720 hourly samples all at 0%. Must survive merge: a "zero-pattern provider" must remain visible in Subscription Utilization, not be silently dropped.
  - `mergedCostCrossDateDayKeysPreserved` — daily cost points spanning a month end (2026-01-31 → 2026-02-01), overlap day sums correctly, dayKey strings round-trip untouched.
- Brought test count from 34 → 40 in `CloudKitMergeTests`; full suite 66 → 72.

### Findings from running the realistic tests
- **No regressions exposed** in current merge code — every assertion passed on the first try after one test-setup fix (single-device passthrough path doesn't dedup, which surfaced an over-specific assertion in one of the new tests that I documented and narrowed to the multi-device path where dedup actually runs).
- This confirms the merge layer handles realistic distributions correctly. The Build 77 Codex-0% bug lived at the view layer, not the merge layer — which is why CloudKitMergeTests fixtures didn't catch it. Round 1 (cross-view semantic consistency) was the right lens for that class.

### Audit wrap-up (post Build 80)
- Round 1 (cross-view semantic consistency): ✅ Build 77 (aggregate/detail) + Build 78 Fix A (Cost "Today")
- Round 2 (multi-device merge fields): ✅ Build 77 (appVersion/mobileVersion) + Build 78 Fix B (notificationPushEnabled). One agent-flagged finding verified as false positive (`providerName` — current `base.providerName` is equivalent to `latestNonNil` because providerName is non-optional).
- Round 3 (test data distribution): ✅ Build 80 Fix D
- Round 4 (boundary conditions): Several `⚠️` findings verified and documented as intentional product behavior (email nil vs "" deliberate split, SwiftData stale-record retention for offline Macs, .distantPast sentinel safe behind override branch). No `❌`.
- Round 5 (Codable resilience): ✅ Build 79 Fix C + Fix E

## [1.3.0 (79)] — 2026-04-23 — dev build · 5-round systematic audit follow-up (commit 2/3)

**Commit 2 of 3** addressing the 5-round audit's infrastructure findings (the other P1 code-level fixes landed in Build 78 as Commit 1). This commit fixes Round 5 (Codable resilience) and part of Round 3 (encoder/decoder consistency in tests).

### Fixed (Codable cross-version forward resilience — Fix C)
- **Added regression guard that iOS 1.3.0 tolerates unknown fields sent by future Mac versions.** Scenario: a hypothetical Mac 0.21 adds a new field to `ProviderUsageSnapshot` / `SyncedUsageSnapshot` / `SyncCostSummary` / `SyncPerplexityCreditSummary`. iOS 1.3.0's decoder must silently drop the unknown key and preserve known fields; any throw would cascade up through `CloudSyncManager.decodeEnvelope` → return nil, and that Mac's data would vanish from the iPhone view until the user upgraded iOS. The current synthesized-decoder behavior already tolerates unknown keys (Swift keyed containers never query a key you didn't declare), but there was no test pinning it. A future refactor to a custom strict decoder (e.g. for debug-mode schema validation) could silently break iOS-reading-newer-Mac paths — these tests prevent that.
- Synthesizes the scenario by encoding a real snapshot, JSON-serializing to `[String: Any]`, injecting unknown keys, re-serializing, and asserting the decoder round-trips successfully.

### Fixed (Test infrastructure — Fix E · encoder/decoder factory unification)
- **Replaced 15 `JSONEncoder() / JSONDecoder() + .iso8601` call sites in `SyncModelTests.swift` with `CloudSyncConstants.makeJSONEncoder/Decoder()`.** This aligns the iOS test suite with the Mac `JSONCodecConsistencyTests` convention that has existed since Build 68's hardening pass. Tests now exercise the exact same factory contract production code does — Build 66's silent-decode-failure class of bug (iso8601 vs deferredToDate strategy mismatch) can't re-enter the test layer.

### Tests
- `SyncModelTests.swift` +4 cases:
  - `providerSnapshotTolerantOfFutureFields`
  - `syncedUsageSnapshotTolerantOfFutureFields`
  - `syncCostSummaryTolerantOfFutureFields`
  - `syncPerplexityCreditsTolerantOfFutureFields`
- `SyncModelTests.swift` 15 call sites refactored to go through `CloudSyncConstants` factory (no semantic change; contract alignment only).

### Not in this commit (tracked for Commit 3)
- Realistic-distribution fixtures (bursty / long idle / cross-reset / cross-date / disordered timestamps) across `CloudKitMergeTests / DualZoneReaderTests / SnapshotCacheTests / SwiftDataBridgeTests` — Round 3's primary finding.

## [1.3.0 (78)] — 2026-04-23 — dev build · 5-round systematic audit follow-up (commit 1/3)

**Context**: Build 77 fixed two reported bugs (Subscription Utilization Codex 0%, Mac App version flipping) but the user rightly pointed out that fix is "只是止血" — the same *class* of bug (cross-view semantic mismatch; non-deterministic multi-device field merge) almost certainly repeats elsewhere. I ran a 5-round systematic audit (cross-view semantic consistency · multi-device merge fields · test data distribution · boundary conditions · cross-version Codable compatibility), 3 parallel Explore agents per round, verified agent findings against source. This is commit 1 of 3 addressing the audit's P1 findings.

### Fixed (Cross-view semantic mismatch — same class as Build 77's Codex 0%)
- **"Today" cost number no longer diverges between Cost tab and provider detail page**. The Cost-tab summary card (via `CostDashboardInsights`) already used `daily.first(where: dayKey == todayKey).costUSD` and fell back to `sessionCostUSD` only when no daily point existed for today — the right preference. `ProviderDetailView.costSummarySection`, however, used `cost.sessionCostUSD` directly. Mid-day the two numbers diverged (session cost is the current session's running total; daily-point cost is the committed day-aggregate). Added `SyncCostSummary.todayTotals(now:)` returning a `TodayTotals` pair as a single source of truth; both call sites now route through it.
  - New file: `CodexBarMobile/Models/SyncCostSummary+Today.swift`
  - Updated: `CodexBarMobile/Views/ProviderDetailView.swift` (line ~96)
  - Codex-reviewer caught a midnight-drift P3 in the first patch (separate `todayCostUSD` / `todayTokens` accessors each called `Date()`, so cost and tokens could resolve from different dayKeys across local midnight). Rewrote as a single `todayTotals(now: Date = Date())` call returning both fields atomically, with injectable `now` so tests stay deterministic.

### Fixed (Multi-device merge non-determinism — same class as Build 77's appVersion)
- **`SyncedUsageSnapshot.notificationPushEnabled` merge is now deterministic regardless of CloudKit iteration order.** Pre-fix: `snapshots.contains(where: { $0 == false }) ? false : snapshots.first?.value`. When all Macs had `true`, returned `snapshots.first?.value` — `true`, correct by accident. But when some Macs had `true` and others had `nil` (e.g., one Mac is the reporter of the user's preference, the others predate the field), the result flipped between `true` and `nil` based on whichever snapshot CloudKit returned first. Fixed semantics: any explicit `false` → `false` (conservative: respect any off-signal); else any explicit `true` → `true`; else `nil`.
  - Updated: `CodexBarMobile/iCloud/CloudSyncReader.swift` `mergeSnapshots`

### Tests
- `CloudKitMergeTests.swift` +8 cases:
  - `pushEnabledAllTrue / AnyFalseWins / TrueWinsOverNil / FalseWinsOverNil / AllNil` — pin the new `notificationPushEnabled` semantics; `TrueWinsOverNil` and `FalseWinsOverNil` run the same snapshots twice with flipped iteration order to prove order-independence.
  - `todayTotalsPrefersDailyToday / FallsBackToSession / NilWhenNoData / DayKeyCoherence` — pin the new `SyncCostSummary.todayTotals(now:)` preference order, nil-when-empty behavior, and single-dayKey resolution across both fields. Fixtures pin `now` to a fixed Date so the suite is immune to midnight crossings.

### Not included in this commit (tracked for follow-up commits)
- Future-field resilience test (decoder meets unknown keys) — Commit 2
- Test-suite encoder/decoder factory unification (27 call sites still construct `JSONEncoder()` manually) — Commit 2
- Realistic-distribution fixtures across `CloudKitMergeTests / DualZoneReaderTests / SyncModelTests / SwiftDataBridgeTests` (bursty / long idle / cross-reset / cross-date / disordered timestamps) — Commit 3

## [1.3.0 (77)] — 2026-04-22 — dev build · Subscription Utilization aggregate + Mac version determinism

**Reported bug**: Cost tab's "Subscription Utilization" card shows Codex at 0% ("0% avg use") while the Codex detail page shows 16% session usage with 84 visible data points and clear bars on recent days. Also reported: with two Macs on different CodexBar versions, the "Mac App" field in Settings flips between versions across refreshes instead of stabilizing on the newer one.

**Root causes** (two independent issues surfaced together by the multi-device setup):

1. **Semantic mismatch — aggregate vs detail.** `UtilizationAggregateView.buildModel` averaged **raw** utilization entries across the window. For session quotas, a typical hour of samples looks like `[0, 0, 0, 20, 10, 5, 0, 0]` — the burst is real but the raw average is near-zero. Detail view (`UtilizationHistoryView.buildPeriodPoints`) groups by reset-period and takes `max`, surfacing the burst. Consequence: bursty-use providers (Codex) read as 0% in the aggregate while the detail chart clearly shows usage.
2. **Non-deterministic Mac App version.** `mergeSnapshots` used `snapshots.first?.appVersion`, which is whichever snapshot CloudKit iterates first — flips per refresh. Two Macs on 0.19.0 + 0.20.3 would display either version depending on fetch order.

### Fixed
- `CodexBarMobile/Views/UtilizationAggregateView.swift`:
  - `buildModel(from:windowSize:)` now collapses each provider's session entries to **daily peaks** (`max(usedPercent)` per calendar day) before aggregating. Summary cards, daily bar heights, and provider-share math all consume the same per-day peak signal.
  - Hardens against cross-version merge leakage where two "session" series end up in the merged history: aggregate now **unions entries across every session-named series** rather than picking `history.first(where: name == "session")` (which could latch onto the empty/stale one).
- `CodexBarMobile/iCloud/CloudSyncReader.swift` `mergeSnapshots`:
  - `appVersion` / `mobileVersion` now take the **highest semver** across devices (new `semverLessThan` helper) instead of `snapshots.first?.appVersion`. Result is stable across refreshes and reflects the most up-to-date client in any multi-Mac setup.
- `CodexBarMobile/iCloud/CloudSyncReader.swift` `mergeUtilizationHistories`:
  - Group by series **name** only (was `(name, windowMinutes)`). Cross-version Macs occasionally disagree on `windowMinutes` for what is logically the same account-level series (e.g. a fallback classification on an older build). Pre-fix this split into two entries named `"session"` and left the picker to guess; post-fix the entries union and the freshest device's `windowMinutes` wins.

### Tests
- `CodexBarMobileTests/SubscriptionUtilizationCompatTests.swift` +3 cases:
  - `aggregateBurstyProviderShowsPeakNotZero`: single provider with 1 peak/day + 23 zero samples — pre-fix would show 0%, post-fix shows 16%.
  - `aggregateTwoBurstyProvidersShowCorrectShare`: two providers reflect proportional share (Claude + Codex scenario from the report).
  - `aggregateUnionsMultipleSessionSeries`: empty-first + real-second session series → aggregate picks real data, not the empty stub.
- `CodexBarMobileTests/CloudKitMergeTests.swift` +5 cases:
  - `appVersionTakesHighest`, `appVersionOrderIndependent`, `semverComparison` — Mac App version determinism.
  - `utilizationMismatchedWindowMinutesUnion`, `utilizationEmptySeriesFromOneDeviceDoesNotMaskOther` — mergeUtilizationHistories regression guards.
- Also repaired two pre-existing tests in `CloudKitMergeTests.swift` whose `SyncCostSummary(…)` argument order was wrong and had silently never compiled.

## [1.3.0 (76)] — 2026-04-22 — dev build · cross-version multi-device merge hardening

**Class-of-bug fix**: every optional account-level field on `ProviderUsageSnapshot` that the merger was taking from `base` (the newest-timestamped device) silently dropped data when two Macs running different CodexBar versions synced to the same iCloud account — and the **older** Mac (without the new field) happened to refresh last. This isn't a transition scenario; it's the steady state for any user whose 2 Macs update on different schedules (could be weeks or months apart). Build 74 fixed the `perplexityCredits` instance after Codex-review flagged it; Build 76 generalizes the fix to every account-level field in the same position.

### Fixed
- `CodexBarMobile/iCloud/CloudSyncReader.swift` `mergeProviderEntries`:
  - New `latestNonNil<T>(_:_keyPath:)` helper — walks entries newest-first and returns the first non-nil value of the given keyPath. Returns nil only when every device has nil for the field.
  - `perplexityCredits`: take-latest → **latestNonNil**
  - `budget`: take-latest → **latestNonNil** (same bug: account-level API data; one Mac may not have fetched)
  - `costSummary` for non-local-cost providers (Cursor, Perplexity, OpenCode Go, etc.): take-latest → **latestNonNil** (account-level; summing only applies to local-file-backed providers: claude / codex / vertexai)
  - `loginMethod`: take-latest → **latestNonNil** (plan strings — same class)
- Inline docstring on `mergeProviderEntries` now enumerates field-by-field semantics (identity / status / rate / cost / utilization / account-level) so the class of bug is visible at the call site.

### Preserved
- `statusMessage`, `isError`, `rateWindows`, `primary`, `secondary`, `lastUpdated` stay take-latest — for these "most recent state of this device" is the right semantic (e.g. show the latest error if any Mac is erroring right now).
- `costSummary` SUM semantics for local-cost providers (claude / codex / vertexai) unchanged — per-Mac CLI files legitimately contain different data.
- `utilizationHistory` merge-and-dedup semantics unchanged.

### Tests
- `CodexBarMobileTests/CloudKitMergeTests.swift` +4 cases for the cross-version inversion scenario:
  - `perplexityCreditsInvertedFreshnessKeepsData`: older Mac has credits + newer has nil → merged keeps credits
  - `budgetInvertedFreshnessKeepsData`: same pattern on `budget`
  - `nonLocalCostInvertedFreshnessKeepsData`: same pattern on Cursor `costSummary` (non-local-cost)
  - `loginMethodInvertedFreshnessKeepsData`: same pattern on Codex plan label
- Plus `localCostStillSumsAfterRefactor`: guard against accidentally regressing the claude / codex / vertexai SUM semantic when adding the latestNonNil branch for non-local.

## [1.3.0 (75)] — 2026-04-22 — dev build · fix iOS archive: private-type leak in PerplexityCreditsCard

Build 74 archived on Mac CI (`swift test` on Package.swift Mac target) without issue, but `xcodebuild archive` against `CodexBarMobile.xcodeproj` for `iphoneos` failed with two compiler errors — `PerplexityCreditsCard.poolLabel(_:)` and `legendDotOpacity(for:)` were declared `static` (implicit internal) with a `PoolSegment.Kind` parameter whose enclosing struct is `private`. Swift archive compilation rejects the mixed-access signature even when the same code compiles fine under `swift build` on Mac because the Mac package target never touches this iOS-only view.

### Fixed
- `CodexBarMobile/Views/PerplexityCreditsCard.swift`: `poolLabel` / `legendDotOpacity` / `formatCreditsUsed` now explicitly `private static`. These helpers are implementation details of the card view; no external caller (or test) referenced them.

### Process improvement note
- CI today only covers `swift test` against the SPM Package target, which is Mac-scoped. iOS-archive-specific errors (private-type leaks, provisioning profile issues, iOS-only API usage) are only caught by `xcodebuild archive` against `CodexBarMobile.xcodeproj`. Worth adding to the CI workflow before next release.

## [1.3.0 (74)] — 2026-04-22 — dev build · Codex review fix: preserve perplexityCredits through multi-device merge

Codex CLI review (gpt-5.3-codex) on `feature/1.3.0-provider-alignment` vs `mobile-dev` surfaced one P2 regression risk: `ProviderUsageSnapshot.perplexityCredits` was added with a default-nil initializer parameter in Build 71 so that existing constructors would keep compiling. But `CloudSyncReader.mergeProviderEntries` (line 202) never passed the field through — so a user with ≥2 Macs on their iCloud account would see the merged Perplexity snapshot arrive with `perplexityCredits == nil`, making the iOS detail view regress to the legacy 3-bar fallback even when Mac 0.20.3 was sending structured data.

### Fixed
- `CodexBarMobile/iCloud/CloudSyncReader.swift` `mergeProviderEntries`: explicitly forward `base.perplexityCredits` into the rebuilt `ProviderUsageSnapshot`. "Take latest device's credits" matches the identity / loginMethod / statusMessage selection rules (all account-level fields; no cross-device sum semantics apply).

### Tests
- `CodexBarMobileTests/CloudKitMergeTests.swift` +2 cases:
  - `perplexityCreditsPreservedInMultiDeviceMerge`: Mac A (older, nil credits) + Mac B (newer, populated credits) → merged snapshot must carry Mac B's credits, not drop them.
  - `perplexityCreditsPreservedSingleDevice`: trivial single-device passthrough still carries credits (guards against a future "shortcut single-device merge" optimization dropping the field).

### Note
- This is the kind of silent-regression bug that slips through when a required field is added behind a default-nil parameter. CI / type-checker can't catch it; only end-to-end merge-path tests. Worth revisiting every call site the next time we extend `ProviderUsageSnapshot`.

## [1.3.0 (73)] — 2026-04-22 — dev build · T6 Subscription Utilization compatibility with Perplexity / OpenCode Go

Perplexity and OpenCode Go don't emit `utilizationHistory` (Perplexity surfaces three credit pools instead; OpenCode Go reports flat rate windows). The Cost-tab aggregate chart iterates `provider.utilizationHistory` and was already `compactMap`-gated on non-nil, but there were zero tests proving the guard actually trips for these two providers. T6 pins the behavior so a future refactor can't reintroduce a force-unwrap that crashes the Cost tab on launch for users with Perplexity enabled.

### Tests
- New `CodexBarMobile/CodexBarMobileTests/SubscriptionUtilizationCompatTests.swift` (5 cases):
  - Identity key stays stable across repeated calls with Perplexity + no-history in the mix
  - Identity key diverges when Perplexity is swapped for OpenCode Go (no accidental collision)
  - `n=<entries>` suffix correctly excludes zero-history providers from the total count
  - All-no-history provider list still produces a well-formed, non-empty key (no crash path)
  - Palette tints for Perplexity / OpenCode Go resolve to distinct, non-gray, non-equal colors (post-T2 consolidation)

### Notes
- No production-code change — `buildModel`'s `compactMap` + `guard let history = ..., !session.entries.isEmpty else` was already correct. This build locks the contract in unit tests so the invariant is CI-visible.
- iOS project bump 72 → 73 per discipline rule (every install bumps).

## [1.3.0 (72)] — 2026-04-22 — dev build · T5 Codex multi-account card UI + ForEach identity fix

Build 23 merged per-device Codex snapshots by `providerID|accountEmail` in `CloudSyncReader.mergeSnapshots`, so two Codex accounts (e.g., one on Mac-A, one on Mac-B) correctly produced two `ProviderUsageSnapshot` entries in the merged output. The cards never reached the user because `ContentView.swift:174` identified rows by `\.providerID` — SwiftUI collapsed the two entries into one view instance, and `accessibilityIdentifier("provider-card-codex")` double-registered on the same element. T5 fixes the identity bug and adds a nil-email ordinal fallback so every disambiguating render path has a unique, human-readable subtitle.

### Fixed
- **SwiftUI ForEach identity collision.** `ContentView.swift` list now identifies each card by a composite `cardIdentityKey` (`"providerID|accountEmail"`) that matches `mergeSnapshots`'s bucket. Two Codex accounts now render as two distinct cards that animate independently, respect their own navigation destinations, and each own a unique `accessibilityIdentifier`.
- Accessibility identifiers updated to `provider-card-codex|alice@example.com` style — a UI test or accessibility inspector can now resolve the exact card without ambiguity.

### Added
- `CodexBarMobile/Models/ProviderUsageSnapshot+Identity.swift`: iOS-only extension exposing `cardIdentityKey` (`"\(providerID)|\(accountEmail ?? "")"`). Kept iOS-scoped because the Mac target doesn't render cards; Shared stays untouched so no Mac re-release is needed for T5.
- `ProviderUsageView.duplicateOrdinal: Int?`: 1-based ordinal among same-`providerID` siblings. `nil` keeps the pre-T5 single-card subtitle behavior so non-Codex providers render identically.
- Subtitle selection rule: `email (non-empty) > localized "Codex N" ordinal > nil`. Empty-string email treated as nil for defensive parity with the merger's fallback.
- `Localizable.xcstrings`: new key `"provider-account-ordinal"` (`%@ %lld` format) across en / zh-Hans / zh-Hant / ja. Plus T3's Perplexity strings (`"Credits"`, `"Monthly credits"`, `"Bonus credits"`, `"Purchased credits"`, `"exp."`) batched in the same update.

### Tests
- New `CodexBarMobile/CodexBarMobileTests/ProviderUsageViewSubtitleTests.swift` (8 cases):
  - `cardIdentityKey` shape for present / nil email
  - Two distinct accounts produce distinct `cardIdentityKey`s
  - Subtitle rule × 4 branches (single+email / single+nil / multi+email / multi+nil)
  - Empty-string email treated as nil in the multi-card ordinal fallback

### Deferred (tracked as Branch B follow-up)
- Workspace-name as a subtitle source. Mac's `ManagedCodexAccount` / `ObservedSystemCodexAccount` carry `workspaceLabel` but `SyncCoordinator` strips it before push. Adding `workspaceName` to `ProviderUsageSnapshot` would be a Shared-contract change + Mac SyncCoordinator update — coordinated with a Mac release window. For now, ordinal fallback is sufficient to disambiguate nil-email multi-card scenarios.
- Research doc: `CodexBarMobile/Research/014-codex-multi-account-ios.md`.

## [1.3.0 (71)] — 2026-04-22 — dev build · T3 Perplexity 3-segment credit detail page

Upstream `PerplexityUsageSnapshot` (`Sources/CodexBarCore/Providers/Perplexity/`) exposes three distinct credit pools — monthly recurring, promotional/bonus, on-demand purchased — plus Pro/Max plan inference and a renewal date. Mac's `toUsageSnapshot()` collapses all of that into three generic `UsageSnapshot` rate windows for the legacy pipeline, so iOS sees three flat bars in fallback blue and no pool breakdown. T3 extends the shared sync contract with a structured `SyncPerplexityCreditSummary` field and adds a native stacked-bar detail view.

### Added
- `Shared/Models/UsageSnapshot.swift`: new `SyncPerplexityCreditSummary` Codable struct (`recurringTotalCents` / `recurringUsedCents` / `promoTotalCents` / `promoUsedCents` / `promoExpiresAt` / `purchasedTotalCents` / `purchasedUsedCents` / `renewalAt` / `planName` / `balanceCents`, all Optional). Amounts in cents to match upstream's raw units; iOS formats for display.
- `ProviderUsageSnapshot` gains `perplexityCredits: SyncPerplexityCreditSummary?`. All writers default to nil; the custom `init(from:)` uses `decodeIfPresent` so Mac 0.20.2 payloads (no key) continue to decode cleanly with `perplexityCredits == nil`.
- New `CodexBarMobile/Views/PerplexityCreditsCard.swift`: stacked 3-segment horizontal bar (pool widths proportional to each pool's `*TotalCents`), Pro/Max badge, renewal-date countdown, and a per-pool legend. Rendered only when both `providerID == "perplexity"` and `perplexityCredits != nil`; otherwise falls through to the existing generic rate-window list.
- `ProviderDetailView.primaryUsageSection` — the switch point that chooses the card vs the legacy list.
- `ProviderSnapshotModel.perplexityCreditsData: Data?` SwiftData column + `SwiftDataBridge` encode-on-write / decode-on-read passthrough. Keeps the credit breakdown alive across cold starts (matches existing `costSummaryData` / `budgetData` pattern).

### Tests
- `Tests/CodexBarTests/JSONCodecConsistencyTests.swift` +5 cases:
  - Fully-populated `SyncPerplexityCreditSummary` round-trip (both Date fields)
  - All-nil `SyncPerplexityCreditSummary` round-trip (free-tier edge case)
  - `ProviderUsageSnapshot` with populated `perplexityCredits` round-trip
  - Backward-compat: hand-rolled legacy JSON (no `perplexityCredits` key) decodes with `perplexityCredits == nil`
  - `ProviderUsageEnvelope` zlib compression round-trip with `perplexityCredits` populated — covers the full Mac → CloudKit CKRecord → iOS pipeline

### Notes
- **Mac-side mapping (`SyncCoordinator.swift`) is required for the user-facing feature to light up.** Mac currently discards `PerplexityUsageSnapshot` in `toUsageSnapshot()` before `SyncCoordinator` sees it. A follow-up Mac 0.20.3 Sparkle release needs to add `perplexityUsage: PerplexityUsageSnapshot?` on Mac-local `UsageSnapshot` (mirroring the `zaiUsage` / `minimaxUsage` escape-hatch pattern) and map it into the shared struct. Until then iOS 1.3.0 Perplexity detail page silently falls back to the legacy 3-bar rendering.
- Research doc: `CodexBarMobile/Research/013-perplexity-detail.md`.

## [1.3.0 (70)] — 2026-04-22 — dev build · T2 consolidate provider color palette

Provider tint color derivation was duplicated (with subtle drift) across 5 files: `ProviderUsageView.providerColor`, `ProviderDetailView.providerColor`, `UtilizationAggregateView.providerColor(for:)`, `ContentView.providerTint(for:)`, and `CostShareService.providerColor(for:)`. The aggregate view in particular used an exact-match switch with a `.gray` default — every provider not in its explicit 5-case list rendered gray in the utilization charts regardless of what the cards showed. Perplexity + OpenCode Go added in Build 69 would have collapsed into the generic blue fallback in every single site.

### Added
- New `CodexBarMobile/Models/ProviderColorPalette.swift` — single source of truth. `ProviderColorPalette.color(for providerIdentifier:)` accepts either `providerID` (`"opencodego"`) or display name (`"OpenCode Go"`) via a lowercased + space-stripped normalization, so callers in both forms get the same color.
- Perplexity → brand teal `(0.13, 0.50, 0.55)` ≈ #21808D.
- OpenCode Go → `.mint` so it stays visually separable from OpenCode Zen's blue when both cards are on screen.
- Specificity ordering: the `opencodego` match is evaluated **before** the broader `opencode` match. Without the ordering `"opencodego".contains("opencode")` would collapse Go back into Zen's blue — pinned by test `opencodeGoDoesNotCollideWithOpencode`.

### Changed
- `ProviderUsageView.providerColor` / `ProviderDetailView.providerColor` / `ContentView.providerTint(for:)` / `CostShareService.providerColor(for:)` / `UtilizationAggregateView.providerColor(for:)` — all now delegate to `ProviderColorPalette.color(for:)`. Removed 5 copies of the same (drifted) logic.
- `CostShareService` call site switched from `row.provider.providerName` to `row.provider.providerID` — ID is the stable canonical form.
- Aggregate view's legacy `.gray` default for unknown providers replaced by the palette's blue fallback. Net visual change in the utilization chart: providers that were previously gray (e.g. OpenCode, Amp, Kimi, …) now render with their proper color.

### Tests
- New `CodexBarMobile/CodexBarMobileTests/ProviderColorPaletteTests.swift` (10 cases) — brand-color pinning, specificity ordering, ID-vs-displayName equivalence, empty / unknown fallback. Extends `UIColor` with a `isApproximately(_:tolerance:)` helper so two SwiftUI `Color`s round-tripped through `UIColor` don't fail on float drift.

### Notes
- Total deleted lines (5 call sites minus new palette + new tests): net +~50 LOC but now there's exactly one matrix to update when the next upstream provider lands.

## [1.3.0 (69)] — 2026-04-22 — dev build · T1 QuotaProviderList append Perplexity + OpenCode Go

Upstream CodexBar 0.20 introduced two new providers on the Mac side — Perplexity and OpenCode Go. `QuotaProviderList` is the single source of truth for the `(provider, state)` matrix that Mac writes `QuotaTransition` records to and iOS creates `CKRecordZoneSubscription`s for. Without updating both sides, iOS never subscribes to Perplexity / OpenCode Go quota zones — so those providers' quota-depleted / -restored pushes never reach the phone.

### Added
- `Shared/Notifications/QuotaProviderList.swift`: append `Provider(id: "perplexity", displayName: "Perplexity")` and `Provider(id: "opencodego", displayName: "OpenCode Go")`. Display names verified to match `ProviderDescriptor.metadata.displayName` in `Sources/CodexBarCore/Providers/Perplexity/PerplexityProviderDescriptor.swift` and `.../OpenCodeGo/OpenCodeGoProviderDescriptor.swift` so the iOS alert body reads "Perplexity session quota depleted" / "OpenCode Go 的会话额度已耗尽" on the corresponding locale without any extra mapping.
- Provider count 23 → 25. Subscription count 46 → 50 (25 providers × 2 states).

### Tests
- New `Tests/CodexBarTests/QuotaProviderListTests.swift`: pins the provider count, requires Perplexity + OpenCode Go entries with the correct `displayName`, asserts OpenCode Zen + Go stay distinct, forbids duplicate / blank IDs, and verifies `quotaZoneName(providerID:state:)` composes to the exact strings Mac + iOS both depend on. Also spot-checks the derived subscription count stays at 50 so the factor-of-2 state assumption is visible to reviewers.

### Notes
- iOS 1.2.0 users don't get these two new zones (their `QuotaProviderList` is still 23). They'll miss Perplexity / OpenCode Go pushes until they install 1.3.0, but existing 23 provider pushes keep working without interruption.

## [1.3.0 (68)] — 2026-04-21 — dev build · hardening pass (Research/012)

After Codex CLI's 2 P-level findings landed in Build 67, an additional hardening review (Phase 1 Explore agent) surfaced one P1 + several P2/P3. Build 68 fixes them and adds defensive scenario tests so a future regression on the same shape can't slip through silently.

### Fixed
- **P1 · `compositeKey` format drift** (`SwiftDataSchema.makeCompositeKey`). Was emitting `{deviceID}|{providerID}|` (empty for nil email), while `CloudSyncManager.perProviderRecordName` and `SnapshotCache.compositeKey` were emitting `{deviceID}|{providerID}|_`. Today nothing in the live code actually compares CloudKit recordName against SwiftData compositeKey, so the drift wasn't a runtime bug — but ANY future code that does (e.g. delete-by-recordName from CloudKit applied to SwiftData) would silently miss matching rows. Aligned all three sites on `_` for nil. Pinned by new test `compositeKeyNilEmailFormat`.
- **P2 · Concurrent silent-push storm could land an older delta on top of newer cache state**. `SyncedUsageData.fetchFromCloudKit` and `refreshIncremental` now both go through a `coalesceRefresh` funnel — if a refresh task is in flight, additional callers await it instead of starting a parallel fetch. Trades a tiny bit of throughput for race-free state mutation under push storms.
- **P2 · Encoder/decoder strategy drift risk**. New `CloudSyncConstants.makeJSONEncoder()` / `makeJSONDecoder()` factories return JSON codecs with `.iso8601` date strategy on both sides. All production callers (`CloudSyncManager`, `SwiftDataBridge`, `SyncCoordinator.providerDiffEncoder`, the static `decodeEnvelopeStatic`) now use the factories — never construct raw `JSONEncoder()` / `JSONDecoder()`. Build 65/66 root cause cannot recur silently.

### Added (scenario tests, designed around USER-FACING POSSIBILITIES not code paths)
- `JSONCodecConsistencyTests` (Mac, 9 cases) — pins the encoder/decoder factory contract: every `Sync*` type that carries a `Date` is round-tripped explicitly. Two tests assert that mixing the factory codec with the default `JSONEncoder/Decoder` FAILS, which means a future "let me just use `JSONEncoder()`" change will break a test instead of a user.
- `SnapshotCacheTests` +4 cases — multi-account same provider, nil-email + emailed coexistence, compositeKey format pin, delta with email doesn't disturb a nil-email entry.

### Reviewed but no change needed
- Hardcoded `CKModifyRecordsOperation` batch size 200 — within CloudKit's documented limit, deferred.
- `nonisolated(unsafe)` accumulators in `fetchPerProviderZoneChanges` — verified safe (single-threaded accumulation inside `withCheckedThrowingContinuation`).
- AppDelegate `iCloudAccountChanged` observer cleanup — singleton, app-lifetime, no leak.
- `SyncedUsageData` deinit cleanup of NotificationCenter token — `@State`-backed app-lifetime instance + `[weak self]` makes the leak benign; explicit cleanup deferred (would need `@MainActor deinit` workaround).

### Hardening plan
- Full plan + findings log: `CodexBarMobile/Research/012-refactor-1.3.0-hardening-plan.md`.

## [1.3.0 (67)] — 2026-04-21 — dev build · Codex review fixes (2 correctness issues)

Codex CLI review of `refactor-1.3.0` vs `mobile-dev` surfaced two P-level defects — both now fixed.

### Fixed
- **P1 · Transient CloudKit failures no longer blank out cached data** (`SyncedUsageData.fetchFromCloudKit`). Previously `replaceFromFullFetch` was called unconditionally even when both zone queries returned `.error`, wiping the in-memory cache and showing the user a blank screen whenever they launched offline or CloudKit was momentarily unreachable. Now each zone's result is classified: `.success` / `.empty` replace that bucket, `.error` preserves it. If BOTH zones error, the cache is left entirely untouched and only the sync status flips to `.error`. `SnapshotCache.replaceFromFullFetch` now takes optional args where `nil` means "leave this bucket alone."
- **P2 · Partial-encode failures no longer silently skip retries** (`CloudSyncManager.pushPerProviderRecords`). The method used to return `.success(message: "Encoded X / failed Y")` when some envelopes failed to encode; the Mac `SyncCoordinator` then updated `lastProviderHashes` for all submitted providers, including the ones that never reached CloudKit, so they stayed stale until their content changed again. Now partial-encode failures return `.failure` — the coordinator keeps the pre-push hash cache and retries everyone next cycle. Slightly wasteful (re-uploads the ones that did land this cycle) but correct.

### Tests
- `SnapshotCacheTests` +2 cases: `nilPerProviderArgPreserves`, `nilLegacyArgPreserves`.

## [1.3.0 (66)] — 2026-04-20 — dev build · fix Usage cold-start blank (two root causes)

User reported Usage tab shows blank on cold start while Cost shows data instantly. After two rounds of wrong diagnosis (TabView lazy, then `.thickMaterial` GPU cost), Build 64/65 diagnostic prints exposed the actual root causes.

### Fixed
- **Date encoding strategy mismatch in `SwiftDataBridge`.** `upsertProvider` used the default `JSONEncoder` which serialises `Date` as a `TimeInterval` double, while `readAllDeviceSnapshots` configured its decoder with `dateDecodingStrategy = .iso8601` and expected an ISO8601 string. Every `SyncRateWindow` / `SyncBudgetSnapshot.resetsAt` silently failed to decode, `try?` swallowed the throw, and `rateWindows` came back as `[]`. Cost tab was unaffected only because `SyncCostSummary` has no `Date` fields and the user's Claude budget happened to have `resetsAt == nil`. Fix: set `encoder.dateEncodingStrategy = .iso8601` in `SwiftDataBridge.upsertProvider` to match the decoder.
- **Ghost envelopes in `DeviceProvidersZone`.** Mac-side P4 pushed `ProviderUsageSnapshot`s with `accountEmail == nil` during early app startup (before OAuth / cookies loaded), producing CKRecords with recordName `{deviceID}|{providerID}|_`. Once the provider's account email loaded, subsequent pushes went to a DIFFERENT recordName (`{deviceID}|{providerID}|user@example.com`), leaving the empty "ghost" record behind. The iOS side then upserted both into SwiftData and into the merged view, producing a blank third "codex" card overwriting the real data. Fix: `SnapshotCache.isGhost(...)` drops envelopes where `primary`/`secondary`/`rateWindows`/`costSummary`/`budget`/`statusMessage` are all nil/empty and `isError == false`. Applied in `replaceFromFullFetch` / `applyDelta` / `replacePerProviderFromReplay`.
- Mac-side preventative fix (skip empty-data pushes to begin with) is a separate follow-up; this defense eliminates the symptom without a Mac rebuild.

### Tests
- `SnapshotCacheTests` +3 cases: ghost dropped from full fetch, ghost dropped from delta, error-only provider NOT considered ghost.

### Removed
- Diagnostic prints added in Build 62 / 64 / 65 are all cleaned up.

### Also re-verified
- `recordName` Queryable index on `DeviceProviderSnapshot` in CloudKit Production schema (user deployed earlier); per-provider zone query now returns `.success(1 devices)` instead of `.error(Field 'recordName' is not marked queryable)`.

## [1.3.0 (65)] — 2026-04-20 — dev build · trace SwiftData rateWindows write/read

Build 64 confirmed SwiftData hydrate returns `rateWindows=0` on every cold start despite fresh full fetch. Build 65 adds prints inside `SwiftDataBridge.upsertProvider` (what gets encoded) and `readAllDeviceSnapshots` (what gets decoded) to find which side drops the data.

## [1.3.0 (64)] — 2026-04-20 — dev build · deeper diagnostic for Usage cold-start blank

User confirmed Build 63's material swap did NOT fix the perceived blank. So the problem isn't GPU-first-frame cost — it's a data-layer asymmetry between Cost and Usage tabs. Adds `[CodexBar Diag]` prints that log:
- Per-device / per-provider hydrate contents from SwiftData (rateWindows count, costSummary presence, etc.)
- Which branch `UsageTab.body` and `CostTab.body` take (Onboarding vs EmptyState vs content)
- `fetchFromCloudKit` entry + per-zone results
Will be removed once the real root cause is identified.

## [1.3.0 (63)] — 2026-04-20 — dev build · fix Usage-tab cold-start "blank" via material swap

### Fixed
- **Usage tab no longer shows a ~1s blank on cold start.** `ProviderUsageView`'s card background was `.thickMaterial` — the most expensive material in the system (large Gaussian blur radius + heavy tint + independent GPU compositing pass per card). On first render after kill+relaunch, GPU setup for every card's thick material blocked the first frame ~1s. Changed to `.ultraThinMaterial` to match the rest of the app (`CostMetricCard`, `BudgetProgressView`, `ContentView`'s Cost dashboard, `ProviderDetailView`, `UtilizationAggregateView`). Verified via `[CodexBar Timing]` diagnostic prints (Build 62): data was always in memory at body time (`providers=2` within 0.238s of init), the delay was purely GPU first-frame compositing.

### Investigation
- `git blame` showed the `.thickMaterial` was introduced in commit `408ce6f25` (2026-03-19) with unrelated message "Fix mobile metrics and release notes", replacing the original `.regularMaterial + glassEffect` pair. No design discussion recorded; bundled with 5 other unrelated file changes. Cost-side cards (`CostMetricCard` etc.) were never changed to match — the asymmetry was accidental drift, not a deliberate visual choice.

### Removed
- The `[CodexBar Timing]` diagnostic prints added in Build 62 (reverted now that the root cause is confirmed and fixed).

### Visual impact
- On CodexBar's solid `systemGroupedBackground`, `.thickMaterial` and `.ultraThinMaterial` are visually indistinguishable (user inspection confirms). No user-visible change to card appearance.

## [1.3.0 (62)] — 2026-04-20 — dev build · diagnostic timing prints

Non-functional. Adds `[CodexBar Timing]` print lines in `SyncedUsageData.init`, `UsageTab.body`, `ProviderListView.body`, and per-card `onAppear` so I can measure the "Usage tab blank ~1–2s on cold start" observation. To be removed once the root cause is confirmed.

## [1.3.0 (61)] — 2026-04-19 — dev build · P6 + P7 v2 (cache-based, multi-device-safe)

### Re-introduced, re-designed
- **P6 · Change-token incremental sync (v2)** — `CKFetchRecordZoneChangesOperation` on `DeviceProvidersZone` is back, with a clean separation from SwiftData: the v1 bug (stale SwiftData rows from past full-fetch upserts leaking into the per-provider bucket) is eliminated because the incremental path now writes to an in-memory `SnapshotCache` with explicit `perProviderByDevice` vs `legacyByDevice` slots.
- **P7 · Silent-push-driven refresh (v2)** — `CKRecordZoneSubscription` on `DeviceProvidersZone` and the `AppDelegate.didReceiveRemoteNotification` routing are both restored, now triggering `SyncedUsageData.refreshIncremental` which applies the change-token delta to the cache. Legacy bucket is never touched by a silent push.

### Design changes vs v1
- `SnapshotCache` (in `CodexBarMobile/Models/SnapshotCache.swift`) keeps per-zone slots explicitly. Priority merge reads from it and never consults SwiftData.
- Token persistence via `SwiftDataBridge.loadChangeToken` / `saveChangeToken` kept (tokens are explicitly zone-scoped, no ambiguity). `applyPerProviderDelta` deleted — cache replaces its role.
- `SyncedUsageData.fetchFromCloudKit` now calls the two zone queries separately and feeds both into `cache.replaceFromFullFetch`. Prior logic that went through `CloudSyncManager.fetchAllDeviceSnapshots`'s internal priority merge is still available but unused by the cache path — kept for completeness.

### Multi-device trace
Research/011 carries six explicit scenarios (Mac-A-new + Mac-B-old, both new, both legacy, iPhone-old × Mac-new, iPhone-new × Mac-old, 2 iPhones × 2 Macs). The test suite `SnapshotCacheTests` has assertions that mirror three of them directly.

## [1.3.0 (60)] — 2026-04-19 — dev build · rollback P6 + P7

Multi-device data regression reverted. Build 59 shipped P6 (change-token incremental sync) and P7 (silent push → incremental refresh), but the incremental path read per-device state from SwiftData, which also contained historical rows populated by past legacy-zone full-fetch upserts. When Mac A (on the new per-provider zone) triggered a silent push, the incremental path wrote Mac A's fresh delta to SwiftData, then reconstructed the "per-provider zone set" by reading SwiftData — which wrongly included stale Mac B rows from legacy history. The priority merge then let stale Mac B data win over the fresh legacy fetch, producing flicker / missing-data symptoms in multi-Mac setups.

### Reverted
- **P7 · Silent-push-driven refresh** — subscription setup, AppDelegate `didReceiveRemoteNotification` handler, and the `SyncedUsageData.refreshIncremental` observer are all removed. Silent pushes to `DeviceProvidersZone` no longer trigger any iOS work.
- **P6 · Change-token incremental sync** — `CKFetchRecordZoneChangesOperation` path, change-token persistence, `SwiftDataBridge.applyPerProviderDelta`, and the `CodexBarMobileTests/Storage/PerProviderDeltaTests` suite are all removed.

### Kept (still correct)
- **P3 · SwiftData cold-start hydrate** — unchanged, no multi-device issue.
- **P4 · Mac dual-write** — Mac still writes per-provider records to `DeviceProvidersZone` alongside the monolithic legacy record. Shared types (`ProviderUsageEnvelope`, `PayloadCompression`) retained.
- **P5 · Dual-zone reader** — the FULL-fetch path (app open / pull-to-refresh) queries both zones fresh from CloudKit every time and priority-merges per device. This path never touched SwiftData for the priority decision, so it didn't have the bug.

### Design debt carried forward
The incremental + silent-push behavior needs a redesign before it can come back. The lesson: SwiftData is a read-through cache, not a per-zone "what's in this zone" mirror, because full-fetch upserts and delta upserts both write to it indiscriminately. Any future incremental path must either track zone-of-origin on `DeviceRecord`, or stop reading SwiftData for priority decisions and query CloudKit fresh each push.

## [1.3.0 (59)] — 2026-04-19 — dev build (refactor-1.3.0)

Internal-only build. No user-visible feature changes yet; the tap target is the sync pipeline, which reshapes how device data flows from Mac → CloudKit → iPhone.

### Refactored (sync layer, invisible to users on this build)
- **P3 · SwiftData-hydrated cold start** — `SyncedUsageData.init` now tries the local SwiftData mirror before falling back to KVS, so the Cost tab no longer flashes a stale "$46" before settling on the real total a second later. First launch on a fresh phone still uses KVS (SwiftData empty).
- **P4 · Mac dual-write** (requires Mac 0.20.1+) — Mac writes each provider into its own CloudKit record in a new `DeviceProvidersZone`, zlib-compressed, in addition to the monolithic `DeviceSnapshot` legacy zone. Older iOS builds keep reading legacy; this build can use either.
- **P5 · Dual-zone reader with priority merge** — iOS queries both zones; per-device, the new per-provider records win over the legacy monolithic record, with graceful fallback when either side is empty.
- **P6 · Change-token incremental sync** — `CKFetchRecordZoneChangesOperation` with persisted `CKServerChangeToken` replaces the full-table query for the per-provider zone. Typical sync transfer drops from ~2 MB to a few dozen KB. `changeTokenExpired` triggers a transparent full replay.
- **P7 · Silent-push-driven refresh** — new `CKRecordZoneSubscription` with `shouldSendContentAvailable = true` on `DeviceProvidersZone`. When Mac writes, iOS wakes silently, runs the change-token fetch, applies to SwiftData, and views refresh — without the user pulling to refresh.

### Notes
- End-to-end (new zone actually populated) requires a Mac running 0.20.1+ AND the CloudKit Production schema to be deployed for the new record type. Until both land, iOS silently falls back to legacy, zero regression.
- Build 59 includes Build 58's bug fix for compositeKey format mismatch between SwiftData and CloudKit record names (aligned on `"_"` for nil `accountEmail`).

## [1.2.0 (58)] — 2026-04-15

### Reverted (partially) + improved
- **Restored the Setup Guide upgrade-notice block** that Build 57 deleted. The decision to drop it was wrong — that orange "Important" callout is a prominent way to tell new users they need a specific Mac version before iPhone features will work, and removing it left the Setup Guide silent on the Mac requirement (only Step 1 said "install on Mac" without specifying which Mac version).
- Block text updated for the 1.2.0 era: title `"v1.2.0 — New Mac App Required"`, body `"Subscription Utilization and Mac→iPhone push notifications need CodexBar Mac 0.19.0 (Build 54.1.2.0) or later."`. Both strings added to `Localizable.xcstrings` with full en / ja / zh-Hans / zh-Hant translations — the gap that made the original Build 56-and-earlier text fall back to English on non-English iPhones.

## [1.2.0 (57)] — 2026-04-15

### Fixed
- **Setup Guide (onboarding) had hardcoded English text "v1.1.0 — New Mac App Required" at the top of the Chinese/Japanese/Traditional-Chinese pages.** The upgrade-notice block was introduced for the 1.0.0 → 1.1.0 transition, never updated for 1.2.0, and never added to `Localizable.xcstrings`. Dropped the entire block — the same information (download Mac app from GitHub) is already covered by Step 1 of the setup and by the Important section of the 1.2.0 release notes. One less thing to keep in sync across four languages.
- **Audit of all `Text(…)` literals found 7 more hardcoded English strings missing from `Localizable.xcstrings`**: `"Data pushed by Mac · Pull to check for updates"` (the Usage/Cost tab status bar), `"Mac Update Available"` + `"Your Mac is using legacy sync. …"` + `"Download Latest Mac Version"` (the legacy-sync upgrade banner in About & Sync), `"Sync Status"` + `"No devices synced yet"` + `"No device data available"` (About & Sync section labels / empty states). Added 4-language translations for all 7. Developer Tools strings deliberately left in English per earlier decision.

### Notes
- The onboarding trigger logic is unchanged: it compares `@AppStorage("onboardingSeenVersion")` against `CFBundleShortVersionString` (the marketing version, e.g. `1.2.0`), not the build number. A build-only update from 1.2.0 (56) to 1.2.0 (57) **does not** retrigger onboarding. Onboarding only auto-shows on a marketing version bump (e.g. 1.1.0 → 1.2.0) or when the user explicitly taps `Settings → Setup Guide`.

## [1.2.0 (56)] — 2026-04-14

### Changed
- **1.2.0 release notes restructured per user feedback**: the Settings / Developer Tools bullet moved from `What's New` to `Improvements` (it is a tidy, not a feature), and the "About page build date in English" clause was removed entirely — that fix landed on the Mac side (commit `686311b3`, task `6gJG6vpwJxG6frm2` "1.2.0 · Mac 端 Utilization CloudKit 完善 + 版本升级 + About 修复") and does not belong in iOS release notes. Final structure: 3 `What's New` items (Utilization, Multi-Mac, Push) + 1 `Improvements` item.

## [1.2.0 (55)] — 2026-04-14

### Fixed
- **1.1.0 release notes were English-only on non-English iPhones** — all 8 of the 1.1.0 `What's New` / `Improvements` / Important / summary entries were never added to `Localizable.xcstrings`, so Chinese / Japanese / Traditional-Chinese users saw the raw English `String(localized:)` keys. Added full 4-language translations for every 1.1.0 entry.
- **1.2.0 release notes had untranslated section headers** — the `"Important"` and `"Improvements"` section titles were missing from `Localizable.xcstrings` while the item bodies were localized, which made the 1.2.0 notes render as a bizarre mix of Chinese body text under English headers. Added 4-language translations for both titles.

### Changed
- **1.2.0 release notes rewritten around the four features that 1.2.0 actually ships** (Subscription Utilization visualization, multi-Mac data merge, Mac→iPhone push notifications with provider name, streamlined Settings + Developer Tools). `Improvements` section folded into the fourth "What's New" bullet. All four bullets translated to en / ja / zh-Hans / zh-Hant.
- **Important section now requires (not recommends) Mac 0.19.0 (Build 54.1.2.0) or later** — previous wording said "works best with the latest Mac app", which understated the dependency. Subscription Utilization data collection and Mac→iOS push both genuinely need that Mac version.
- **Push Setup diagnostic subscription list grouped by ID pattern** — before Build 55 the `allSubscriptions()` output listed all 47 subscriptions one per line, drowning the real signal; now grouped into `device-snapshot-changes`, `quota-*-depleted-sub`, `quota-*-restored-sub`, and a `quota-transition-*` LEGACY bucket (should always be 0 after a healthy Build 54 upgrade). Each group shows its count + a sample `alertBody`.

## [1.2.0 (54)] — 2026-04-14

### Fixed
- **Push notifications now show the provider name in the body** — e.g. "Codex 的会话额度已耗尽" on a Chinese iPhone, "Codex session quota depleted" on an English iPhone. Build 53's `UNNotificationServiceExtension` approach proved unreliable on this CloudKit container — on-device verification showed the extension didn't wake, very likely because the container silently strips the `shouldSendMutableContent` flag the same way it strips `titleLocalizationArgs`. Build 54 falls back all the way to the mechanism Build 48 / 52 proved persists reliably (a plain `CKRecordZoneSubscription` with a static `alertBody`) and scales it horizontally.

### Changed
- **One subscription per `(provider, state)` pair, ≈ 46 subscriptions total**, each with the provider's display name pre-baked into its `alertBody` via `String(format: "%@ session quota depleted", providerName)` against localized templates (`Push.QuotaDepleted.bodyWithProvider` / `Push.QuotaRestored.bodyWithProvider`, 4 languages). The iPhone's locale is resolved at subscription-setup time.
- **Mac `writeQuotaTransition` routes to a per-provider zone** named `Quota-{providerID}-{state}Zone` (e.g. `Quota-codex-depletedZone`). The shared Build 52/53 `QuotaDepletedZone` / `QuotaRestoredZone` are no longer written to — Mac simply picks the zone matching the current `(provider, state)`.
- **`QuotaProviderList` (shared)** lists the 23 providers + display names that track `UsageProvider` on Mac. New provider additions upstream require an iOS shipping update to be subscribed to.
- **Sub setup batched**: a single `modifyRecordZones(saving: [...46 zones])` + a diff-driven `modifySubscriptions(saving: [drifted subs only], deleting: [])`. Returning launches whose configs are already correct cost only one `allSubscriptions()` round-trip.
- **Legacy subs deleted on upgrade**: `quota-transition-zone-sub` (Build 42–49) + `quota-transition-depleted` / `quota-transition-restored` (Build 52/53).

### Notes
- **The `CodexBarMobilePushExtension` target is retained but dormant**: subscriptions no longer set `shouldSendMutableContent`, so iOS will never wake the extension. We keep the code around as a future-revival hook; for the foreseeable future the plain static-body mechanism is the only one that has been empirically proven on this container.
- **The body text includes the provider; the title stays as the iOS default "CodexBar"**. Title override requires the extension path, which this container does not support.

## [1.2.0 (53)] — 2026-04-14

### Added
- **Push notifications now include the provider name as the title.** Mac local notifications have always shown e.g. "Codex session depleted" — iOS push from Build 52 only showed the state ("会话额度已耗尽") without provider. Build 53 closes this gap via a new `UNNotificationServiceExtension` (`CodexBarMobilePushExtension`) target that intercepts the push, fetches the latest `QuotaTransition` record from the triggering zone, reads `providerName`, and sets it as `content.title`. The Build 52 locale-resolved body is preserved as `content.body`, so a Chinese iPhone now sees title "Codex" + body "会话额度已耗尽" instead of just "会话额度已耗尽".

### Architecture notes
- The extension target carries its own iCloud + CloudKit container entitlements (Production environment) so it can fetch records from the same private database the main app uses.
- Subscriptions now set `info.shouldSendMutableContent = true` so APNs flags pushes with `mutable-content: 1`, which is what wakes the extension. This boolean does not reference any record fields, so it does not trigger the Build 49/50 "args silently drop" failure mode (`titleLocalizationArgs` / `alertLocalizationArgs` referencing record fields). The "already correct" check on existing subscriptions is updated to require `shouldSendMutableContent`, so Build 52 subs are recreated on first launch of Build 53.
- Extension fetch path: `CKQuery(recordType: "QuotaTransition", predicate: TRUEPREDICATE)` against the state-specific zone with `desiredKeys: ["providerName", "transitionAt"]`, sorted in code by `transitionAt` (no Sortable schema requirement). If the fetch fails or times out (~30s budget), the extension delivers the unmodified push content — same UX as Build 52, no regression.
- Pure parsing helpers moved to `Shared/Notifications/QuotaZoneNotificationParser.swift` so the test target can verify them without depending on the extension target. Seven new unit tests in `CodexBarMobileTests/QuotaZoneNotificationParserTests.swift` cover zone-name acceptance, legacy-zone rejection, empty/non-CloudKit `userInfo` handling.

### Research
- 15 alternative architectures for adding provider-in-push were enumerated by parallel research agents and are documented in `Research/005-push-provider-alternatives.md`. The chosen `UNNotificationServiceExtension` design (matching alternative #14 in that doc) is fully described in `Research/006-push-provider-nse.md`.

## [1.2.0 (52)] — 2026-04-13

> **Version label note:** `xcodebuild -exportArchive` auto-bumps `CFBundleVersion` on App Store Connect collision. The commit that produced this build (`8654c6d7`) was authored with `CURRENT_PROJECT_VERSION = 51` but uploaded as 52 because 51 was already present on ASC. The `project.yml` bump 51 → 52 in the subsequent commit reconciles the label.

### Fixed
- **Push notification subscription persistence — regression from Build 51 fixed.** Build 51 (the commit that shipped as TestFlight 52 — see label note above; the preceding TestFlight 51 was labelled "Build 50" in the commit that produced it) tried to use `CKSubscription.NotificationInfo.titleLocalizationArgs = ["providerName"]` on the assumption that `providerName` (present in the Production schema since the post-Build-48 Shared changes) was safe to reference. On-device verification proved otherwise: `allSubscriptions()` returned only the legacy `device-snapshot-changes` sub after install, same failure mode as the earlier arg-stripping build (commit `65960ac8`). **Any subscription carrying args is silently dropped by CloudKit on this container, regardless of which field the args reference.**

### Changed
- **Push notification text is now localized on the iOS side via `String(localized:)`.** The `alertBody` is resolved at subscription-creation time against the iPhone's current locale (using the pre-translated `Push.QuotaDepleted.body` / `Push.QuotaRestored.body` keys in `Localizable.xcstrings`) and baked into the subscription payload as a literal string. CloudKit delivers that string verbatim at push time — no args, no server-side substitution. Each iPhone sees the push in its own language (en / ja / zh-Hans / zh-Hant); Mac-side language is irrelevant.
- If the user switches iPhone locale between sessions, the push text updates on next app launch: the `"already correct"` check compares the stored `alertBody` against a freshly-resolved `String(localized: …)`, mismatches, and recreates the subscription with the new locale's text.
- The Build 50 zone split (`QuotaDepletedZone` / `QuotaRestoredZone`) is **retained**. State differentiation still comes from the zone, which is how iOS knows at setup time which localized body to bake into which subscription.

### Notes
- Definitive takeaway recorded in `Research/004-alert-push-cloudkit.md`: subscription localization args are unusable on this CloudKit container. Pass-through-from-record designs (Plan A) are not viable. The replacement pattern is iOS-side `String(localized:)` at subscription-creation time, keyed off the zone (which is state-specific).

## [1.2.0 (51)] — 2026-04-13

> **Version label note:** This entry was committed as "(build 50)" in commit `c899e997` (`project.yml` = 50), but `xcodebuild -exportArchive` auto-bumped the upload to 51 after App Store Connect rejected 50 as a duplicate. TestFlight delivered build 51. **Build 51 turned out to have a regression (see 52 below) — iOS `allSubscriptions()` returned only the legacy `device-snapshot-changes` sub, the two new quota subs did not persist.**

### Added (attempted — regressed)
- **Locale-aware Mac→iOS push notifications.** Each iPhone was intended to render the quota push in its own locale (English / 简体中文 / 繁體中文 / 日本語) using the pre-translated `Push.QuotaDepleted.*` and `Push.QuotaRestored.*` keys in `Localizable.xcstrings`. Mac writes only the untranslated `providerName` field into the record; CloudKit was to substitute it into the title template at push time via `titleLocalizationArgs = ["providerName"]`, and iOS was to resolve the templates against its current locale.

### Changed
- **Quota transition state differentiation moved from predicate to zone.** Instead of a single zone-wide subscription with a static `alertBody = "Session quota changed"`, iOS now carries two `CKRecordZoneSubscription`s — one on the new `QuotaDepletedZone` and one on `QuotaRestoredZone` — each with its own localization key. The split lets each subscription own a static `titleLocalizationKey` / `alertLocalizationKey` while staying on the persisting subscription type (`CKRecordZoneSubscription` — `CKQuerySubscription` is still silently non-persisting on this container).
- `CloudSyncManager.writeQuotaTransition` picks the destination zone from the transition state and drops `notificationTitle` / `notificationBody` parameters (no longer needed). `recordName` is now `(providerID, hourBucket)` — state is implicit in the zone.
- The Build 42–49 legacy subscription `quota-transition-zone-sub` is explicitly deleted on upgrade. The legacy `QuotaTransitionsZone` is left in place (no harm: Mac no longer writes to it).

### Notes
- **No CloudKit Dashboard schema deploy is required for this change.** Zones are created on-demand, and the only field referenced by subscription args (`providerName`) has been in the Production schema since Build 48. This avoids the Build 49 (`65960ac8`) failure mode where args referencing undeployed fields caused subscriptions to silently not persist.
- Covers the v4 push notification iteration through Builds 43–49 (subscription type, DB, zone, localization). See `Research/004-alert-push-cloudkit.md`.

## [1.2.0 (42)] — 2026-04-08

### Added
- **Mac→iOS push notifications, v2 (CloudKit alert push design).** When a session quota becomes depleted or restored on the Mac, iPhone receives a visible push notification ("Codex" / "Session quota depleted") delivered directly by APNs without the iOS app needing to wake up. **Background App Refresh is no longer required.** See `Research/004-alert-push-cloudkit.md` for the full design rationale.
  - Mac side: when a transition is detected, write a small `QuotaTransition` record to CloudKit (provider name + state + timestamp + deviceID), debounced 5 minutes per (provider, state).
  - iOS side: two `CKQuerySubscription`s on `QuotaTransition` (one filtered by `state == "depleted"`, one by `state == "restored"`), each with a `notificationInfo.titleLocalizationKey` + `titleLocalizationArgs = ["providerName"]` that lets CloudKit fill in the provider name from the record at push time.
  - Localized in 4 languages (en / ja / zh-Hans / zh-Hant).
- **Independent Mac and iOS notification toggles.** Mac local notifications (Settings → General) and iOS push notifications (Mac Settings → Mobile → "Push notifications to iOS") are now decoupled. You can keep Mac silent and still get alerts on your iPhone, or vice versa, or both, or neither.
- **Mac DEV "iOS Push Test" buttons** (Settings → Mobile, debug build only) — writes a real `QuotaTransition` record so the full pipeline can be exercised end-to-end without waiting for an actual quota change.

### Changed
- `UsageStore.handleSessionQuotaTransition` refactored: transition computation moved before the `sessionQuotaNotificationsEnabled` gate, so the Mac local notification path and iOS push path can be controlled independently. Existing Mac local notification behaviour (gated by `sessionQuotaNotificationsEnabled`) is preserved unchanged.

### Notes
- Compared to the v1 silent-push design (rolled back in build 41): no Background App Refresh dependency, no UN authorization required for the silent-push path, no iOS app wake-up needed, no client-side baseline tracking, no diagnostic infrastructure. Net deletion of ~700 lines from build 40 → 41 → 42.

## [1.2.0 (41)] — 2026-04-08

### Removed
- **Mac→iOS push notification feature, in its entirety.** The CloudKit silent push (`shouldSendContentAvailable=true`) architecture is dropped because it requires Background App Refresh to be enabled on the device — and even then is silently throttled by iOS in many real-world conditions. The feature will return in a future release built on a different architecture (alert push triggered by a small server-decided record, no client-side wake-up needed).
- `AppDelegate.swift` (remote notification handler), `SessionQuotaMonitor.swift` (transition detection), `LocalNotificationManager.swift` (local notification posting), `PushDiagnosticStore.swift` (debug store)
- iOS Push Diagnostic developer tool and its navigation entry under Developer Tools
- iOS "Session quota notifications" toggle in Usage Setting
- iOS `aps-environment` entitlement and `UIBackgroundModes` from `Info.plist`
- Mac `MacPushDiagnostics.swift` (Mac-side debug pane) and the entire DEV "iOS Push Testing" section in `PreferencesMobilePane`
- Mac "Push notifications to iOS" toggle and `notificationPushToiOSEnabled` setting
- `SyncCoordinator.pushTestSnapshot` and the test-lock plumbing
- `CloudSyncManager.setupSubscription` and `subscriptionID` constant

### Notes
- iCloud data sync (Mac→iOS usage data display) is unaffected — that path still uses `pushSnapshot` / `fetchAllDeviceSnapshots` on the existing custom zone.
- The `DeviceSnapshotsZone` custom record zone is intentionally kept (rather than reverting to `_defaultZone`) so the future Plan B work can reuse it without another data migration.

## [1.2.0 (40)] — 2026-04-08

### Added
- **`UIBackgroundModes: fetch`** in Info.plist alongside the existing `remote-notification`. Apple's `CKQuerySubscription` documentation explicitly requires both Background Modes to be enabled for silent push notifications to wake the app. The previous build was missing `fetch`.
- **Runtime Environment** section in Push Diagnostic showing the values that actually shipped in the signed binary, not what the source files claim:
  - `aps-environment` read from `SecTaskCopyValueForEntitlement` — proves whether the device registered with Sandbox or Production APNs
  - `icloud-container-environment` — must match Mac side
  - `Background App Refresh` status — required for silent push delivery
  - `Low Power Mode` — iOS throttles silent push when on
  Mismatches are highlighted in orange so the user can spot them at a glance.

## [1.2.0 (39)] — 2026-04-08

### Fixed
- **CloudKit silent push delivery (root-cause fix)** — `DeviceSnapshot` records now live in a custom record zone (`DeviceSnapshotsZone`) instead of `_defaultZone`, and iOS subscribes via `CKRecordZoneSubscription` instead of `CKQuerySubscription`. The previous architecture was the documented dead-end for private-database silent push: query subscriptions on the default zone do not deliver pushes reliably (Apple's official `apple/sample-cloudkit-privatedb-sync` uses the same custom-zone + zone-subscription pattern). On first launch the iOS app self-heals: it queries the server for the existing subscription, deletes the legacy `CKQuerySubscription` if found, and creates a fresh `CKRecordZoneSubscription` bound to the current APNs device token.

### Changed
- `CloudSyncManager.fetchAllDeviceSnapshots()` now reads from BOTH the custom zone (where build 39+ Macs write) and the default zone (where pre-39 Macs may still be writing). Snapshots are deduped by `deviceID` keeping the most recent `syncTimestamp` per device, so the iOS app stays correct during the cross-device migration window.
- `CloudSyncManager.ensureCustomZoneExists()` and `setupSubscription(forceRecreate:)` use a fetch-first self-healing pattern: every call queries the server's actual state instead of trusting a local UserDefaults flag. This is robust to iCloud account switches, manual server-side resets, and external dashboard deletions.
- Push Diagnostic "Re-create CKSubscription" button now passes `forceRecreate: true`, bypassing the no-op fast path so the user can manually refresh the device-token binding after a TestFlight reinstall.

## [1.2.0 (38)] — 2026-04-06

Marketing version bump that rolls up all the utilization, multi-device sync, and Settings reorganization work since 1.1.0.

### Added
- **Subscription Utilization section in the Cost tab** — 30-day daily bar chart aligned with the cost chart, four period summary cards (Today / This Week / 14 Days / 30 Days) each with delta vs the previous period, and an inline Provider Share breakdown that shows each provider's proportional share of total utilization (sums to 100%).
- **Subscription Utilization History chart on each provider detail page** — scrollable per-period bars (V4 Capsule style) covering session, weekly, and opus limits.
- **Push Diagnostic developer tool** — Settings → Developer Tools → Push Diagnostic. Surfaces APNS registration, CKSubscription state, UN authorization, last silent push, fetch/transition/notification results, and a 100-entry rolling event log. Manual actions: Fetch Now, Re-create CKSubscription, Post Test Local Notification, Clear Log.
- **Multi-device utilization merge** — utilization entries from all Macs are combined and deduped by `(hourSlot, resetEpoch)` so the chart stays consistent no matter how many devices report.
- Setup Guide promoted to a top-level Settings row (above About & Sync); tapping opens the existing onboarding sheet.

### Changed
- Provider breakdown in the Cost tab now shows proportional share (summing to 100%) instead of raw average percentages, matching the visual style of the cost Provider Share section.
- Subscription Utilization section title uses `.headline` to match every other Cost-tab section header.
- Developer Tools consolidated under a single Settings entry that navigates into a dedicated container page listing Raw Sync Data and Push Diagnostic.
- About page build timestamp is forced to `en_US` locale regardless of system language (app is English).

### Removed
- "How It Works" section from Settings (previously listed 3 informational items plus a Show Setup Guide button) — redundant with the promoted Setup Guide entry.
- "How It Works" subsection inside About & Sync detail — duplicated the same info.
- Dead localization keys for the removed strings.

### Fixed
- CloudKit utilization merge now picks the entry with the freshest `capturedAt` per hour bucket instead of the one with more entries — prevents stale data from an inactive Mac from overwriting fresh data from an active one.

## [1.1.0 (37)] — 2026-04-06

### Changed
- **Promoted Setup Guide to a top-level Settings row.** It now sits at the very top of the first section (above About & Sync), opens the existing Setup Guide sheet on tap, and uses the `sparkles` icon.

### Removed
- The standalone "How It Works" section in Settings (previously listed 3 informational items plus a Show Setup Guide button). Now redundant with the promoted Setup Guide entry.
- The "How It Works" section inside About & Sync detail — duplicated the same information.
- Dead localization keys: `How It Works`, `Show Setup Guide`, `CodexBar on your Mac pushes usage data to iCloud`, `Data syncs automatically when both devices are online`, `This app reads the latest snapshot via iCloud Key-Value Store`.

## [1.1.0 (36)] — 2026-04-06

### Changed
- **Consolidated dev tools under a single "Developer Tools" entry** — Settings → Developer now shows one row that navigates into a dedicated page listing Raw Sync Data and Push Diagnostic. Future tools can be added there without cluttering the main Settings list.

## [1.1.0 (35)] — 2026-04-06

### Changed
- Renamed the Settings → Developer section to **Developer Tools**, now housing both "Raw Sync Data" and "Push Diagnostic". These screens are intentionally shipped to production builds so end users can self-diagnose sync/push issues (no sensitive data exposed).

## [1.1.0 (34)] — 2026-04-06

### Added
- **Push Diagnostic** developer view (Settings → Developer → Push Diagnostic) that surfaces every step of the Mac→iOS push notification chain in-app: APNS registration, CKSubscription status, UN authorization, last silent push received, last fetch result, last transitions, last local notification post, and a rolling event log
- `PushDiagnosticStore` — observable store tracking registration/subscription/push/fetch/transition/notification state with a 100-entry event log
- Manual diagnostic actions: "Fetch Now", "Re-create CKSubscription", "Post Test Local Notification", "Clear Event Log"
- `CloudSyncReader.setupSubscriptionWithDiagnostics()` wrapper that captures any error thrown from the shared `CloudSyncManager.setupSubscription()` instead of letting it be swallowed by `try?`
- `LocalNotificationManager.postDiagnosticTestNotification()` for verifying the UN pipeline end-to-end from the Diagnostic view

### Changed
- `AppDelegate` now reports every remote-notification lifecycle event (registration success/failure, push received, fetch result, transitions, notification post) into `PushDiagnosticStore` so the diagnostic view updates live
- `LocalNotificationManager.postSessionQuotaNotification` now returns `Bool` so the caller can record success/failure in diagnostics

## [1.1.0 (33)] — 2026-04-06

### Changed
- Subscription Utilization section title now uses `.headline` (was `.title3.bold()`), matching every other section header in the Cost tab
- Provider share rows are now merged directly into the Subscription Utilization section — the previous "Provider Share" sub-header (title + caption) is gone, and the cards sit under the daily chart as part of the same section
- Section subtitle updated to describe the whole section ("Session quota usage trend across synced providers.")

## [1.1.0 (32)] — 2026-04-06

### Removed
- Release notes items mistakenly appended to the 1.1.0 in-app catalog (`MobileReleaseNotesCatalog`) in build 31. The in-app catalog is reserved for major version updates and should not be touched on minor build bumps.

## [1.1.0 (31)] — 2026-04-06

### Changed
- **Subscription Utilization chart redesigned with daily granularity** — bars are now per-calendar-day (matching the Cost chart's 30-day window) instead of per-week
- **Four period summary cards** — Today, This Week, 14 Days, 30 Days, each with delta vs previous period (orange ↑ / green ↓)
- **Provider Share breakdown** — replaces raw average % with proportional share% (sums to 100% across providers), styled to match the Cost tab's Provider Share section
- 30-day raw average shown as subtitle context for each provider in the share breakdown

### Added
- 4-language localization for new strings: `14 Days`, `This Week`, and `30-day utilization share across synced providers.`

## [1.1.0 (25)] — 2026-04-01

### Added
- **Session quota push notifications** — iOS receives silent push from CloudKit when Mac detects quota changes, posts local notification for depleted/restored events
- `AppDelegate` with remote notification handler for CloudKit silent push processing
- `SessionQuotaMonitor` for detecting quota state transitions (depleted ≤0.01% / restored)
- `LocalNotificationManager` for posting user-visible notifications with sound
- Notification toggle in Settings → Usage → Notifications section (enabled by default)
- 4-language localization for all notification strings

### Changed
- App architecture upgraded: added `UIApplicationDelegateAdaptor` for background notification handling

## [1.0.0 (23)] — 2026-03-23

### Changed
- **iCloud sync upgraded from KVS to CloudKit** — each Mac now writes its own device record; iPhone merges all devices
- Multi-Mac support: providers from different Macs are combined on iPhone instead of last-write-wins
- Cost data from local-source providers (Claude, Codex, VertexAI) is summed across devices; account-level providers deduplicate
- Sync status now shows specific CloudKit errors (network, auth, quota) instead of generic "synced/not synced"
- Mac side generates a stable device UUID (persisted in UserDefaults) for CloudKit record identity
- KVS dual-write maintained for backward compatibility with older iOS builds

### Added
- `CloudSyncError` enum with CKError-to-user-readable mapping
- `MultiDeviceSyncResult` for multi-device CloudKit fetch results
- `SyncStatus` enum (`.synced` / `.syncing` / `.error` / `.noData` / `.incompatibleData`)
- `deviceID` field on `SyncedUsageSnapshot` for per-device CloudKit records
- CKQuerySubscription setup for silent push notifications on record changes
- Multi-device merge logic with per-provider cost aggregation strategy
- CloudKit + background remote notification entitlements (iOS + Mac)
- 13 new tests: multi-device merge (9), sync error mapping (14 total in suite)

## [1.0.0 (22)] — 2026-03-21

### Added
- App Store screenshot source assets under `AppStoreScreenshots/v0` and `AppStoreScreenshots/v1-screenshot`
- Finalized Chinese App Store screenshots under `AppStoreScreenshots/v1-styled`
- Matching English App Store screenshots under `AppStoreScreenshots/v1-styled-en`
- Reusable screenshot generation script for localized marketing images

## [1.0.0 (21)] — 2026-03-20

### Added
- Vibe (cyberpunk) share card style with arc gauges, neon glow, and "Did you vibe today?" headlines
- Style picker in share sheet: Classic / Vibe
- Dark and light theme support for both Classic and Vibe styles
- Save to Photos option in share sheet (NSPhotoLibraryAddUsageDescription)
- QR code and link updated to codexbarios.o1xhack.com

### Changed
- Share card headlines forced to single line across all 4 languages (minimumScaleFactor)
- In-app release notes now merge updates within the same marketing version
- AGENTS.md Step 5 updated with release notes merge rule

### Fixed
- Share sheet not showing "Save Image" option due to ShareLink Transferable limitation

## [1.0.0 (15)] — 2026-03-20

### Added
- One-tap share button on Cost tab to generate shareable cost report images
- Share sheet with period picker (Today / 7 Days / 30 Days) and live card preview
- Three share card styles: today (provider breakdown), 7-day and 30-day (stacked bar chart)
- Stacked bar chart colored by provider (top 3 + "Others" for 4+ providers)
- QR code footer linking to CodexBar project
- Feature research framework under Research/ with status tracking (draft → done → dropped)
- Research doc 001: Daily Utilization Chart (blocked-upstream, PR #565)
- Research doc 002: Cost Share Card (done)

### Changed
- CLAUDE.md simplified to project overview; AGENTS.md now holds complete 7-step workflow
- Share card charts follow dataviz conventions (largest segment at bottom for stable baseline)

## [1.0.0 (13)] — 2026-03-19

### Changed
- Refined in-app release note: replaced screenshot coverage note with clearer label readability improvement

## [1.0.0 (12)] — 2026-03-19

### Fixed
- In-app release notes now preserve the original 1.0.0 launch notes while prepending the latest build updates

## [1.0.0 (11)] — 2026-03-19

### Changed
- Usage percentage labels now keep a larger, fixed layout instead of scaling down under pressure
- Cost overview cards and trailing metrics in Cost lists now use adaptive fixed-width layouts for crisper numbers

### Fixed
- Blurry `% used` and `% left` labels on provider usage cards
- Soft or blurry trailing amount/share text in Provider Share and Model Mix rows

## [1.0.0 (10)] — 2026-03-18

### Changed
- Daily spend chart now scrolls horizontally, showing 30 days at a time with swipe for history
- Consolidated release notes into "What's New" and "Improvements & Fixes" sections
- Updated CLAUDE.md with jj workflow and commit automation rules
- Enriched demo data to 50 days with realistic spend curves

## [1.0.0 (9)] — 2026-03-17

Initial App Store release line, corresponding to the earlier Mobile `0.1.0` build.

### Added
- iOS companion app for CodexBar with iCloud Key-Value Store sync
- Provider list with dynamic rate limit progress bars and labels (Session, Weekly, Sonnet, etc.)
- Tappable provider cards with cost teaser line ("Today: $X.XX · 30d: $Y.YY")
- Provider detail view with interactive daily spend bar chart (SwiftUI Charts)
- Cost summary grid (session cost, 30-day cost, token counts)
- Budget progress bar with color-coded thresholds (red >90%, orange >70%)
- "Show remaining usage" toggle in Settings to display quota left instead of quota used
- iCloud sync error display (quota exceeded, account change notifications)
- iOS 26 Liquid Glass UI support (glass effect cards, soft scroll edges, tab bar minimize)
- Demo mode for previewing the app without Mac data
- About tab with sync status, developer info, and open source credits
- Display Mac app version and Sync version from iCloud payload in About tab
- Empty state views for waiting-for-sync and no-providers states
- Cost tab with provider share, model/service mix, and 30-day spend analysis
- In-app release notes page with the latest update summary and collapsible version history
- Privacy manifest, privacy policy, and dark mode app icon
- Onboarding flow, setup guide, and pull-to-refresh support
- Native localization for English, Simplified Chinese, Traditional Chinese, and Japanese

### Changed
- Usage and Cost charts support both Bar Chart and Line Chart styles
- 30-day charts support press-and-hold inspection for exact daily values
- Daily spend chart now scrolls horizontally, showing 30 days at a time with swipe to view history
- Chart Y-axis uses smart integer tick marks for cleaner readability
- Setting tab reorganized into Usage, Charts, and Privacy sections
- Mobile versioning is now aligned directly with the iOS app version number
- Dynamic version display now surfaces synced iPhone and Mac versions more clearly

### Fixed
- Pull to refresh now asks iCloud Key-Value Store to synchronize before reading the latest snapshot
- Mac sync status now reports missing iCloud entitlements or unavailable iCloud accounts instead of showing a false success state
- Fix iCloud sync entitlement check on iOS
