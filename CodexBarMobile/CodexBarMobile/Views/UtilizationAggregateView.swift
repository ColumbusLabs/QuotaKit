import Charts
import CodexBarSync
import SwiftUI

/// Independent Subscription Utilization section for the Cost tab.
/// Uses **calendar weeks** (Mon 00:00 – Sun 23:59) instead of provider reset windows.
/// Includes: summary cards, weekly trend chart, provider breakdown.
struct UtilizationAggregateView: View {
    let providers: [ProviderUsageSnapshot]

    @State private var selectedIndex: Int?

    private let barWidth: CGFloat = 8
    private let windowSize = 12  // Show up to 12 weeks

    private var model: AggregateModel? {
        Self.buildModel(from: self.providers, windowSize: self.windowSize)
    }

    var body: some View {
        if let m = self.model {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text("Subscription Utilization")
                    .font(.title3.bold())

                // Summary Cards
                self.summaryCards(m)

                // Weekly Trend Chart
                if !m.weekBars.isEmpty {
                    self.weeklyChart(m)
                        .frame(height: 120)
                    self.detailLine(m)
                        .frame(height: 16)
                }

                // Provider Breakdown
                if !m.providerBreakdown.isEmpty {
                    self.providerBreakdownSection(m)
                }
            }
        }
    }

    // MARK: - Summary Cards

    private func summaryCards(_ m: AggregateModel) -> some View {
        HStack(spacing: 12) {
            // This Week
            VStack(alignment: .leading, spacing: 4) {
                Text("This Week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f%%", m.thisWeekAvg))
                        .font(.title.bold())
                    if let delta = m.weekOverWeekDelta {
                        let sign = delta >= 0 ? "+" : ""
                        Text(String(format: "%@%.0f%%", sign, delta))
                            .font(.caption.bold())
                            .foregroundStyle(delta >= 0 ? .orange : .green)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            // 30-Day Avg
            VStack(alignment: .leading, spacing: 4) {
                Text("30-Day Avg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", m.thirtyDayAvg))
                    .font(.title.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Weekly Chart

    private func weeklyChart(_ m: AggregateModel) -> some View {
        Chart {
            ForEach(m.weekBars) { bar in
                if !bar.isPadding {
                    ForEach(bar.segments, id: \.providerID) { seg in
                        BarMark(
                            x: .value("I", bar.id),
                            y: .value("V", seg.avgPercent),
                            width: .fixed(self.barWidth))
                            .foregroundStyle(seg.color)
                    }
                }
            }

            if let si = self.selectedIndex, si >= 0, si < m.weekBars.count, !m.weekBars[si].isPadding {
                RuleMark(x: .value("S", si))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel {
                    if let idx = value.as(Int.self), idx >= 0, idx < m.weekBars.count,
                       let label = m.weekBars[idx].weekLabel
                    {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: 0 ... max(m.weekBars.count - 1, self.windowSize - 1))
        .chartXSelection(value: self.$selectedIndex)
    }

    // MARK: - Detail Line

    @ViewBuilder
    private func detailLine(_ m: AggregateModel) -> some View {
        if let si = self.selectedIndex, si >= 0, si < m.weekBars.count, !m.weekBars[si].isPadding {
            let bar = m.weekBars[si]
            let avg = bar.segments.isEmpty ? 0.0
                : bar.segments.reduce(0.0) { $0 + $1.avgPercent } / Double(bar.segments.count)
            HStack {
                Text(bar.weekLabel ?? "")
                Spacer()
                Text(String(format: "%.0f%% avg", avg))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack {
                Text("\(m.providerBreakdown.count) providers")
                Spacer()
                Text(String(format: "%.0f%% avg", m.thirtyDayAvg))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Provider Breakdown

    private func providerBreakdownSection(_ m: AggregateModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(m.providerBreakdown, id: \.id) { pb in
                HStack(spacing: 10) {
                    Circle().fill(pb.color).frame(width: 8, height: 8)
                    Text(pb.name)
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.0f%%", pb.thisWeekAvg))
                        .font(.subheadline.bold().monospacedDigit())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.06))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(pb.color)
                            .frame(width: max(4, geo.size.width * pb.thisWeekAvg / 100))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - Data Model

    struct WeekSegment {
        let providerID: String
        let providerName: String
        let avgPercent: Double
        let color: Color
    }

    struct WeekBar: Identifiable {
        let id: Int
        let weekLabel: String?
        let segments: [WeekSegment]
        let isPadding: Bool
    }

    struct ProviderBreakdown: Identifiable {
        let id: String
        let name: String
        let color: Color
        let thisWeekAvg: Double
    }

    struct AggregateModel {
        let weekBars: [WeekBar]
        let providerBreakdown: [ProviderBreakdown]
        let thisWeekAvg: Double
        let weekOverWeekDelta: Double?
        let thirtyDayAvg: Double
    }

    // MARK: - Build Model

    private static func buildModel(from providers: [ProviderUsageSnapshot], windowSize: Int) -> AggregateModel? {
        // Collect all providers with session utilization data
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

        // Group each provider's entries by calendar week (Mon-Sun)
        struct WeekKey: Hashable, Comparable {
            let year: Int
            let weekOfYear: Int
            static func < (lhs: WeekKey, rhs: WeekKey) -> Bool {
                if lhs.year != rhs.year { return lhs.year < rhs.year }
                return lhs.weekOfYear < rhs.weekOfYear
            }
        }

        func weekKey(for date: Date) -> WeekKey {
            var cal = Calendar(identifier: .iso8601)  // ISO: week starts Monday
            cal.timeZone = .current
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return WeekKey(year: comps.yearForWeekOfYear ?? 2026, weekOfYear: comps.weekOfYear ?? 1)
        }

        func weekLabel(for key: WeekKey) -> String {
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = .current
            var comps = DateComponents()
            comps.yearForWeekOfYear = key.year
            comps.weekOfYear = key.weekOfYear
            comps.weekday = 2  // Monday
            if let date = cal.date(from: comps) {
                let formatter = DateFormatter()
                formatter.dateFormat = "M/d"
                return formatter.string(from: date)
            }
            return "W\(key.weekOfYear)"
        }

        // Per-provider weekly averages
        var providerWeekly: [(id: String, name: String, color: Color, weekAvgs: [WeekKey: Double])] = []

        for pd in providerData {
            var weekBuckets: [WeekKey: [Double]] = [:]
            for entry in pd.entries {
                let wk = weekKey(for: entry.capturedAt)
                weekBuckets[wk, default: []].append(entry.usedPercent)
            }
            let weekAvgs = weekBuckets.mapValues { values in
                values.reduce(0, +) / Double(values.count)
            }
            providerWeekly.append((id: pd.id, name: pd.name, color: pd.color, weekAvgs: weekAvgs))
        }

        // Collect all week keys across providers
        let allWeekKeys = Set(providerWeekly.flatMap { $0.weekAvgs.keys }).sorted()
        guard !allWeekKeys.isEmpty else { return nil }

        // Build week bars
        var realBars: [WeekBar] = []
        for (idx, wk) in allWeekKeys.enumerated() {
            var segments: [WeekSegment] = []
            for pw in providerWeekly {
                if let avg = pw.weekAvgs[wk] {
                    segments.append(WeekSegment(
                        providerID: pw.id, providerName: pw.name,
                        avgPercent: avg, color: pw.color))
                }
            }
            realBars.append(WeekBar(id: idx, weekLabel: weekLabel(for: wk), segments: segments, isPadding: false))
        }

        // Right-align
        var weekBars: [WeekBar]
        if realBars.count < windowSize {
            let pad = windowSize - realBars.count
            var padded: [WeekBar] = (0 ..< pad).map { WeekBar(id: $0, weekLabel: nil, segments: [], isPadding: true) }
            for (off, bar) in realBars.enumerated() {
                padded.append(WeekBar(id: pad + off, weekLabel: bar.weekLabel, segments: bar.segments, isPadding: false))
            }
            weekBars = padded
        } else {
            weekBars = realBars
        }

        // This week avg (last week key)
        let currentWeek = weekKey(for: Date())
        let thisWeekAvgs = providerWeekly.compactMap { $0.weekAvgs[currentWeek] }
        let thisWeekAvg = thisWeekAvgs.isEmpty ? 0.0 : thisWeekAvgs.reduce(0, +) / Double(thisWeekAvgs.count)

        // Last week for delta
        let previousWeekKeys = allWeekKeys.filter { $0 < currentWeek }
        let weekOverWeekDelta: Double?
        if let lastWeek = previousWeekKeys.last {
            let lastAvgs = providerWeekly.compactMap { $0.weekAvgs[lastWeek] }
            let lastAvg = lastAvgs.isEmpty ? 0.0 : lastAvgs.reduce(0, +) / Double(lastAvgs.count)
            weekOverWeekDelta = thisWeekAvg - lastAvg
        } else {
            weekOverWeekDelta = nil
        }

        // 30-day avg: all entries from last 30 days, averaged per provider, then averaged
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        let providerThirtyDayAvgs = providerData.map { pd -> Double in
            let recent = pd.entries.filter { $0.capturedAt >= thirtyDaysAgo }
            guard !recent.isEmpty else { return 0 }
            return recent.reduce(0.0) { $0 + $1.usedPercent } / Double(recent.count)
        }
        let thirtyDayAvg = providerThirtyDayAvgs.reduce(0, +) / Double(max(providerThirtyDayAvgs.count, 1))

        // Provider breakdown (this week)
        let breakdown = providerWeekly.map { pw in
            let avg = pw.weekAvgs[currentWeek] ?? 0
            return ProviderBreakdown(id: pw.id, name: pw.name, color: pw.color, thisWeekAvg: avg)
        }

        return AggregateModel(
            weekBars: weekBars,
            providerBreakdown: breakdown,
            thisWeekAvg: thisWeekAvg,
            weekOverWeekDelta: weekOverWeekDelta,
            thirtyDayAvg: thirtyDayAvg)
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
