import Charts
import CodexBarSync
import SwiftUI

/// Independent Subscription Utilization section for the Cost tab.
/// Uses **calendar days** (matches the cost chart's daily granularity).
/// Includes: 4 period summary cards, daily trend chart, provider share breakdown.
struct UtilizationAggregateView: View {
    let providers: [ProviderUsageSnapshot]

    @State private var selectedIndex: Int?
    @State private var cachedKey: String = ""
    @State private var cachedModel: AggregateModel?

    // Honor the Usage tab's "Show remaining usage" toggle here too — pre-fix
    // the share row always rendered "86% avg use" even when the user had
    // flipped the toggle and every other card on the Usage tab was showing
    // "14% remaining". Matches `UsageCardView`'s own @AppStorage declaration
    // (including the legacy-key migration default) so we toggle in lockstep.
    @AppStorage(MobileSettingsKeys.showRemainingUsage) private var showRemainingUsage =
        UserDefaults.standard.string(forKey: MobileSettingsKeys.usagePercentDisplayMode) == UsagePercentDisplayMode.remaining.rawValue

    /// Bar width in points. Tuned with `windowSize` so 30 bars + their
    /// inter-bar padding fit within the Cost tab's card width on a 390pt
    /// iPhone screen. Narrower than `UtilizationHistoryView`'s 10pt because
    /// this chart shares vertical space with 4 summary cards above it and
    /// a provider list below it, so the plot area is more constrained.
    /// Changing this without re-tuning `windowSize` can make labels overlap
    /// or leave excessive empty padding.
    private let barWidth: CGFloat = 8
    /// 30-day window — matches Cost tab's daily-spend chart so the two
    /// sections read as a coherent 30-day story. Also pins the axis
    /// `dateFormat` to compact `"M/d"` (see `dayLabelFormatter` below),
    /// because 8pt-wide bars can't accommodate locale-aware labels like
    /// Simplified Chinese's `"4月23日"`.
    private let windowSize = 30

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

    private var identityKey: String {
        Self.identityKey(for: self.providers, windowSize: self.windowSize)
    }

    var body: some View {
        // Synchronous cache resolution:
        // - Cache hit (identity stable, e.g. hover) → return cached model, ZERO compute
        // - Cache miss → compute synchronously so the view has data on THIS frame.
        //   `.onChange(initial: true)` fires just after to persist the result into
        //   @State so subsequent renders hit the cache.
        // Previous `.task(id:)` pattern rendered empty on first frame while the async
        // task populated the cache — user reported the entire Subscription Utilization
        // section disappearing. Sync fallback fixes that without sacrificing hover
        // performance (identity is stable during hover, so cache stays warm).
        let currentKey = self.identityKey
        let model: AggregateModel? = (self.cachedKey == currentKey)
            ? self.cachedModel
            : Self.buildModel(from: self.providers, windowSize: self.windowSize)

        return Group {
            if let m = model {
                self.content(m)
            }
        }
        .onChange(of: currentKey, initial: true) { _, newKey in
            if self.cachedKey != newKey {
                self.cachedModel = Self.buildModel(from: self.providers, windowSize: self.windowSize)
                self.cachedKey = newKey
            }
        }
    }

    @ViewBuilder
    private func content(_ m: AggregateModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
                // Title — matches other Cost-tab section headers (.headline)
                Text("Subscription Utilization")
                    .font(.headline)
                    .padding(.top, 4)

                Text("Session quota usage trend across synced providers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // 4 Summary Cards
                self.summaryCards(m)

                // Daily Trend Chart + Detail Line
                if !m.dayBars.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        self.dailyChart(m)
                            .frame(height: 120)
                        self.detailLine(m)
                            .frame(height: 16)
                    }
                }

                // Provider cards — merged directly into this section (no sub-header)
                if !m.providerShares.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(m.providerShares) { row in
                            self.providerShareRow(row)
                        }
                    }
                }
        }
    }

    // MARK: - Summary Cards (4 periods)

    private func summaryCards(_ m: AggregateModel) -> some View {
        HStack(spacing: 6) {
            self.periodCard(title: "Today", value: m.todayAvg, delta: m.todayDelta)
            self.periodCard(title: "This Week", value: m.thisWeekAvg, delta: m.thisWeekDelta)
            self.periodCard(title: "14 Days", value: m.last14Avg, delta: m.last14Delta)
            self.periodCard(title: "30 Days", value: m.last30Avg, delta: m.last30Delta)
        }
    }

    private func periodCard(
        title: LocalizedStringKey,
        value: Double?,
        delta: Double?) -> some View
    {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let delta {
                let sign = delta >= 0 ? "+" : ""
                Text(String(format: "%@%.0f%%", sign, delta))
                    .font(.caption2.bold())
                    .foregroundStyle(delta >= 0 ? .orange : .green)
                    .lineLimit(1)
            } else {
                // Reserve vertical space so all 4 cards align
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Daily Chart

    private func dailyChart(_ m: AggregateModel) -> some View {
        Chart {
            ForEach(m.dayBars) { bar in
                if !bar.isPadding {
                    ForEach(bar.segments, id: \.providerID) { seg in
                        BarMark(
                            x: .value("D", bar.id),
                            y: .value("V", seg.avgPercent),
                            width: .fixed(self.barWidth))
                            .foregroundStyle(seg.color)
                    }
                }
            }

            if let si = self.selectedIndex, si >= 0, si < m.dayBars.count, !m.dayBars[si].isPadding {
                RuleMark(x: .value("S", si))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel {
                    if let idx = value.as(Int.self), idx >= 0, idx < m.dayBars.count,
                       let label = m.dayBars[idx].dayLabel
                    {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: 0 ... max(m.dayBars.count - 1, self.windowSize - 1))
        .chartXSelection(value: self.$selectedIndex)
    }

    // MARK: - Detail Line

    @ViewBuilder
    private func detailLine(_ m: AggregateModel) -> some View {
        if let si = self.selectedIndex, si >= 0, si < m.dayBars.count, !m.dayBars[si].isPadding {
            let bar = m.dayBars[si]
            let avg = bar.segments.isEmpty ? 0.0
                : bar.segments.reduce(0.0) { $0 + $1.avgPercent } / Double(bar.segments.count)
            HStack {
                Text(bar.dayLabel ?? "")
                Spacer()
                Text(String(format: "%.0f%% avg", avg))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack {
                Text("\(m.providerShares.count) providers")
                Spacer()
                if let last30 = m.last30Avg {
                    Text(String(format: "%.0f%% 30-day avg", last30))
                        .fontWeight(.medium)
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Provider Share Row

    /// Subtitle under each provider name on the share rows. Respects the
    /// "Show remaining usage" setting so every place on the Cost tab agrees
    /// on which direction the number runs. `rawAvgPercent` is the 30-day
    /// average of daily peaks (so "% remaining" is `100 - avg`, not inverse
    /// on a per-day basis — the right interpretation when the underlying
    /// number is already an average over days).
    private func averageUsageSubtitle(for rawAvgPercent: Double) -> String {
        if self.showRemainingUsage {
            let remaining = max(0, 100 - rawAvgPercent)
            return String(format: String(localized: "%.0f%% avg remaining"), remaining)
        }
        return String(format: String(localized: "%.0f%% avg use"), rawAvgPercent)
    }

    private func providerShareRow(_ row: ProviderShare) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(row.color)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(self.averageUsageSubtitle(for: row.rawAvgPercent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(format: "%.0f%%", row.sharePercent))
                    .font(.title3.monospacedDigit().bold())
            }

            ProgressView(value: row.sharePercent / 100)
                .tint(row.color)
                .scaleEffect(y: 1.8, anchor: .center)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Data Model

    struct DaySegment {
        let providerID: String
        let providerName: String
        let avgPercent: Double
        let color: Color
    }

    struct DayBar: Identifiable {
        let id: Int
        let dayLabel: String?
        let segments: [DaySegment]
        let isPadding: Bool
    }

    struct ProviderShare: Identifiable {
        let id: String
        let name: String
        let color: Color
        let rawAvgPercent: Double  // 30-day raw average usage %
        let sharePercent: Double   // proportional share, sums to 100% across providers
    }

    struct AggregateModel {
        let dayBars: [DayBar]
        let providerShares: [ProviderShare]
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
    nonisolated static func buildModel(from providers: [ProviderUsageSnapshot], windowSize: Int) -> AggregateModel? {
        let calendar = Calendar.current

        // Collect providers that have any session-window utilization history.
        // Union entries across EVERY series named "session" (not just the first);
        // this shields us from cross-version duplication where `mergeUtilizationHistories`
        // left two "session" series behind because the devices disagreed on windowMinutes.
        let providerData = providers.compactMap { provider -> (id: String, name: String, color: Color, dayMaxes: [Date: Double])? in
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
            return (id: provider.providerID, name: provider.providerName,
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

        var realBars: [DayBar] = []
        for day in recentDays {
            var segments: [DaySegment] = []
            for pd in providerData {
                if let peak = pd.dayMaxes[day] {
                    segments.append(DaySegment(
                        providerID: pd.id, providerName: pd.name,
                        avgPercent: peak, color: pd.color))
                }
            }
            realBars.append(DayBar(
                id: 0,  // re-assigned below
                dayLabel: dayLabelFormatter.string(from: day),
                segments: segments,
                isPadding: false))
        }

        // Right-align: pad left if fewer than `windowSize` real days
        var dayBars: [DayBar]
        if realBars.count < windowSize {
            let pad = windowSize - realBars.count
            var padded: [DayBar] = (0 ..< pad).map {
                DayBar(id: $0, dayLabel: nil, segments: [], isPadding: true)
            }
            for (off, bar) in realBars.enumerated() {
                padded.append(DayBar(
                    id: pad + off,
                    dayLabel: bar.dayLabel,
                    segments: bar.segments,
                    isPadding: false))
            }
            dayBars = padded
        } else {
            dayBars = realBars.enumerated().map { idx, bar in
                DayBar(id: idx, dayLabel: bar.dayLabel, segments: bar.segments, isPadding: false)
            }
        }

        // === Provider Share (30-day avg of daily peaks) ===

        let providerThirtyDayRaw: [(id: String, name: String, color: Color, avg: Double)] = providerData.compactMap { pd in
            let recent = pd.dayMaxes.filter { $0.key >= last30Start }.values
            guard !recent.isEmpty else { return nil }
            let avg = recent.reduce(0, +) / Double(recent.count)
            return (id: pd.id, name: pd.name, color: pd.color, avg: avg)
        }

        let totalRaw = providerThirtyDayRaw.reduce(0) { $0 + $1.avg }
        let providerShares: [ProviderShare] = providerThirtyDayRaw
            .map { item in
                ProviderShare(
                    id: item.id,
                    name: item.name,
                    color: item.color,
                    rawAvgPercent: item.avg,
                    sharePercent: totalRaw > 0 ? (item.avg / totalRaw * 100) : 0)
            }
            .sorted { $0.sharePercent > $1.sharePercent }

        return AggregateModel(
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
