# 013 · iOS 1.3.0 · T3 · Perplexity 详情页 3 段式信用展示 — 调研

- Status: `ready`
- Date: 2026-04-21
- Author: Architect (Claude)
- Parent plan: 1.3.0 refactor (`refactor-1.3.0` branch), follow-up to T1 (QuotaProviderList append) already shipped in Build 69.
- Todoist: _to be created by Release Engineer at commit time_

## Summary

Upstream CodexBar 0.20 added Perplexity as a first-class provider on Mac. Its backend actually exposes **three distinct credit pools** — monthly recurring, promotional/bonus, on-demand purchased — plus a plan (Pro/Max) inferred from recurring quota, and a renewal date. Today iOS collapses all of that into a generic three-bar `UsageCardView` list rendered in fallback blue. T3 builds a native `PerplexityCreditSummary` Codable value on the shared sync layer, pushes it from Mac via `SyncCoordinator`, and renders a **stacked 3-segment progress bar + Pro/Max badge + renewal countdown** on the iOS `ProviderDetailView` when `providerID == "perplexity"`. Old Macs / old iOS clients degrade to the existing generic rendering.

## Current state (before T3)

### Mac side · where the rich data lives and where it is lost

The Mac provider parses the rich Perplexity API response into a value type:

- `Sources/CodexBarCore/Providers/Perplexity/PerplexityModels.swift` — the raw API response (`PerplexityCreditsResponse` + `PerplexityCreditGrant`, snake_case keys).
- `Sources/CodexBarCore/Providers/Perplexity/PerplexityUsageSnapshot.swift` — the processed snapshot. Real fields:

```swift
public struct PerplexityUsageSnapshot: Sendable {
    public let recurringTotal: Double    // cents, raw units the API returns
    public let recurringUsed: Double     // cents
    public let promoTotal: Double        // cents
    public let promoUsed: Double         // cents
    public let purchasedTotal: Double    // cents
    public let purchasedUsed: Double     // cents
    public let balanceCents: Double      // response.balanceCents passthrough
    public let totalUsageCents: Double   // response.totalUsageCents passthrough
    public let renewalDate: Date         // non-optional (always produced, seeded from renewal_date_ts)
    public let promoExpiration: Date?    // min expires_at_ts across still-valid promo grants
    public let updatedAt: Date
}
```

Plus a derived `planName: String?` computed property (`nil` → free, `< 5000` recurring cents → `"Pro"`, else `"Max"`) and a `toUsageSnapshot()` extension at `PerplexityUsageSnapshot.swift:69–133` that collapses everything into the **generic** `UsageSnapshot` shape:

- `primary` RateWindow → recurring pool with `resetsAt = renewalDate`, `resetDescription = "{used}/{total} credits"`
- `secondary` RateWindow → promo pool with `resetDescription = "{used}/{total} bonus · exp. {MMM d}"`
- `tertiary` RateWindow → purchased pool with `resetDescription = "{used}/{total} credits"`
- `identity.loginMethod = planName` (i.e. `"Pro"` or `"Max"` leaks through as the login-method label)

Importantly, the three pools' totals/used values and `promoExpiration` / `renewalDate` / `balanceCents` are **lost as soon as `toUsageSnapshot()` runs** — the caller in `PerplexityProviderDescriptor.swift:105–110` only keeps the resulting `UsageSnapshot`, and that's what lands in `UsageStore.snapshots[.perplexity]`. There is NO place on Mac today that keeps the structured `PerplexityUsageSnapshot` alive beyond the fetch call.

The descriptor also sets labels that the generic pipeline uses: `sessionLabel: "Credits"`, `weeklyLabel: "Bonus credits"`, `opusLabel: "Purchased"`, `supportsOpus: true` (`PerplexityProviderDescriptor.swift:13–16`). Brand color is teal `rgb(32, 178, 170)` at line 31.

### Shared / Sync contract · the wire format

`Shared/Models/UsageSnapshot.swift` defines what travels over iCloud. Relevant types:

- `SyncRateWindow` (`label`, `usedPercent`, `windowMinutes?`, `resetsAt?`, `resetDescription?`) — one per metric.
- `SyncBudgetSnapshot` (`usedAmount`, `limitAmount`, `currencyCode`, `period?`, `resetsAt?`) — currently used by Warp, not Perplexity.
- `SyncCostSummary` + `SyncDailyPoint` — cost graphs (Perplexity doesn't populate these because `tokenCost.supportsTokenCost = false`).
- `SyncUtilizationSeries` + `SyncUtilizationEntry` — historical utilization chart.
- `ProviderUsageSnapshot` — the wrapper. Has `primary/secondary` (legacy), `rateWindows: [SyncRateWindow]` (dynamic), `accountEmail`, `loginMethod`, `statusMessage`, `isError`, `lastUpdated`, `costSummary?`, `budget?`, `utilizationHistory?`.

All Codable, all iCloud-encoded through `CloudSyncConstants.makeJSONEncoder/Decoder()` (ISO8601 dates — **mandatory**; `JSONCodecConsistencyTests` pins this invariant; `Shared/iCloud/CloudConstants.swift:47–60`). `ProviderUsageSnapshot.init(from:)` already uses `decodeIfPresent` for every optional child, so adding another optional field is fully backward-compatible at decode time.

`ProviderUsageSnapshot` is synced into per-provider CKRecord envelopes (`Shared/Models/ProviderUsageEnvelope.swift`) plus the legacy monolithic `SyncedUsageSnapshot`, then mirrored into SwiftData on iOS via `SwiftDataBridge.swift` which stores `allRateWindows`, `costSummary`, `budget` as opaque encoded `Data` blobs on `ProviderSnapshotModel`.

### Mac Sync Coordinator

`Sources/CodexBar/Sync/SyncCoordinator.swift:89–163` builds one `ProviderUsageSnapshot` per enabled provider. For Perplexity today it reads `store.snapshots[.perplexity]` — which is the already-lossy generic `UsageSnapshot` — and packs three `SyncRateWindow`s in `rateWindows`, labeled by `ProviderMetadata.sessionLabel / weeklyLabel / opusLabel`. This is the only place Perplexity data flows out of the Mac.

### iOS side · current rendering

`CodexBarMobile/CodexBarMobile/Views/ProviderDetailView.swift`:

- `rateLimitSection` (line 54) iterates `provider.allRateWindows` and renders one `UsageCardView` per entry. For Perplexity today: 3 cards labeled "Credits" / "Bonus credits" / "Purchased", each a standalone bar in fallback **blue** (because `providerColor` at line 204–217 has no branch for Perplexity — it falls through to `.blue`).
- No Pro/Max badge, no renewal countdown beyond the generic `resetsAt` "Resets in N days" text inside `UsageCardView`.
- `BudgetProgressView`, `UtilizationHistoryView`, daily-spend chart are all skipped for Perplexity (provider doesn't populate `budget`, `utilizationHistory`, `costSummary`).

Reusable components inventory:

- `UsageCardView` (`Views/UsageCardView.swift`) — single rate-window card. Already has color ramp red/orange/tint at 70/90 thresholds. We'll reuse its visual vocabulary.
- `BudgetProgressView` (`Views/BudgetProgressView.swift`) — reference for "card with header + progress + footer" layout + `.ultraThinMaterial` background + `RoundedRectangle(cornerRadius: 14)`.
- Mobile color helper: none central — every view re-inlines `providerColor`. OK to do the same.

## Design

### Shared model extension · `PerplexityCreditSummary`

Add a new Codable value type in `Shared/Models/UsageSnapshot.swift` (right after `SyncUtilizationSeries` and before `ProviderUsageSnapshot`, so the file stays grouped by "payload types, then wrapper"). Every field optional — we must gracefully degrade if the Mac build is older, if a pool is empty (free tier), or if the API shape changes.

```swift
/// Perplexity-specific credit breakdown for iOS provider detail rendering.
/// All fields optional so old Mac payloads (pre-0.20.3) and unusual account
/// shapes (free-tier with no recurring pool, no promo, etc.) degrade silently.
/// Amounts are in **cents** (raw units from Perplexity API) to match the
/// upstream `PerplexityUsageSnapshot`; iOS formats for display.
public struct SyncPerplexityCreditSummary: Codable, Sendable, Equatable {
    /// Monthly recurring plan credits (Pro/Max entitlement).
    public let recurringTotalCents: Double?
    public let recurringUsedCents: Double?
    /// Promotional / bonus credits (time-limited).
    public let promoTotalCents: Double?
    public let promoUsedCents: Double?
    public let promoExpiresAt: Date?
    /// On-demand purchased credits (no expiration).
    public let purchasedTotalCents: Double?
    public let purchasedUsedCents: Double?
    /// Next recurring renewal (nil when free tier or when Mac hasn't parsed it).
    public let renewalAt: Date?
    /// Inferred plan name from `PerplexityUsageSnapshot.planName`: `"Pro"`, `"Max"`, or nil (free).
    public let planName: String?
    /// `response.balance_cents` — account balance passthrough (rarely shown but kept for parity).
    public let balanceCents: Double?

    public init(
        recurringTotalCents: Double?,
        recurringUsedCents: Double?,
        promoTotalCents: Double?,
        promoUsedCents: Double?,
        promoExpiresAt: Date?,
        purchasedTotalCents: Double?,
        purchasedUsedCents: Double?,
        renewalAt: Date?,
        planName: String?,
        balanceCents: Double?)
    {
        self.recurringTotalCents = recurringTotalCents
        self.recurringUsedCents = recurringUsedCents
        self.promoTotalCents = promoTotalCents
        self.promoUsedCents = promoUsedCents
        self.promoExpiresAt = promoExpiresAt
        self.purchasedTotalCents = purchasedTotalCents
        self.purchasedUsedCents = purchasedUsedCents
        self.renewalAt = renewalAt
        self.planName = planName
        self.balanceCents = balanceCents
    }

    // Auto-synthesized Codable is fine: all Optionals, no custom keys.
    // JSONDecoder (`.decodeIfPresent` semantics for Optional) handles missing
    // keys automatically; the encoder (.iso8601 dates) handles `promoExpiresAt`
    // and `renewalAt`. `Equatable` auto-synthesized from all-stored-property
    // equality — used by `ProviderUsageSnapshot`'s content-hash diff.
}
```

Then extend `ProviderUsageSnapshot` with a new optional property. Two mechanical edits:

```swift
// add to the stored property block (alongside utilizationHistory):
public let perplexityCredits: SyncPerplexityCreditSummary?

// extend the public init (append with default nil — callers stay source-compatible):
public init(
    ...
    utilizationHistory: [SyncUtilizationSeries]? = nil,
    perplexityCredits: SyncPerplexityCreditSummary? = nil)
{
    ...
    self.utilizationHistory = utilizationHistory
    self.perplexityCredits = perplexityCredits
}

// extend the custom decoder (backward-compat · Mac 0.20.2 won't ship this key):
self.perplexityCredits = try container.decodeIfPresent(
    SyncPerplexityCreditSummary.self, forKey: .perplexityCredits)
```

And add the key to the (currently auto-synthesized) `CodingKeys`. Swift auto-synthesizes `CodingKeys` when the custom `init(from:)` only refers to `container.decodeIfPresent(..., forKey: .foo)` for every property — but since `ProviderUsageSnapshot` already has a custom `init(from:)` without a spelled-out `CodingKeys`, it's relying on auto-synthesis. Check at implementation time: if auto-synthesis works, we don't need to add `CodingKeys`; if not (e.g. if Swift complains about a missing case), add an explicit enum. **TODO: confirm `ProviderUsageSnapshot` still auto-synthesizes `CodingKeys` after we add the new stored property; if it does not, spell out the enum explicitly matching the existing `CodingKeys` that `init(from:)` implicitly uses.**

Codable strategy notes:

- Dates (`promoExpiresAt`, `renewalAt`) piggyback on `CloudSyncConstants.makeJSONEncoder/Decoder()`'s `.iso8601` — no per-type override needed. Round-trip guaranteed by the factory contract tested in `JSONCodecConsistencyTests`.
- Amounts are `Double` cents (not `Int`) to match upstream `PerplexityUsageSnapshot` which already uses `Double` for every `*Total` / `*Used`.
- Optionals everywhere: if a pool doesn't exist, both `...TotalCents` and `...UsedCents` should be nil (not 0), so the renderer can distinguish "no pool" from "empty pool".

### Mac mapping

Two-step plumbing — rich snapshot has to survive longer than it does today, then get read by `SyncCoordinator`. Recommended approach: add a new optional parallel dictionary on `UsageStore` (the existing `openRouterUsage`/`zaiUsage`-on-`UsageSnapshot` pattern won't work cleanly here because `UsageSnapshot`'s custom decoder explicitly drops non-persisted fields, and the Mac-side `UsageSnapshot` is *not* the shared `ProviderUsageSnapshot` we're syncing).

Minimal footprint:

1. **Preserve the rich snapshot on Mac at fetch time.**

   Keep a new `@MainActor` property on `UsageStore`:

   ```swift
   // Sources/CodexBar/UsageStore.swift (same storage group as `snapshots`)
   var perplexityCreditSnapshot: PerplexityUsageSnapshot?
   ```

   In `PerplexityProviderDescriptor.fetch()` (Sources/CodexBarCore/Providers/Perplexity/PerplexityProviderDescriptor.swift:96) the `PerplexityUsageSnapshot` is already in scope before `.toUsageSnapshot()` is called. But `ProviderFetchResult` is the bottleneck — the extended rich snapshot has to travel through it back to `UsageStore`.

   Cleanest path: piggyback on `ProviderRuntime.providerDidRefresh` (already wired in `UsageStore+Refresh.swift:108–112`). Add a `perplexityDidRefresh(snapshot:)` hook on a new `PerplexityProviderRuntime` in `Sources/CodexBar/Providers/Perplexity/`, or — simpler — stash the rich snapshot inside the `UsageSnapshot` via the existing `zaiUsage`-style escape hatch on Mac-local `UsageSnapshot`:

   ```swift
   // Sources/CodexBarCore/UsageFetcher.swift (Mac internal; NOT the shared one)
   public let perplexityUsage: PerplexityUsageSnapshot?
   ```

   Both options work. **Recommended: the `perplexityUsage` on `UsageSnapshot`** — matches `zaiUsage` / `minimaxUsage` precedent, no new runtime class, no new plumbing. The Mac-side `UsageSnapshot` is a different type from the shared `ProviderUsageSnapshot` (see `Sources/CodexBarCore/UsageFetcher.swift:50` vs `Shared/Models/UsageSnapshot.swift:157`), so the decoder at line 105 drops it to `nil` when loaded from disk — which is fine, Perplexity snapshots are fetched fresh each cycle anyway.

2. **Map to shared struct in `SyncCoordinator`.**

   At `Sources/CodexBar/Sync/SyncCoordinator.swift:148` (the `ProviderUsageSnapshot(...)` call), add:

   ```swift
   // Map Perplexity-specific structured data.
   // Mac 0.20.2 and older don't populate this (struct is brand new) — iOS falls
   // back to generic rateWindows rendering. Safe to always set from snapshot,
   // stays nil for every other provider.
   let perplexityCredits: SyncPerplexityCreditSummary? = {
       guard provider == .perplexity, let p = snapshot?.perplexityUsage else { return nil }
       return SyncPerplexityCreditSummary(
           recurringTotalCents: p.recurringTotal > 0 ? p.recurringTotal : nil,
           recurringUsedCents: p.recurringTotal > 0 ? p.recurringUsed : nil,
           promoTotalCents: p.promoTotal > 0 ? p.promoTotal : nil,
           promoUsedCents: p.promoTotal > 0 ? p.promoUsed : nil,
           promoExpiresAt: p.promoExpiration,
           purchasedTotalCents: p.purchasedTotal > 0 ? p.purchasedTotal : nil,
           purchasedUsedCents: p.purchasedTotal > 0 ? p.purchasedUsed : nil,
           renewalAt: p.renewalDate,
           planName: p.planName,
           balanceCents: p.balanceCents)
   }()
   ```

   Pass `perplexityCredits: perplexityCredits` to the `ProviderUsageSnapshot` initializer.

   Rationale for the `> 0 ? _ : nil` pattern: upstream zero-valued pools still encode as Double zero, but on iOS we want the renderer to hide an empty pool entirely (e.g. free-tier user with no recurring). Nil is clearer than zero for that distinction.

### iOS rendering

Swap in a Perplexity-specialized section **above** the generic `rateLimitSection` when both `providerID == "perplexity"` and `perplexityCredits != nil`. When the field is missing (old Mac), fall back to the existing generic rendering (3 blue cards) — no behavior change for 1.2.0-era data.

File: `CodexBarMobile/CodexBarMobile/Views/ProviderDetailView.swift`.

New computed view (sketch):

```swift
@ViewBuilder
private var perplexitySection: some View {
    if self.provider.providerID == "perplexity",
       let credits = self.provider.perplexityCredits
    {
        PerplexityCreditsCard(
            credits: credits,
            tintColor: self.providerColor)
    } else {
        // Fall back to the existing generic 3-card stack
        self.rateLimitSection
    }
}
```

Then `body` calls `self.perplexitySection` instead of `self.rateLimitSection`.

New component file: `CodexBarMobile/CodexBarMobile/Views/PerplexityCreditsCard.swift` (one new file — keeps `ProviderDetailView.swift` focused and mirrors the per-feature file layout in `Views/`). Structure:

```swift
struct PerplexityCreditsCard: View {
    let credits: SyncPerplexityCreditSummary
    var tintColor: Color = .teal  // rgb(32, 178, 170) to match Mac branding

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: "Perplexity Credits" + Pro/Max badge + renewal countdown
            header

            // Stacked 3-segment bar (or single-metric fallback)
            stackedBar

            // Per-pool legend rows: recurring / promo / purchased with used-of-total
            legend
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Header
    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Credits")
                .font(.subheadline).fontWeight(.semibold)
            if let plan = credits.planName {
                Text(plan)  // "Pro" or "Max"
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(tintColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(tintColor)
            }
            Spacer()
            if let renewal = credits.renewalAt {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                    Text(renewal, format: .relative(presentation: .named))
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Stacked bar
    // Geometry: pool widths are proportional to `*TotalCents`. Used portion
    // fills with `tintColor`, remaining with `tintColor.opacity(0.18)`.
    // When only one pool is non-nil, renders as a single segment (still works).
    private var stackedBar: some View {
        GeometryReader { geo in
            let totalCents = (credits.recurringTotalCents ?? 0)
                           + (credits.promoTotalCents ?? 0)
                           + (credits.purchasedTotalCents ?? 0)
            let safeTotal = max(totalCents, 1)  // avoid /0 on free tier
            HStack(spacing: 2) {
                ForEach(pools, id: \.kind) { pool in
                    let share = pool.total / safeTotal
                    let width = geo.size.width * share
                    ZStack(alignment: .leading) {
                        Capsule().fill(tintColor.opacity(0.18))
                        Capsule()
                            .fill(tintColor)
                            .frame(width: width * (pool.usedFraction))
                    }
                    .frame(width: width)
                }
            }
        }
        .frame(height: 10)
    }

    private struct PoolSegment: Identifiable {
        let kind: String  // "recurring" / "promo" / "purchased"
        let total: Double
        let used: Double
        var usedFraction: Double { total > 0 ? min(1, used / total) : 0 }
        var id: String { kind }
    }

    private var pools: [PoolSegment] {
        var out: [PoolSegment] = []
        if let t = credits.recurringTotalCents, t > 0 {
            out.append(.init(kind: "recurring", total: t, used: credits.recurringUsedCents ?? 0))
        }
        if let t = credits.promoTotalCents, t > 0 {
            out.append(.init(kind: "promo", total: t, used: credits.promoUsedCents ?? 0))
        }
        if let t = credits.purchasedTotalCents, t > 0 {
            out.append(.init(kind: "purchased", total: t, used: credits.purchasedUsedCents ?? 0))
        }
        return out
    }

    // MARK: Legend
    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pools) { pool in
                HStack {
                    Circle().fill(tintColor.opacity(pool.kind == "purchased" ? 0.55 : pool.kind == "promo" ? 0.78 : 1)).frame(width: 8, height: 8)
                    Text(Self.poolLabel(pool.kind))
                        .font(.caption)
                    Spacer()
                    Text(Self.formatCreditsUsed(pool.used, pool.total))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if pool.kind == "promo", let exp = credits.promoExpiresAt {
                        Text("·")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("exp. \(exp, format: .dateTime.month(.abbreviated).day())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static func poolLabel(_ kind: String) -> String {
        switch kind {
        case "recurring": String(localized: "Monthly credits")
        case "promo":     String(localized: "Bonus credits")
        case "purchased": String(localized: "Purchased credits")
        default:          kind
        }
    }

    /// Cents → human-readable credit count (`12,345 / 50,000`). Perplexity's
    /// API uses cents as internal units — we display the raw integer since
    /// users think in "credits" not dollars.
    static func formatCreditsUsed(_ used: Double, _ total: Double) -> String {
        let u = Int(used.rounded())
        let t = Int(total.rounded())
        return "\(u.formatted(.number)) / \(t.formatted(.number))"
    }
}
```

Also add a color branch for Perplexity in `providerColor` (`ProviderDetailView.swift:204`):

```swift
} else if id.contains("perplexity") {
    return Color(red: 32/255, green: 178/255, blue: 170/255)  // teal, matches Mac
}
```

Same branch should be added in:
- `ProviderUsageView.swift:109` (list row tint)
- `ContentView.swift:959` (any overview tints — spot-check)

Adding to `CostShareService.swift:273` is optional — Perplexity doesn't contribute cost data, so the share-card provider color fallback rarely surfaces. Still worth a one-line add for consistency.

Localization: new strings go in `Localizable.xcstrings`:
- `"Monthly credits"`, `"Bonus credits"`, `"Purchased credits"` (if not already there — `"Bonus credits"` may already exist from the generic label pipeline; check before duplicating).
- `"Resets {relative}"` is already localized.

Preview data: add a `PreviewData.perplexityProvider` in `PreviewData.swift` with a populated `SyncPerplexityCreditSummary` (e.g. Pro plan: 2,500/5,000 recurring + 1,000/5,000 promo + 0/10,000 purchased) for the SwiftUI preview.

## Backward-compat matrix

| Mac version | iOS version | Result |
|---|---|---|
| 0.20.2 (current release, no `perplexityCredits` field) | 1.2.0 (current release) | Works. Mac writes `rateWindows` only; iOS ignores unknown keys (it's already the case — there are none). 3 generic blue cards. |
| 0.20.2 | 1.3.0 (this release) | `perplexityCredits` is `nil` in decoded snapshot → `perplexitySection` falls through to `rateLimitSection` → 3 generic blue cards (but now teal if we also add the teal color branch — that's a pure-iOS cosmetic upgrade that ships unconditionally). |
| 0.20.3+ (new, writes `perplexityCredits`) | 1.2.0 | Works. `ProviderUsageSnapshot`'s old decoder path (1.2.0) already `decodeIfPresent`s every field and IGNORES unknown keys — auto-synthesized Codable behavior confirmed by spot-check in `UsageSnapshot.swift:211–226`. 1.2.0 renders the legacy 3 blue cards. |
| 0.20.3+ | 1.3.0 | **Full experience** — stacked 3-segment bar, Pro/Max badge, renewal countdown. |

Critical safety check — the compressed envelope pipeline: `envelopeCompressionRoundTrip` in `JSONCodecConsistencyTests.swift:171` already covers the full encode → zlib → decompress → decode path for `ProviderUsageEnvelope`. Our new field rides the same envelope, so as long as we add a round-trip test (below) and keep `perplexityCredits` on `ProviderUsageSnapshot`, compression-path compat is free.

SwiftData mirror on iOS (`SwiftDataBridge.swift:141–198`): does **not** currently persist `perplexityCredits`. Options:

1. **Don't persist.** On cold start iOS reads legacy rate windows from SwiftData, then the live CloudKit fetch repopulates `perplexityCredits` within seconds. Tradeoff: brief flash of "generic bars → teal stacked bar" on launch before CloudKit fetch returns.
2. **Persist.** Add `perplexityCreditsData: Data?` to `ProviderSnapshotModel`, encode on upsert at line 162 and decode at line 290. Zero data-loss on cold start.

**Recommended: option 2.** The refactor-1.3.0 branch has already invested heavily in SwiftData fidelity (Build 67/68 hardening), and a brief flicker on cold start regresses the "instant cold-start" goal documented in `SwiftDataBridge.readAllDeviceSnapshots` (line 262–267). Encode on write (2 lines), decode on read (3 lines), pass through to `ProviderUsageSnapshot.init`. The new field joins `costSummaryData` / `budgetData` as a peer.

## Required Mac update — YES

T3 cannot be shipped to end-users without a matching Mac release. **Mac needs a `0.20.3` bump** that:

1. Adds `perplexityUsage: PerplexityUsageSnapshot?` to Mac-local `UsageSnapshot` + populates it in `PerplexityWebFetchStrategy.fetch` (`PerplexityProviderDescriptor.swift:96–123`).
2. Maps it in `SyncCoordinator` as above.

Release sequencing implication:

- iOS 1.3.0 (Build 70+) can ship **before** Mac 0.20.3 — the field is optional everywhere, the generic fallback still renders. T3 just stays invisible in production until Mac 0.20.3 rolls out.
- Mac 0.20.3 must be shipped from `upstream` (steipete/CodexBar) or via a patch fork. Since **the rule is: we don't modify Mac-only files without explicit request** (per CLAUDE.md), the Mac 0.20.3 bump needs explicit user approval before we do the Mac-side `Sources/…` edits. Flag this loudly in the Developer handoff.
- Alternative: iOS-only shallow version of T3 that renders the Perplexity card using whatever *is* already in `rateWindows` today — i.e. parse the existing `resetDescription` strings ("12345/50000 credits") back out into three pools. This is fragile (format-dependent) and explicitly not what the task asked for; including here for completeness.

## Unit test plan

Add to `Tests/CodexBarTests/JSONCodecConsistencyTests.swift` (Mac-side, this is the pin for the wire format — iOS uses the same shared module so covers both):

1. **`syncPerplexityCreditSummaryRoundTripFullyPopulated`** — encode a `SyncPerplexityCreditSummary` with every field non-nil (including both `Date` fields), round-trip through the factory codecs, `#expect` equality. Pins the ISO8601 pairing for our two new `Date` fields (the Build 66 bug shape).
2. **`syncPerplexityCreditSummaryRoundTripAllNil`** — every field nil (free-tier edge case). Ensures the encoder doesn't emit `null` for missing optionals in a way that breaks the decoder.
3. **`providerUsageSnapshotWithPerplexityCreditsRoundTrip`** — full `ProviderUsageSnapshot` with `providerID: "perplexity"` + populated `perplexityCredits`. Round-trip check that `decoded.perplexityCredits?.renewalAt == original.perplexityCredits?.renewalAt` (the Date field most likely to silently drop on encoder drift).
4. **`providerUsageSnapshotBackwardCompatDecodesWithoutPerplexityCredits`** — hand-roll a JSON blob matching what Mac 0.20.2 produces (no `perplexityCredits` key at all), decode with the new factory decoder, `#expect(decoded.perplexityCredits == nil)`. Proves the backward-compat matrix row for "old Mac → new iOS".
5. **Envelope compression round-trip with `perplexityCredits` populated** — extend `envelopeCompressionRoundTrip` to also populate `perplexityCredits` on the inner provider, assert it survives the zlib pipeline. Matches the pattern already established at line 172.

Optional: add a SwiftData bridge test in `CodexBarMobile/CodexBarMobileTests/Storage/SwiftDataBridgeTests.swift` that upserts a `ProviderUsageSnapshot` with `perplexityCredits` set, round-trips via `readAllDeviceSnapshots`, asserts the field survives. Only needed if we go with SwiftData-persistence option 2 above (recommended).

## Files touched

| File | Operation | Notes |
|---|---|---|
| `Shared/Models/UsageSnapshot.swift` | add `SyncPerplexityCreditSummary` struct; add `perplexityCredits: SyncPerplexityCreditSummary?` to `ProviderUsageSnapshot` + init + decoder | Shared — **iOS + Mac both depend on this** |
| `Sources/CodexBarCore/UsageFetcher.swift` | add `perplexityUsage: PerplexityUsageSnapshot?` on Mac-local `UsageSnapshot` (escape-hatch pattern, mirrors `zaiUsage`) | Mac only — touches Mac files so **needs explicit user approval** |
| `Sources/CodexBarCore/Providers/Perplexity/PerplexityUsageSnapshot.swift` | update `toUsageSnapshot()` to pass `perplexityUsage: self` through | Mac only |
| `Sources/CodexBar/Sync/SyncCoordinator.swift` | map `snapshot?.perplexityUsage` to `SyncPerplexityCreditSummary` at the `ProviderUsageSnapshot(...)` call site (~line 148) | Mac only |
| `CodexBarMobile/CodexBarMobile/Views/ProviderDetailView.swift` | add `perplexitySection`; switch `body` to use it; add `perplexity` branch in `providerColor` | iOS |
| `CodexBarMobile/CodexBarMobile/Views/PerplexityCreditsCard.swift` | new file — stacked-bar card component | iOS |
| `CodexBarMobile/CodexBarMobile/Views/ProviderUsageView.swift` | add Perplexity teal tint branch (consistency) | iOS |
| `CodexBarMobile/CodexBarMobile/ContentView.swift` | spot-check and add Perplexity teal at line ~959 if present | iOS |
| `CodexBarMobile/CodexBarMobile/Storage/SwiftDataSchema.swift` | add `perplexityCreditsData: Data?` on `ProviderSnapshotModel` (option 2) | iOS |
| `CodexBarMobile/CodexBarMobile/Storage/SwiftDataBridge.swift` | encode/decode the new blob in `upsertProvider` + `readAllDeviceSnapshots` | iOS |
| `CodexBarMobile/CodexBarMobile/Preview Content/PreviewData.swift` | add `perplexityProvider` fixture | iOS |
| `CodexBarMobile/CodexBarMobile/Localizable.xcstrings` | 3–4 new strings × 4 locales (en/zh-Hans/zh-Hant/ja) | iOS |
| `Tests/CodexBarTests/JSONCodecConsistencyTests.swift` | 4–5 new `@Test` cases (see plan) | Shared-ish (Mac test target, covers shared model) |
| `CodexBarMobile/CodexBarMobileTests/Storage/SwiftDataBridgeTests.swift` | optional — add SwiftData round-trip | iOS, conditional on option 2 |
| `CodexBarMobile/CHANGELOG.md` | add entry under 1.3.0 | iOS |
| `CodexBarMobile/project.yml` | bump `CURRENT_PROJECT_VERSION` (per discipline rule: every install bumps) | iOS |
| `CodexBarMobile/Research/013-perplexity-detail.md` | this doc | — |

## Effort estimate

- **Research (done):** ~1h (this document).
- **Implementation (iOS-only slice, if Mac 0.20.3 is deferred):** ~2h — Shared struct + decoder tweak + iOS view + color branch + SwiftData passthrough + previews + strings. No end-user visible change until Mac catches up.
- **Implementation (Mac 0.20.3 changes):** ~1h — add `perplexityUsage` to Mac `UsageSnapshot`, thread through `toUsageSnapshot()`, map in `SyncCoordinator`. Plus ~30min to run Mac tests, bump Mac version, archive.
- **Testing:** ~1h — 4–5 new codec round-trip tests + 1 SwiftData bridge test + SwiftUI preview visual QA.
- **Manual QA (real data):** ~30min — side-by-side with `https://www.perplexity.ai/account/usage` in browser, verify recurring/promo/purchased numbers match; verify renewal countdown accuracy on a Pro account.

**Total:** ~5h all-in.

## Risks / open questions

1. **Mac-side changes require explicit user approval.** CLAUDE.md is emphatic: "we only work on the iOS app" and "Mac-side code is maintained upstream — do not modify Mac-only files unless explicitly asked." T3 is half iOS, half Mac — the iOS half is safe, the Mac half needs a go/no-go from the user. The research doc recommends bundling the Mac-side change as part of T3 because without it the iOS UI never surfaces; Developer should not assume approval.

2. **Perplexity API unit ambiguity.** `balance_cents` and `amount_cents` both exist in the API. Upstream `PerplexityUsageSnapshot` treats them all as raw `Double` "cents" — but the UI formatter at `toUsageSnapshot()` line 80 displays `Int(recurringUsed.rounded())/Int(recurringTotal)` directly as "credits", which suggests Perplexity's internal unit is "1 credit == 1 cent" (not dollars). Confirm by cross-referencing a real account: a Pro user should have ≈ 5,000 monthly credits, displayed as "5000 credits" not "$50.00". If that's off, our legend formatter needs a unit conversion. **TODO: confirm Perplexity credit unit with a real Pro account; upstream `PerplexityUsageSnapshot.swift:20–23` appears to treat `amount_cents` as the raw credit count with no USD conversion, so sticking to `"{used} / {total}"` (no currency symbol) is the safe default.**

3. **CodingKeys synthesis on `ProviderUsageSnapshot`.** The type has a custom `init(from:)` that uses `.forKey: .providerID` etc. — it's relying on Swift's auto-synthesized `CodingKeys`. If auto-synthesis silently breaks when we add `perplexityCredits`, the whole type fails to decode. Mitigate by running the JSONCodec tests immediately after adding the property. If it breaks, spell the enum out explicitly — 1-minute fix, but don't skip the test run.

4. **SwiftData schema migration.** Adding `perplexityCreditsData: Data?` to `ProviderSnapshotModel` is a schema change. SwiftData lightweight migration handles adding optional attributes automatically, but the project has NOT enabled explicit migrations yet. Verify before merging that a cold launch on a device with the 1.3.0 Build 69 SwiftData store correctly opens with the extended schema. **TODO: run on a pre-loaded test device — if SwiftData refuses the schema change, we may need `Schema(versionedSchema:)` + a migration plan (overhead: ~2h).**

5. **Pro/Max inference drift.** `PerplexityUsageSnapshot.planName` uses a magic `< 5000` cents threshold to distinguish Pro from Max. If Perplexity changes their pricing (e.g. adds a new plan or shifts Pro to 7,500 credits), the badge will mis-label. Low-impact (badge reverts to nil on edge cases and the user sees the raw pool numbers anyway), but worth noting. No action needed for T3.

6. **Localization consistency with `weeklyLabel: "Bonus credits"` / `opusLabel: "Purchased"`.** If we ship our own `"Bonus credits"` / `"Purchased credits"` in `Localizable.xcstrings`, we're duplicating strings that may also get localized upstream. Prefer labels slightly different from the upstream metadata ("Monthly credits" instead of "Credits", "Purchased credits" instead of "Purchased") so it's obvious which translation path wins. The legacy fallback (old Mac) still shows the upstream English labels via `rateWindows.label` — fine, tolerable stale label.
