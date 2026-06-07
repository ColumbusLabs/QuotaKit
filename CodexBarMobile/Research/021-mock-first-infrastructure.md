# Mock-First Quality Infrastructure (Mac 0.23.5+ / iOS 1.5.2+)

**Status**: Live (Mac 0.23.5 / iOS 1.5.2 + later)
**Owner**: ColumbusLabs/QuotaKit contributors
**Architecture decision date**: 2026-05-03

---

## TL;DR

CodexBar covers ≥27 AI coding-tool providers, each with multi-account
support, cost dashboards, push notifications, and cross-Mac merge.
Manual testing the matrix (27 providers × N accounts × M error states)
is impossible. **Mock providers** are the project's core quality
infrastructure: a synthetic, opt-in injection layer that pushes 32
fake `ProviderUsageSnapshot` entries through the entire iCloud sync
pipeline, exercising every code path on iPhone without requiring real
provider subscriptions.

This document defines the contract, ownership, and forward-compat
expectations. PR template (`.github/PULL_REQUEST_TEMPLATE.md`) gates
changes against it.

---

## Why mocks exist (CTO view)

7 strategic premises behind the mock layer:

1. **Test coverage is non-linear**. Hand-testing 486 cases (27
   providers × 3 accounts × 6 states) doesn't fit in a quarter; one
   mock = N test cases free.
2. **Mix mode = double regression insurance**. 27 mocks use real
   provider IDs (exercise iOS first-class card UI); 2 use synthetic
   `_mock_*` IDs (exercise iOS unknown-provider fallback). Both
   paths must keep working — any divergence is caught.
3. **Cost dashboard is hidden P0**. Daily Spend, monthly compare,
   per-provider share, model breakdown all aggregate cost across
   providers. Without mock cost data there's no way to verify these
   pipelines without a billing-active account on every provider.
4. **Toggle reversibility = trust**. Mock activation must never
   pollute real CKRecords. Real users seeing inflated numbers after
   QA leaves mock on would be a credibility-destroying bug.
5. **iOS visual identification = QA experience**. Beta testers must
   spot mock data instantly so they don't conflate it with real
   spend. Hence MOCK badge + purple accent + top banner + Settings
   Diagnostics row, all gated on the universal `.test` TLD signal.
6. **CI integration = quality gate**. Every PR runs the mock suite;
   any break is blocked at PR time, not at TestFlight time.
7. **Coverage is quantifiable**. The 32-snapshot table is auditable.
   Adding a new provider = one row in `simpleProviderProfiles`. Each
   provider's coverage is visible to reviewers at a glance.

---

## Architecture

### Mac side: `MockProviderInjector`

Single file, single source of truth:
`Sources/CodexBar/Sync/MockProviderInjector.swift`.

**Activation** (any one method, all default OFF):
- Environment variable `CODEXBAR_MOCK_PROVIDERS=1`
- UserDefaults flag `CodexBarMockProvidersEnabled`
- Settings UI: `Settings → Mobile → Debug · Mock Provider Data`
  toggle (Mac 0.23.5+).

**Wire path**: `SyncCoordinator.pushCurrentSnapshot()` calls
`mockInjector()` and appends the result to `providerSnapshots` before
encoding the `SyncedUsageSnapshot` for CloudKit. The default
`mockInjector` closure delegates to
`MockProviderInjector.injectedSnapshots()`, which checks `isEnabled`
and returns mock data if active, empty otherwise.

**Test isolation**: `SyncCoordinator.init` accepts an explicit
`mockInjector: () -> [ProviderUsageSnapshot]` closure (default `{ [] }`)
so tests don't depend on process-global UserDefaults state — preserves
parallel @Suite isolation.

### Mock composition (32 entries / 29 distinct providerIDs)

| Group | Count | Purpose |
|-------|-------|---------|
| Codex multi-account | 3 (Alice / Bob / Carol) | R1 path: per-account cache + identity merge + 3-account first-class rendering |
| Claude multi-account | 2 (Personal / Work) | R2 path: token-based multi-account + 3-lane Sonnet/Opus rendering |
| Perplexity Pro | 1 | 3-segment credit breakdown + Pro plan badge + renewal countdown |
| Simple real-borrowed | 24 | Single-account first-class card for every other real provider (cursor, opencode, opencodego, alibaba, factory, gemini, antigravity, copilot, zai, minimax, kimi, kilo, kiro, vertexai, augment, jetbrains, kimik2, amp, ollama, synthetic, warp, openrouter, abacus, mistral) |
| `_mock_cursor_unknown` | 1 | Fallback path with error state + isError=true + statusMessage |
| `_mock_synthetic_unknown` | 1 | Fallback path with rich data (3 rate windows + 30-day utilization + budget) |
| **Total** | **32** | |

### Mock detection contracts

Two independent signals; either is sufficient:

1. **Email TLD** — every mock account uses `*-mock@*.test`. The
   `.test` TLD is RFC 6761 reserved for testing; real accounts will
   never legally use it. Defined as `MockProviderInjector.mockEmailTLD`
   on Mac, `MockProviderDetector.mockEmailTLD` on iOS.
2. **ProviderID prefix** — synthetic providerIDs are always prefixed
   `_mock_`. Defined as `MockProviderInjector.syntheticProviderIDs` on
   Mac (closed set), `MockProviderDetector.mockProviderIDPrefix` on iOS.

**ORed together** so a future Mac change that drops one signal but
keeps the other still works.

### iOS side: `MockProviderDetector`

`CodexBarMobile/CodexBarMobile/Models/MockProviderDetector.swift`.

Three usage points:

1. **`MockBadgeView`** in card header (provider list + detail page).
2. **`MockProviderBanner`** at top of Usage / Cost tabs.
3. **Settings → Diagnostics row** when mock is active.

`isMock(_:)` and `hasAnyMock(in:)` are the two main entry points.

### Cost data invariants

- 28 of 32 mocks carry `SyncCostSummary` (the 4 cost-less:
  `_mock_cursor_unknown` error state, `_mock_synthetic_unknown`
  budget-only, antigravity preview/no-billing, ollama local).
- Aggregate ~$85/30day across all cost-bearing mocks. Test bound:
  > $50 visible, < $120 not skewing.
- One mock (Codex Alice) carries 30-day daily breakdown with model
  breakdowns so iPhone Cost dashboard's Daily Spend chart + per-day
  selection + model-breakdown pie are testable.

---

## When to add / update a mock

**Adding a new provider** (post-Mac 0.23.5):

1. Add the provider's `case` to `UsageProvider` in
   `Sources/CodexBarCore/Providers/Providers.swift`.
2. Add a row to
   `MockProviderInjector.simpleProviderProfiles` (≤10 lines):
   ```swift
   .init(
       providerID: "newprovider", providerName: "NewProvider",
       accountLocal: "team", loginMethod: "Pro",
       primaryUsage: 35, primaryLabel: "Daily",
       primaryWindowMinutes: 1440,
       primaryResetsInSeconds: 3600 * 12,
       primaryResetDescription: "in 12 hours",
       secondary: nil,
       thirtyDayCostUSD: 1.50, sessionCostUSD: 0.05),
   ```
3. Add `"newprovider"` to
   `MockProviderInjector.realProviderIDsBorrowedByMocks`.
4. Update test counts in `MockProviderInjectorTests.swift` and
   `MockProviderInjectorIntegrationTests.swift` (search for `32 ==`,
   `29 ==`, `28 ==`).
5. PR with the checklist ticked.

**Adding a new error state**:

1. Either modify an existing mock (e.g. set `isError = true` on Bob)
   OR add a new fallback mock with synthetic providerID
   `_mock_<state>_<unique>`.
2. Test in `MockProviderAdvancedScenariosTests.swift`.

**Adding a new aggregate cost behavior**:

1. Bump per-provider cost in `simpleProviderProfiles`.
2. Verify aggregate stays within `MR6.2` bounds (`$50 < total < $120`).
3. Test in `MockProviderInjectorIntegrationTests.swift` MR6.x suite.

---

## Quality gates

- **PR template** (`.github/PULL_REQUEST_TEMPLATE.md`) — required
  checklist items including "mock data covers this change".
- **CI** (`.github/workflows/ci.yml`) — `swift test --no-parallel`
  runs the entire mock suite on every push and PR. Failure blocks merge.
- **Lint** (`./Scripts/lint.sh lint`) — keeps the file under the
  swiftlint thresholds; `parser-version audit` keeps cost cache
  invalidation in sync with parser changes.
- **Local** — `swift test --filter "MockProviderInjector"` runs
  ≥67 mock-specific tests in <1 second; ideal pre-commit.

---

## What this is NOT

- **Not** a fixture for unit tests. The Mac project has separate
  per-suite fixtures for unit tests; mock providers are end-to-end,
  exercising the entire CKRecord → iOS render pipeline.
- **Not** for production debugging on real users' devices. Mock
  activation is opt-in; no telemetry collects mock state. The toggle
  is exposed in Settings but defaults OFF for everyone.
- **Not** a replacement for real-account testing. Real Codex / Claude
  accounts catch issues mocks can't (real CloudKit network, real
  account-switch races, real token-refresh edge cases). Mocks cover
  the 99% — real accounts catch the 1%.
- **Not** versioned independently. Mock layer evolves alongside the
  CKRecord schema; bump matters only when the underlying
  `ProviderUsageSnapshot` shape changes (which is gated by separate
  schema-version migration).

---

## Future extensions (post-1.5.2)

| Item | Priority | Effort |
|------|----------|--------|
| iOS Snapshot Testing for mock cards | P3 | 1 day (needs SnapshotTesting library) |
| `mocks.json` config file (drop Swift literals) | P4 | 1 day |
| Coverage dashboard auto-generated in CHANGELOG | P4 | 4 hours |
| Mock time-travel (override `nowReference`) for testing date math | P3 | 4 hours |
| Mock CKRecord round-trip integration test (writeable mock CloudKit) | P3 | 1-2 days |

These are not blockers; the current 32-mock + detector + visual
treatment infrastructure is the core that everything else builds on.
