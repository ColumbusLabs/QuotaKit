import CodexBarSync
import Foundation
import SwiftUI

// MARK: - Data Model

struct UtilizationDaySegment {
    /// **Despite the name, this holds the multi-account-aware
    /// `cardIdentityKey` (providerID|accountEmail)** so the chart's
    /// `ForEach(bar.segments, id: \.providerID)` iteration stays
    /// collision-free when two accounts of the same provider both
    /// contribute segments to the same day (1.5.3 fix). Field name
    /// kept for source-stability — the chart code reads it as an
    /// opaque ForEach id, not as a provider lookup key.
    let providerID: String
    let providerName: String
    let avgPercent: Double
    let color: Color
}

struct UtilizationDayBar: Identifiable {
    let id: Int
    let dayLabel: String?
    let segments: [UtilizationDaySegment]
    let isPadding: Bool
}

struct UtilizationProviderShare: Identifiable {
    let id: String
    let providerID: String
    let name: String
    let color: Color
    let rawAvgPercent: Double  // 30-day raw average usage %
    let sharePercent: Double   // proportional share, sums to 100% across providers
}

struct UtilizationAggregateModel {
    let dayBars: [UtilizationDayBar]
    let providerShares: [UtilizationProviderShare]
    // 4 summary periods (nil = no data for that period)
    let todayAvg: Double?
    let todayDelta: Double?
    let thisWeekAvg: Double?
    let thisWeekDelta: Double?
    let last14Avg: Double?
    let last14Delta: Double?
    let last30Avg: Double?
    let last30Delta: Double?
}

enum UtilizationAggregateModelBuilder {
    /// Identity key for `providers` input. Cheap O(N) over providers — does NOT iterate
    /// utilization entries. This property is the `.task(id:)` key and is recomputed on
    /// every render including hover/drag state changes, so the per-frame cost must stay
    /// bounded by provider count (typically ≤ 25), not entry count (up to 730 × 3 series
    /// per provider).
    ///
    /// Correctness: every upstream change to utilization entries arrives via a fresh
    /// provider snapshot whose `lastUpdated` is bumped by the Mac-side fetcher; iOS's
    /// `mergeSnapshots` preserves `max(lastUpdated)` across devices. Therefore
    /// `max(lastUpdated)` IS a sufficient content-invalidation signal in this app's
    /// data flow. A content-only mutation without any `lastUpdated` bump would be a
    /// protocol violation rather than a legitimate state we need to cache-invalidate
    /// against. A previous attempt to include full entry-level content (per Codex
    /// review P2) re-paid the O(N) cost on every hover frame, negating the caching
    /// win — that was a worse trade-off than tolerating a theoretical gap that our
    /// data flow precludes.
    static func identityKey(for providers: [ProviderUsageSnapshot], windowSize: Int) -> String {
        let ids = providers.map(\.providerID).sorted().joined(separator: ",")
        let latest = providers.map(\.lastUpdated).max()?.timeIntervalSince1970 ?? 0
        // Count entries via plain for-loops rather than nested reduce-with-closure;
        // closure variants have caused the swift-testing runner to crash at test
        // invocation boundaries on the View struct type (same class of issue as the
        // earlier sorted(by:) attempt).
        var totalEntries = 0
        for provider in providers {
            guard let history = provider.utilizationHistory else { continue }
            for series in history {
                totalEntries += series.entries.count
            }
        }
        return "\(ids)|\(latest)|\(windowSize)|n=\(totalEntries)"
    }

    // MARK: - Build Model

    /// Builds the aggregate from per-provider utilization entries, using
    /// **daily peak** semantics throughout:
    ///
    ///   daily peak = max(usedPercent) across all entries captured that day
    ///
    /// Why peak instead of raw average: session quotas (5h, reset-based) produce
    /// many samples at 0% between bursts of activity. Raw-averaging them makes
    /// bursty providers (e.g. Codex used in short sessions) read as 0% here
    /// while `UtilizationHistoryView` — which takes `max` per reset period —
    /// shows meaningful bars on the detail page. That cross-view mismatch is a
    /// reported user bug. Collapsing to daily peaks aligns the two views: each
    /// day's bar here represents the same "peak usage" signal the detail chart
    /// shows one level up.
    ///
    /// If a provider has two or more session series after multi-device merge
    /// (cross-version Macs reporting with different `windowMinutes`), we union
    /// their entries BEFORE collapsing to daily peaks — one Mac's stale/empty
    /// "session" can no longer mask the other's real data, because the daily
    /// max picks the highest observed value regardless of which device captured it.
    nonisolated static func buildModel(from providers: [ProviderUsageSnapshot], windowSize: Int) -> UtilizationAggregateModel? {
        let calendar = Calendar.current

        // Collect providers that have any session-window utilization history.
        // Union entries across EVERY series named "session" (not just the first);
        // this shields us from cross-version duplication where `mergeUtilizationHistories`
        // left two "session" series behind because the devices disagreed on windowMinutes.
        //
        // **id**: must be `cardIdentityKey` (providerID|accountEmail), not raw
        // `providerID`. Two accounts on the same provider (e.g. two Codex
        // accounts after Mac ≥ 0.25 starts extracting accountEmail) would
        // otherwise collide on `id` here and propagate the collision into the
        // chart segment ForEach and the UtilizationProviderShare list. 1.5.3 fix.
        let providerData = providers.compactMap { provider -> (id: String, providerID: String, name: String, color: Color, dayMaxes: [Date: Double])? in
            guard let history = provider.utilizationHistory else { return nil }
            let sessionSeries = history.filter { $0.name == "session" }
            let chosen = sessionSeries.isEmpty ? Array(history.prefix(1)) : sessionSeries
            let entries = chosen.flatMap(\.entries)
            guard !entries.isEmpty else { return nil }

            // Collapse to daily peak.
            var dayMaxes: [Date: Double] = [:]
            for entry in entries {
                let day = calendar.startOfDay(for: entry.capturedAt)
                dayMaxes[day] = max(dayMaxes[day] ?? 0, entry.usedPercent)
            }
            guard !dayMaxes.isEmpty else { return nil }
            return (id: provider.cardIdentityKey, providerID: provider.providerID, name: provider.providerName,
                    color: Self.providerColor(for: provider.providerID),
                    dayMaxes: dayMaxes)
        }

        guard !providerData.isEmpty else { return nil }

        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now

        // Helper: average of per-provider (average-of-daily-peaks-in-window), then
        // average across providers. Returns nil if NO provider has any day in window.
        func aggregateAvg(from start: Date, to end: Date) -> Double? {
            let providerAvgs: [Double] = providerData.compactMap { pd in
                let vals = pd.dayMaxes.filter { $0.key >= start && $0.key < end }.values
                guard !vals.isEmpty else { return nil }
                return vals.reduce(0, +) / Double(vals.count)
            }
            guard !providerAvgs.isEmpty else { return nil }
            return providerAvgs.reduce(0, +) / Double(providerAvgs.count)
        }

        // Helper: compute delta only when BOTH current and previous have data.
        func delta(current: Double?, previous: Double?) -> Double? {
            guard let current, let previous else { return nil }
            return current - previous
        }

        // === 4 Summary Periods ===

        // Today / Yesterday
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let todayAvg = aggregateAvg(from: todayStart, to: tomorrowStart)
        let yesterdayAvg = aggregateAvg(from: yesterdayStart, to: todayStart)
        let todayDelta = delta(current: todayAvg, previous: yesterdayAvg)

        // This Week / Last Week (ISO Mon-Sun)
        var isoCal = Calendar(identifier: .iso8601)
        isoCal.timeZone = .current
        let weekComps = isoCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let thisWeekStart = isoCal.date(from: weekComps) ?? todayStart
        let lastWeekStart = isoCal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart
        let nextWeekStart = isoCal.date(byAdding: .weekOfYear, value: 1, to: thisWeekStart) ?? tomorrowStart
        let thisWeekAvg = aggregateAvg(from: thisWeekStart, to: nextWeekStart)
        let lastWeekAvg = aggregateAvg(from: lastWeekStart, to: thisWeekStart)
        let thisWeekDelta = delta(current: thisWeekAvg, previous: lastWeekAvg)

        // 14 Days / Prev 14 (rolling, anchored to start of today)
        let last14Start = calendar.date(byAdding: .day, value: -13, to: todayStart) ?? todayStart
        let prev14Start = calendar.date(byAdding: .day, value: -27, to: todayStart) ?? todayStart
        let last14Avg = aggregateAvg(from: last14Start, to: tomorrowStart)
        let prev14Avg = aggregateAvg(from: prev14Start, to: last14Start)
        let last14Delta = delta(current: last14Avg, previous: prev14Avg)

        // 30 Days / Prev 30 (rolling, anchored to start of today)
        let last30Start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
        let prev30Start = calendar.date(byAdding: .day, value: -59, to: todayStart) ?? todayStart
        let last30Avg = aggregateAvg(from: last30Start, to: tomorrowStart)
        let prev30Avg = aggregateAvg(from: prev30Start, to: last30Start)
        let last30Delta = delta(current: last30Avg, previous: prev30Avg)

        // === Daily Bars (height = daily peak per provider) ===

        // Collect all unique days across providers, keep only the last `windowSize` days
        let allDaysSorted = Set(providerData.flatMap { $0.dayMaxes.keys }).sorted()
        let recentDays = allDaysSorted.filter { $0 >= last30Start }
        guard !recentDays.isEmpty else { return nil }

        // **Intentionally hardcoded English compact numeric format.**
        //
        // `M/d` + `Locale("en_US")` is a deliberate design choice from commit
        // 79f207d2 ("use compact numeric date labels"). The 30-day chart
        // renders 30 bars with `barWidth: 8pt` each; labels need to stay as
        // short as "4/23" to fit. A naive `setLocalizedDateFormatFromTemplate("Md")`
        // would respect the user's locale and in Simplified Chinese would
        // produce "4月23日" — three characters of CJK glyph per label, which
        // overflows the bar spacing and breaks the chart layout.
        //
        // Cross-locale users see the same compact "M/d" format; this is
        // by design, not an i18n miss. Build 81 briefly replaced it with the
        // template approach based on an agent audit that didn't check the
        // chart geometry constraint — reverted in Build 85.
        let dayLabelFormatter = DateFormatter()
        dayLabelFormatter.dateFormat = "M/d"
        dayLabelFormatter.locale = Locale(identifier: "en_US")

        var realBars: [UtilizationDayBar] = []
        for day in recentDays {
            var segments: [UtilizationDaySegment] = []
            for pd in providerData {
                if let peak = pd.dayMaxes[day] {
                    segments.append(UtilizationDaySegment(
                        providerID: pd.id, providerName: pd.name,
                        avgPercent: peak, color: pd.color))
                }
            }
            realBars.append(UtilizationDayBar(
                id: 0,  // re-assigned below
                dayLabel: dayLabelFormatter.string(from: day),
                segments: segments,
                isPadding: false))
        }

        // Right-align: pad left if fewer than `windowSize` real days
        var dayBars: [UtilizationDayBar]
        if realBars.count < windowSize {
            let pad = windowSize - realBars.count
            var padded: [UtilizationDayBar] = (0 ..< pad).map {
                UtilizationDayBar(id: $0, dayLabel: nil, segments: [], isPadding: true)
            }
            for (off, bar) in realBars.enumerated() {
                padded.append(UtilizationDayBar(
                    id: pad + off,
                    dayLabel: bar.dayLabel,
                    segments: bar.segments,
                    isPadding: false))
            }
            dayBars = padded
        } else {
            dayBars = realBars.enumerated().map { idx, bar in
                UtilizationDayBar(id: idx, dayLabel: bar.dayLabel, segments: bar.segments, isPadding: false)
            }
        }

        // === Provider Share (30-day avg of daily peaks) ===

        let providerThirtyDayRaw: [(id: String, providerID: String, name: String, color: Color, avg: Double)] = providerData.compactMap { pd in
            let recent = pd.dayMaxes.filter { $0.key >= last30Start }.values
            guard !recent.isEmpty else { return nil }
            let avg = recent.reduce(0, +) / Double(recent.count)
            return (id: pd.id, providerID: pd.providerID, name: pd.name, color: pd.color, avg: avg)
        }

        let totalRaw = providerThirtyDayRaw.reduce(0) { $0 + $1.avg }
        let providerShares: [UtilizationProviderShare] = providerThirtyDayRaw
            .map { item in
                UtilizationProviderShare(
                    id: item.id,
                    providerID: item.providerID,
                    name: item.name,
                    color: item.color,
                    rawAvgPercent: item.avg,
                    sharePercent: totalRaw > 0 ? (item.avg / totalRaw * 100) : 0)
            }
            .sorted { $0.sharePercent > $1.sharePercent }

        return UtilizationAggregateModel(
            dayBars: dayBars,
            providerShares: providerShares,
            todayAvg: todayAvg,
            todayDelta: todayDelta,
            thisWeekAvg: thisWeekAvg,
            thisWeekDelta: thisWeekDelta,
            last14Avg: last14Avg,
            last14Delta: last14Delta,
            last30Avg: last30Avg,
            last30Delta: last30Delta)
    }

    // MARK: - Colors

    nonisolated private static func providerColor(for id: String) -> Color {
        ProviderColorPalette.color(for: id)
    }

}
