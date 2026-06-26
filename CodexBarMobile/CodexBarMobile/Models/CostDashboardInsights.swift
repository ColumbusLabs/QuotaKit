import CodexBarSync
import Foundation
import SwiftUI

struct CostDashboardInsights {
    struct ProviderRow: Identifiable {
        let provider: ProviderUsageSnapshot
        let thirtyDayCost: Double
        let todayCost: Double
        let thirtyDayTokens: Int

        /// Composite key (providerID|accountEmail) so multi-account rows
        /// with the same providerID don't collapse in SwiftUI ForEach.
        /// Hit on user QA 2026-05-04 — see RawSyncDataView fix in same commit.
        var id: String {
            self.provider.cardIdentityKey
        }
    }

    struct DailyPoint: Identifiable {
        let dayKey: String
        let date: Date
        let costUSD: Double
        let totalTokens: Int

        var id: String {
            self.dayKey
        }
    }

    let providerRows: [ProviderRow]
    let dailyPoints: [DailyPoint]
    let modelRows: [CostBreakdownRow]
    let serviceRows: [CostBreakdownRow]
    let budgetRows: [CostBudgetRow]
    /// When CWL is ON, the user-selected window (7/30/90/365) the ledger was
    /// re-aggregated to. nil on the blob path. Drives `historyDays` so the
    /// Overview "N Days" headline reflects the chosen CWL window instead of the
    /// max Mac `historyDays` across providers (e.g. a 90-day mock provider).
    let cwlWindowDays: Int?

    var total30DayCost: Double {
        self.providerRows.reduce(0) { $0 + $1.thirtyDayCost }
    }

    var totalTodayCost: Double {
        self.providerRows.reduce(0) { $0 + $1.todayCost }
    }

    var total30DayTokens: Int {
        self.providerRows.reduce(0) { $0 + $1.thirtyDayTokens }
    }

    /// Cost-history window in days shown in the Overview headline. When CWL is
    /// ON this is the user's selected window (the dashboard re-windows the
    /// ledger to it); when OFF it's the Mac's max configured `historyDays`
    /// (gap F) across providers. nil → caller defaults to 30.
    var historyDays: Int? {
        if let cwlWindowDays = self.cwlWindowDays { return cwlWindowDays }
        return self.providerRows.compactMap { $0.provider.costSummary?.historyDays }.max()
    }

    var topProvider: ProviderRow? {
        self.providerRows.max { $0.thirtyDayCost < $1.thirtyDayCost }
    }

    var highestDay: DailyPoint? {
        self.dailyPoints.max { $0.costUSD < $1.costUSD }
    }

    var activeDayCount: Int {
        self.dailyPoints.count(where: { $0.costUSD > 0 })
    }

    var hasDisplayData: Bool {
        !self.providerRows.isEmpty || !self.dailyPoints.isEmpty || !self.budgetRows.isEmpty
    }

    init(snapshot: SyncedUsageSnapshot) {
        let todayKey = Self.dayKeyFormatter.string(from: Date())
        var providerRows: [ProviderRow] = []
        var dailyTotals: [String: (costUSD: Double, totalTokens: Int)] = [:]
        var modelTotals: [String: Double] = [:]
        // Codex standard/fast split summed per model across the window, so the
        // Model Mix rows can show a "Std / Fast" sub-line (upstream #1070).
        var modelSplits: [String: (std: Double, fast: Double)] = [:]
        var serviceTotals: [String: Double] = [:]
        var budgetRows: [CostBudgetRow] = []

        // Drop extinct mock zombies before aggregation so the Cost
        // dashboard's totals don't include them. iOS 1.5.2+: see
        // `MockProviderDetector.extinctMockProviderIDs`.
        let liveProviders = MockProviderDetector.filteredProviders(from: snapshot)
        for provider in liveProviders {
            if let budget = provider.budget {
                budgetRows.append(CostBudgetRow(provider: provider, budget: budget))
            }

            guard let costSummary = provider.costSummary else { continue }

            let thirtyDayCost = costSummary.last30DaysCostUSD
                ?? costSummary.daily.reduce(0) { $0 + $1.costUSD }
            let thirtyDayTokens = costSummary.last30DaysTokens
                ?? costSummary.daily.reduce(0) { $0 + $1.totalTokens }

            let todayPoint = costSummary.daily.first(where: { $0.dayKey == todayKey })
            let todayCost = todayPoint?.costUSD ?? costSummary.sessionCostUSD ?? 0

            guard thirtyDayCost > 0 || todayCost > 0 || !costSummary.daily.isEmpty else { continue }

            providerRows.append(
                ProviderRow(
                    provider: provider,
                    thirtyDayCost: thirtyDayCost,
                    todayCost: todayCost,
                    thirtyDayTokens: thirtyDayTokens))

            for point in costSummary.daily {
                dailyTotals[point.dayKey, default: (0, 0)].costUSD += point.costUSD
                dailyTotals[point.dayKey, default: (0, 0)].totalTokens += point.totalTokens

                for breakdown in point.modelBreakdowns where breakdown.costUSD > 0 {
                    modelTotals[breakdown.label, default: 0] += breakdown.costUSD
                    if breakdown.standardCostUSD != nil || breakdown.priorityCostUSD != nil {
                        modelSplits[breakdown.label, default: (0, 0)].std += breakdown.standardCostUSD ?? 0
                        modelSplits[breakdown.label, default: (0, 0)].fast += breakdown.priorityCostUSD ?? 0
                    }
                }

                for breakdown in point.serviceBreakdowns where breakdown.costUSD > 0 {
                    serviceTotals[breakdown.label, default: 0] += breakdown.costUSD
                }
            }
        }

        self.providerRows = providerRows.sorted { lhs, rhs in
            if lhs.thirtyDayCost == rhs.thirtyDayCost {
                return lhs.provider.providerName
                    .localizedCaseInsensitiveCompare(rhs.provider.providerName) == .orderedAscending
            }
            return lhs.thirtyDayCost > rhs.thirtyDayCost
        }

        self.dailyPoints = dailyTotals.keys.compactMap { dayKey in
            guard let date = Self.dayKeyFormatter.date(from: dayKey),
                  let totals = dailyTotals[dayKey] else { return nil }
            return DailyPoint(dayKey: dayKey, date: date, costUSD: totals.costUSD, totalTokens: totals.totalTokens)
        }
        .sorted { $0.date < $1.date }

        self.modelRows = Self.breakdownRows(from: modelTotals, palette: .model, splits: modelSplits)
        self.serviceRows = Self.breakdownRows(from: serviceTotals, palette: .service)
        self.budgetRows = budgetRows.sorted { lhs, rhs in
            let lhsRatio = lhs.budget.limitAmount > 0 ? lhs.budget.usedAmount / lhs.budget.limitAmount : 0
            let rhsRatio = rhs.budget.limitAmount > 0 ? rhs.budget.usedAmount / rhs.budget.limitAmount : 0
            return lhsRatio > rhsRatio
        }
        self.cwlWindowDays = nil
    }

    /// Memberwise init used by `fromLedger` (CWL path) and any future
    /// alternate data source. Callers pass already-sorted arrays — the
    /// blob-backed `init(snapshot:)` above does its own inline sorting.
    init(
        providerRows: [ProviderRow],
        dailyPoints: [DailyPoint],
        modelRows: [CostBreakdownRow],
        serviceRows: [CostBreakdownRow],
        budgetRows: [CostBudgetRow],
        cwlWindowDays: Int? = nil)
    {
        self.providerRows = providerRows
        self.dailyPoints = dailyPoints
        self.modelRows = modelRows
        self.serviceRows = serviceRows
        self.budgetRows = budgetRows
        self.cwlWindowDays = cwlWindowDays
    }

    /// Build insights from the Cost Window Ledger aggregation (CWL ON path,
    /// research doc 024 Round 5 / P4a). Cost fields (provider totals, daily
    /// series, model / service mix) come from the ledger — re-aggregated over
    /// the user's chosen window, which can exceed Mac's historyDays. Provider
    /// metadata (name, color, budget, loginMethod) still comes from the live
    /// snapshot since the ledger stores only IDs + numbers. Providers in the
    /// snapshot but absent from the ledger get no row (no cost yet); ledger
    /// rollups with no matching live provider are dropped (stale / removed
    /// provider — no metadata to render).
    static func fromLedger(
        aggregation: CostLedgerAggregation,
        snapshot: SyncedUsageSnapshot) -> CostDashboardInsights
    {
        let todayKey = Self.dayKeyFormatter.string(from: Date())
        let liveProviders = MockProviderDetector.filteredProviders(from: snapshot)

        var providerRows: [ProviderRow] = []
        for rollup in aggregation.providerRollups.values {
            // Match on the actual (providerID, accountEmail) tuple — avoids the
            // "_"-vs-"" nil-sentinel mismatch between the ledger composite key
            // and `cardIdentityKey`.
            guard let provider = liveProviders.first(where: {
                $0.providerID == rollup.providerID
                    && $0.accountEmail == rollup.accountEmail
            }) else { continue }
            let todayCost = rollup.dailyPoints
                .first(where: { $0.dayKey == todayKey })?.costUSD ?? 0
            providerRows.append(ProviderRow(
                provider: provider,
                thirtyDayCost: rollup.totalCostUSD,
                todayCost: todayCost,
                thirtyDayTokens: rollup.totalTokens))
        }

        var budgetRows: [CostBudgetRow] = []
        for provider in liveProviders {
            if let budget = provider.budget {
                budgetRows.append(CostBudgetRow(provider: provider, budget: budget))
            }
        }

        let dailyPoints: [DailyPoint] = aggregation.dailyPoints.compactMap { point in
            guard let date = Self.dayKeyFormatter.date(from: point.dayKey) else { return nil }
            return DailyPoint(
                dayKey: point.dayKey, date: date,
                costUSD: point.costUSD, totalTokens: point.totalTokens)
        }

        let modelTotals = Dictionary(
            uniqueKeysWithValues: aggregation.modelMix.map { ($0.label, $0.costUSD) })
        let modelSplits = Dictionary(
            uniqueKeysWithValues: aggregation.modelMix.compactMap {
                bd -> (String, (std: Double, fast: Double))? in
                guard bd.standardCostUSD != nil || bd.priorityCostUSD != nil else { return nil }
                return (bd.label, (bd.standardCostUSD ?? 0, bd.priorityCostUSD ?? 0))
            })
        let serviceTotals = Dictionary(
            uniqueKeysWithValues: aggregation.serviceMix.map { ($0.label, $0.costUSD) })

        return CostDashboardInsights(
            providerRows: providerRows.sorted { lhs, rhs in
                if lhs.thirtyDayCost == rhs.thirtyDayCost {
                    return lhs.provider.providerName
                        .localizedCaseInsensitiveCompare(rhs.provider.providerName) == .orderedAscending
                }
                return lhs.thirtyDayCost > rhs.thirtyDayCost
            },
            dailyPoints: dailyPoints.sorted { $0.date < $1.date },
            modelRows: Self.breakdownRows(from: modelTotals, palette: .model, splits: modelSplits),
            serviceRows: Self.breakdownRows(from: serviceTotals, palette: .service),
            budgetRows: budgetRows.sorted { lhs, rhs in
                let lhsRatio = lhs.budget.limitAmount > 0 ? lhs.budget.usedAmount / lhs.budget.limitAmount : 0
                let rhsRatio = rhs.budget.limitAmount > 0 ? rhs.budget.usedAmount / rhs.budget.limitAmount : 0
                return lhsRatio > rhsRatio
            },
            cwlWindowDays: aggregation.windowDays)
    }

    private static func breakdownRows(
        from totals: [String: Double],
        palette: BreakdownPalette,
        splits: [String: (std: Double, fast: Double)] = [:]) -> [CostBreakdownRow]
    {
        totals
            .filter { $0.value > 0 }
            .map { label, amount in
                CostBreakdownRow(
                    label: label,
                    amountUSD: amount,
                    subtitle: splits[label].flatMap {
                        CodexCostSplit.subtitle(standardCostUSD: $0.std, priorityCostUSD: $0.fast)
                    },
                    color: palette.color(for: label))
            }
            .sorted { lhs, rhs in
                if lhs.amountUSD == rhs.amountUSD {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.amountUSD > rhs.amountUSD
            }
    }

    /// Wire-format `dayKey` formatter used to match records to today's
    /// calendar day when reading `SyncCostSummary.daily`. The format
    /// `yyyy-MM-dd` + `en_US_POSIX` + `gregorian` is pinned here to match
    /// Mac-side `SyncCoordinator.daily[].dayKey` generation; changing any
    /// of the three values would make the keys stop round-tripping across
    /// the sync boundary. Do NOT "localize" this — `dayKey` is a machine
    /// contract, not user-facing text. See `SyncCostSummary+Today.swift`
    /// for the symmetric helper used outside this view.
    ///
    /// Only called from view-body (main-actor) synchronous paths —
    /// DateFormatter's documented thread-unsafety does not apply here.
    /// If a future refactor moves the call into a background Task, switch
    /// to `SyncCostSummary.iso8601DayKey(for:)` (per-call factory).
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Today's wire-format day key from the same pinned formatter the
    /// aggregation itself uses for "today" matching. Exposed so CostTab's
    /// insights memo key flips at exactly the same midnight boundary as the
    /// aggregation — a divergent formatter could cache stale "today" totals
    /// across the day rollover. Main-actor only (see formatter doc above).
    static func todayDayKey(now: Date = Date()) -> String {
        self.dayKeyFormatter.string(from: now)
    }
}

struct CostBreakdownRow: Identifiable {
    let label: String
    let amountUSD: Double
    let subtitle: String?
    let color: Color
    let brandProviderID: String?
    /// Optional override for SwiftUI identity. Defaults to `label` for the
    /// existing Model Mix / Codex Service Mix sites where labels are
    /// guaranteed unique (one row per model name, one per service name).
    /// The Provider Share path on the Cost dashboard supplies a composite
    /// key because two Macs running the same provider with different
    /// `accountEmail` values produce two rows with the same `providerName`
    /// label — ForEach would otherwise collide on the duplicate id, render
    /// both rows with the first row's data, and the second account's $$
    /// vanishes from the UI (1.5.3 fix; see Research/021 §1).
    let identityOverride: String?

    init(
        label: String,
        amountUSD: Double,
        subtitle: String?,
        color: Color,
        brandProviderID: String? = nil,
        identityOverride: String? = nil)
    {
        self.label = label
        self.amountUSD = amountUSD
        self.subtitle = subtitle
        self.color = color
        self.brandProviderID = brandProviderID
        self.identityOverride = identityOverride
    }

    var id: String {
        self.identityOverride ?? self.label
    }
}

struct CostBudgetRow: Identifiable {
    let provider: ProviderUsageSnapshot
    let budget: SyncBudgetSnapshot

    /// Use the multi-account-aware composite key, not just `providerID`.
    /// Two budgets coming from two Macs on the same provider but different
    /// accounts would otherwise collide and the second budget would render
    /// with the first's data (1.5.3 fix; see Research/021 §1).
    var id: String {
        self.provider.cardIdentityKey
    }
}

/// Deterministic color palette for model / service breakdown chips on the Cost tab.
///
/// The HSB constants below are tuned for two competing requirements:
/// - Labels (e.g. model names like "claude-3-5-sonnet") must get a stable,
///   reproducible color — so we seed from `label` hash and look up HSB from a
///   small constant range rather than choosing randomly.
/// - Adjacent chips in a breakdown list must stay visually distinct — the
///   saturation and brightness ranges are narrow on purpose; widening them
///   introduces grey-ish or washed-out colors that blend into the card
///   material background.
///
/// - `hueBase = 0.08` (model) — warm orange/red family, reserved for model
///   chips (e.g. "claude-3-5-sonnet-20250219").
/// - `hueBase = 0.52` (service) — cool cyan/blue family, reserved for
///   service/deployment chips. The ~0.44 hue gap keeps the two families
///   easily distinguishable even when a user's list mixes both.
/// - Hue variation of `±0.21` (seed % 21 / 100) spreads labels across a
///   slice of the hue wheel without crossing into the other family.
/// - Saturation: 0.62–0.83 — below 0.62 reads as grey on the Cost tab's
///   `.ultraThinMaterial`; above ~0.85 looks harsh on iPad's wider gamut.
/// - Brightness: 0.78–0.93 — ensures WCAG-adjacent contrast on the dark-
///   mode material background; below 0.78 reads as muddy, above 0.93 blows
///   out text legibility overlaid on the chip.
///
/// Do NOT replace with `.random()` or a generic palette API — these
/// specific ranges are load-bearing for the Cost tab's visual clarity.
private enum BreakdownPalette {
    case model
    case service

    func color(for label: String) -> Color {
        let seed = label.lowercased().unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        let hueBase = switch self {
        case .model: 0.08
        case .service: 0.52
        }
        let hue = (hueBase + (Double(seed % 21) / 100)).truncatingRemainder(dividingBy: 1)
        let saturation = 0.62 + Double(seed % 7) * 0.03
        let brightness = 0.78 + Double(seed % 5) * 0.03
        return Color(hue: hue, saturation: min(saturation, 0.95), brightness: min(brightness, 0.98))
    }
}
