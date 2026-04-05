import Charts
import CodexBarSync
import SwiftUI

/// Displays subscription utilization history as a bar chart.
/// Design follows Mac-side PlanUtilizationHistoryChartMenuView:
/// - Dual-layer bars (track + fill)
/// - Hidden Y-axis, minimal X-axis
/// - Segmented series picker
/// - Detail line at bottom (not popup)
struct UtilizationHistoryView: View {
    let series: [SyncUtilizationSeries]
    let tintColor: Color

    @State private var selectedSeriesIndex = 0
    @State private var selectedEntry: SyncUtilizationEntry?

    private var activeSeries: SyncUtilizationSeries? {
        let index = min(self.selectedSeriesIndex, self.series.count - 1)
        guard index >= 0, index < self.series.count else { return nil }
        return self.series[index]
    }

    private let trackColor = Color.primary.opacity(0.08)
    private let barWidth: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header + picker
            HStack {
                Text("Subscription Utilization")
                    .font(.headline)
                Spacer()
            }

            if self.series.count > 1 {
                Picker("Series", selection: self.$selectedSeriesIndex) {
                    ForEach(Array(self.series.enumerated()), id: \.offset) { index, s in
                        Text(Self.seriesDisplayName(s)).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: self.selectedSeriesIndex) { _, _ in
                    self.selectedEntry = nil
                }
            }

            if let active = self.activeSeries, !active.entries.isEmpty {
                // Chart
                self.chartView(active)
                    .frame(height: 140)

                // Detail line (Mac-style: single line at bottom)
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

    // MARK: - Chart (Mac-style dual-layer bars)

    private func chartView(_ series: SyncUtilizationSeries) -> some View {
        Chart {
            ForEach(Array(series.entries.enumerated()), id: \.offset) { index, entry in
                // Track bar (full 100% height, subtle background)
                BarMark(
                    x: .value("Index", index),
                    yStart: .value("Start", 0),
                    yEnd: .value("End", 100),
                    width: .fixed(self.barWidth))
                    .foregroundStyle(self.trackColor)

                // Fill bar (actual utilization)
                BarMark(
                    x: .value("Index", index),
                    yStart: .value("Start", 0),
                    yEnd: .value("End", entry.usedPercent),
                    width: .fixed(self.barWidth))
                    .foregroundStyle(self.tintColor)
            }

            // Selection rule mark
            if let selected = self.selectedEntry,
               let selectedIndex = series.entries.firstIndex(where: { $0.capturedAt == selected.capturedAt })
            {
                RuleMark(x: .value("Selected", selectedIndex))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0 ... 100)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
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
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let plotOrigin = geometry[plotFrame].origin
                                let xInPlot = drag.location.x - plotOrigin.x
                                guard let idx: Int = proxy.value(atX: xInPlot),
                                      idx >= 0, idx < series.entries.count
                                else { return }
                                self.selectedEntry = series.entries[idx]
                            }
                            .onEnded { _ in
                                self.selectedEntry = nil
                            })
            }
        }
    }

    // MARK: - Detail Line (Mac-style)

    @ViewBuilder
    private func detailLine(_ series: SyncUtilizationSeries) -> some View {
        if let entry = self.selectedEntry {
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
