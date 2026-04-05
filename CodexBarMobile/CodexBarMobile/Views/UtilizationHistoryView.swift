import Charts
import CodexBarSync
import SwiftUI

/// Displays subscription utilization history as a capsule bar chart.
/// Design: V4 Capsule — thick rounded bars with track layer, horizontal scrolling.
struct UtilizationHistoryView: View {
    let series: [SyncUtilizationSeries]
    let tintColor: Color

    @State private var selectedSeriesIndex = 0
    @State private var selectedIndex: Int?

    private var activeSeries: SyncUtilizationSeries? {
        let index = min(self.selectedSeriesIndex, self.series.count - 1)
        guard index >= 0, index < self.series.count else { return nil }
        return self.series[index]
    }

    private let trackColor = Color.primary.opacity(0.06)
    private let barWidth: CGFloat = 10
    private let visibleBars = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subscription Utilization")
                .font(.headline)

            if self.series.count > 1 {
                Picker("Series", selection: self.$selectedSeriesIndex) {
                    ForEach(Array(self.series.enumerated()), id: \.offset) { index, s in
                        Text(Self.seriesDisplayName(s)).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: self.selectedSeriesIndex) { _, _ in
                    self.selectedIndex = nil
                }
            }

            if let active = self.activeSeries, !active.entries.isEmpty {
                self.capsuleChart(active)
                    .frame(height: 140)

                self.detailLine(active)
                    .frame(height: 16)
            } else {
                Text("No utilization data yet. Keep CodexBar running on your Mac to start recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Capsule Chart

    private func capsuleChart(_ series: SyncUtilizationSeries) -> some View {
        Chart {
            ForEach(Array(series.entries.enumerated()), id: \.offset) { index, entry in
                // Track (full height, rounded capsule look)
                BarMark(
                    x: .value("I", index),
                    yStart: .value("S", 0),
                    yEnd: .value("E", 100),
                    width: .fixed(self.barWidth))
                    .foregroundStyle(self.trackColor)
                    .cornerRadius(5)

                // Fill (actual utilization)
                BarMark(
                    x: .value("I", index),
                    yStart: .value("S", 0),
                    yEnd: .value("E", entry.usedPercent),
                    width: .fixed(self.barWidth))
                    .foregroundStyle(self.tintColor)
                    .cornerRadius(5)
            }

            if let si = self.selectedIndex, si >= 0, si < series.entries.count {
                RuleMark(x: .value("S", si))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0 ... 100)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel {
                    if let idx = value.as(Int.self), idx >= 0, idx < series.entries.count {
                        Text(Self.shortDateLabel(series.entries[idx].capturedAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: self.visibleBars)
        .chartXSelection(value: self.$selectedIndex)
    }

    // MARK: - Detail Line

    @ViewBuilder
    private func detailLine(_ series: SyncUtilizationSeries) -> some View {
        if let si = self.selectedIndex, si >= 0, si < series.entries.count {
            let entry = series.entries[si]
            HStack {
                Text(Self.fullDateLabel(entry.capturedAt))
                Spacer()
                Text(String(format: "%.0f%% used", entry.usedPercent))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            let avg = series.entries.reduce(0.0) { $0 + $1.usedPercent } / Double(max(series.entries.count, 1))
            HStack {
                Text(String(format: String(localized: "%d data points"), series.entries.count))
                Spacer()
                Text(String(format: String(localized: "Avg") + " %.0f%%", avg))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private static func seriesDisplayName(_ series: SyncUtilizationSeries) -> String {
        switch series.name {
        case "session": String(localized: "Session")
        case "weekly": String(localized: "Weekly")
        case "opus": String(localized: "Opus")
        default: series.name.capitalized
        }
    }

    private static func shortDateLabel(_ date: Date) -> String {
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
