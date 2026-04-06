import Charts
import CodexBarSync
import SwiftUI

/// Aggregate utilization dashboard for the Cost tab.
/// Shows combined session utilization across all providers with stacked bars.
struct UtilizationAggregateView: View {
    let providers: [ProviderUsageSnapshot]

    @State private var selectedIndex: Int?

    private let windowSize = 30
    private let barWidth: CGFloat = 8

    private var chartData: ChartData? {
        Self.buildChartData(from: self.providers, windowSize: self.windowSize)
    }

    var body: some View {
        if let data = self.chartData, !data.bars.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text("Subscription Utilization")
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%.0f%%", data.overallAvg))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                }

                // Stacked bar chart
                self.stackedChart(data)
                    .frame(height: 120)

                // Detail line
                self.detailLine(data)
                    .frame(height: 16)

                // Legend
                HStack(spacing: 12) {
                    ForEach(data.providerInfos, id: \.id) { info in
                        HStack(spacing: 4) {
                            Circle().fill(info.color).frame(width: 6, height: 6)
                            Text(info.name).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Chart

    private func stackedChart(_ data: ChartData) -> some View {
        Chart {
            ForEach(data.bars) { bar in
                if !bar.isPadding {
                    ForEach(bar.segments, id: \.providerID) { segment in
                        BarMark(
                            x: .value("I", bar.id),
                            y: .value("V", segment.usedPercent),
                            width: .fixed(self.barWidth))
                            .foregroundStyle(by: .value("P", segment.providerName))
                    }
                }
            }

            if let si = self.selectedIndex, si >= 0, si < data.bars.count, !data.bars[si].isPadding {
                RuleMark(x: .value("S", si))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(
            domain: data.providerInfos.map(\.name),
            range: data.providerInfos.map(\.color))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel {
                    if let idx = value.as(Int.self), idx >= 0, idx < data.bars.count,
                       let date = data.bars[idx].date
                    {
                        Text(Self.axisLabel(for: date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: 0 ... max(data.bars.count - 1, self.windowSize - 1))
        .modifier(ScrollableIfNeeded(
            dataCount: data.realBarCount,
            windowSize: self.windowSize,
            totalPoints: data.bars.count))
        .chartXSelection(value: self.$selectedIndex)
    }

    // MARK: - Detail Line

    @ViewBuilder
    private func detailLine(_ data: ChartData) -> some View {
        if let si = self.selectedIndex, si >= 0, si < data.bars.count, !data.bars[si].isPadding {
            let bar = data.bars[si]
            HStack {
                if let date = bar.date {
                    Text(Self.fullDateLabel(date))
                }
                Spacer()
                let total = bar.segments.reduce(0.0) { $0 + $1.usedPercent }
                Text(String(format: "%.0f%% total", total))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack {
                Text(String(format: "%d providers", data.providerInfos.count))
                Spacer()
                Text(String(format: "Avg %.0f%%", data.overallAvg))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Data Model

    struct ProviderInfo: Identifiable {
        let id: String
        let name: String
        let color: Color
    }

    struct BarSegment {
        let providerID: String
        let providerName: String
        let usedPercent: Double
    }

    struct Bar: Identifiable {
        let id: Int
        let date: Date?
        let segments: [BarSegment]
        let isPadding: Bool
    }

    struct ChartData {
        let bars: [Bar]
        let providerInfos: [ProviderInfo]
        let overallAvg: Double
        let realBarCount: Int
    }

    private static func buildChartData(from providers: [ProviderUsageSnapshot], windowSize: Int) -> ChartData? {
        // Get providers with utilization data
        let providerSeries = providers.compactMap { provider -> (id: String, name: String, color: Color, entries: [SyncUtilizationEntry])? in
            guard let history = provider.utilizationHistory,
                  let series = history.first(where: { $0.name == "weekly" }) ?? history.first,
                  !series.entries.isEmpty
            else { return nil }
            return (id: provider.providerID, name: provider.providerName,
                    color: Self.providerColor(for: provider.providerID),
                    entries: series.entries)
        }

        guard !providerSeries.isEmpty else { return nil }

        let providerInfos = providerSeries.map { ProviderInfo(id: $0.id, name: $0.name, color: $0.color) }
        let maxCount = providerSeries.map(\.entries.count).max() ?? 0

        // Build bars (one per time slot, stacked by provider)
        var realBars: [Bar] = []
        for i in 0 ..< maxCount {
            var segments: [BarSegment] = []
            var date: Date?
            for ps in providerSeries {
                if i < ps.entries.count {
                    let entry = ps.entries[i]
                    segments.append(BarSegment(
                        providerID: ps.id,
                        providerName: ps.name,
                        usedPercent: entry.usedPercent))
                    if date == nil { date = entry.capturedAt }
                }
            }
            realBars.append(Bar(id: i, date: date, segments: segments, isPadding: false))
        }

        // Right-align: pad left if fewer than windowSize
        var bars: [Bar]
        if realBars.count < windowSize {
            let paddingCount = windowSize - realBars.count
            var padded: [Bar] = (0 ..< paddingCount).map { i in
                Bar(id: i, date: nil, segments: [], isPadding: true)
            }
            for (offset, bar) in realBars.enumerated() {
                padded.append(Bar(id: paddingCount + offset, date: bar.date, segments: bar.segments, isPadding: false))
            }
            bars = padded
        } else {
            bars = realBars
        }

        // Calculate overall average
        let allAvgs = providerSeries.map { ps in
            ps.entries.reduce(0.0) { $0 + $1.usedPercent } / Double(ps.entries.count)
        }
        let overallAvg = allAvgs.reduce(0.0, +) / Double(max(providerSeries.count, 1))

        return ChartData(bars: bars, providerInfos: providerInfos, overallAvg: overallAvg, realBarCount: realBars.count)
    }

    // MARK: - Helpers

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

    private static func axisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private static func fullDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Conditional Scroll Modifier

private struct ScrollableIfNeeded: ViewModifier {
    let dataCount: Int
    let windowSize: Int
    let totalPoints: Int

    func body(content: Content) -> some View {
        if self.dataCount > self.windowSize {
            content
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: self.windowSize)
                .chartScrollPosition(initialX: self.totalPoints - self.windowSize)
        } else {
            content
        }
    }
}
