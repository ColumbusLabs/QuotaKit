import Charts
import CodexBarSync
import SwiftUI

/// Independent Subscription Utilization section for the Cost tab.
/// Uses **calendar days** (matches the cost chart's daily granularity).
/// Includes: 4 period summary cards, daily trend chart, provider share breakdown.
struct UtilizationAggregateView: View {
    let providers: [ProviderUsageSnapshot]

    @State private var selectedIndex: Int?

    private let barWidth: CGFloat = 8
    private let windowSize = 30  // 30 days to match the cost chart

    private var model: AggregateModel? {
        Self.buildModel(from: self.providers, windowSize: self.windowSize)
    }

    var body: some View {
        if let m = self.model {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text("Subscription Utilization")
                    .font(.title3.bold())

                // 4 Summary Cards
                self.summaryCards(m)

                // Daily Trend Chart
                if !m.dayBars.isEmpty {
                    self.dailyChart(m)
                        .frame(height: 120)
                    self.detailLine(m)
                        .frame(height: 16)
                }

                // Provider Share Breakdown
                if !m.providerShares.isEmpty {
                    self.providerShareSection(m)
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

    // MARK: - Provider Share Section

    private func providerShareSection(_ m: AggregateModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Provider Share")
                .font(.headline)
                .padding(.top, 4)

            Text("30-day utilization share across synced providers.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(m.providerShares) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(row.color)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(String(format: "%.0f%% avg use", row.rawAvgPercent))
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
            }
        }
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

    private static func buildModel(from providers: [ProviderUsageSnapshot], windowSize: Int) -> AggregateModel? {
        // Collect providers that have session-window utilization history
        let providerData = providers.compactMap { provider -> (id: String, name: String, color: Color, entries: [SyncUtilizationEntry])? in
            guard let history = provider.utilizationHistory,
                  let session = history.first(where: { $0.name == "session" }) ?? history.first,
                  !session.entries.isEmpty
            else { return nil }
            return (id: provider.providerID, name: provider.providerName,
                    color: Self.providerColor(for: provider.providerID),
                    entries: session.entries)
        }

        guard !providerData.isEmpty else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now

        // Helper: average raw entries per provider in [start, end), then average across providers.
        // Returns nil if NO provider has any entry in this window.
        func aggregateAvg(from start: Date, to end: Date) -> Double? {
            let providerAvgs: [Double] = providerData.compactMap { pd in
                let filtered = pd.entries.filter { $0.capturedAt >= start && $0.capturedAt < end }
                guard !filtered.isEmpty else { return nil }
                return filtered.reduce(0.0) { $0 + $1.usedPercent } / Double(filtered.count)
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

        // === Daily Bars ===

        // Per-provider daily averages
        var providerDaily: [(id: String, name: String, color: Color, dayAvgs: [Date: Double])] = []

        for pd in providerData {
            var dayBuckets: [Date: [Double]] = [:]
            for entry in pd.entries {
                let day = calendar.startOfDay(for: entry.capturedAt)
                dayBuckets[day, default: []].append(entry.usedPercent)
            }
            let dayAvgs = dayBuckets.mapValues { vals in vals.reduce(0, +) / Double(vals.count) }
            providerDaily.append((id: pd.id, name: pd.name, color: pd.color, dayAvgs: dayAvgs))
        }

        // Collect all unique days across providers, keep only the last `windowSize` days
        let allDaysSorted = Set(providerDaily.flatMap { $0.dayAvgs.keys }).sorted()
        let cutoff = last30Start
        let recentDays = allDaysSorted.filter { $0 >= cutoff }
        guard !recentDays.isEmpty else { return nil }

        // Build real bars
        let dayLabelFormatter = DateFormatter()
        dayLabelFormatter.dateFormat = "M/d"
        dayLabelFormatter.locale = Locale(identifier: "en_US")

        var realBars: [DayBar] = []
        for day in recentDays {
            var segments: [DaySegment] = []
            for pd in providerDaily {
                if let avg = pd.dayAvgs[day] {
                    segments.append(DaySegment(
                        providerID: pd.id, providerName: pd.name,
                        avgPercent: avg, color: pd.color))
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

        // === Provider Share (based on 30-day raw averages) ===

        let providerThirtyDayRaw: [(id: String, name: String, color: Color, avg: Double)] = providerData.compactMap { pd in
            let recent = pd.entries.filter { $0.capturedAt >= last30Start }
            guard !recent.isEmpty else { return nil }
            let avg = recent.reduce(0.0) { $0 + $1.usedPercent } / Double(recent.count)
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

    private static func providerColor(for id: String) -> Color {
        switch id {
        case "claude": Color(red: 0.82, green: 0.55, blue: 0.28)
        case "codex": .purple
        case "cursor": .blue
        case "chatgpt": .green
        case "gemini": .cyan
        default: .gray
        }
    }
}
