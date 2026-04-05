import Charts
import CodexBarSync
import SwiftUI

/// Displays subscription utilization history as a capsule bar chart (V4 style).
///
/// Key behavior matching Mac-side PlanUtilizationHistoryChartMenuView:
/// - Entries grouped by period boundaries (5h for session, 7d for weekly)
/// - Gaps between observed periods filled with zero-value bars
/// - Each bar = one reset window, not one raw entry
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

            if let active = self.activeSeries {
                let points = Self.buildDisplayPoints(from: active)
                if !points.isEmpty {
                    self.capsuleChart(points)
                        .frame(height: 140)
                    self.detailLine(points)
                        .frame(height: 16)
                } else {
                    self.emptyState
                }
            } else {
                self.emptyState
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        Text("No utilization data yet. Keep CodexBar running on your Mac to start recording.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
    }

    // MARK: - Build Display Points (Mac-style period grouping)

    struct DisplayPoint: Identifiable {
        let id: Int
        let date: Date
        let usedPercent: Double
        let isObserved: Bool
    }

    /// Groups raw entries into period-aligned display points.
    /// Session (windowMinutes=300): one bar per 5-hour window.
    /// Weekly (windowMinutes=10080): one bar per 7-day window.
    private static func buildDisplayPoints(from series: SyncUtilizationSeries) -> [DisplayPoint] {
        guard !series.entries.isEmpty, series.windowMinutes > 0 else { return [] }

        let windowSeconds = Double(series.windowMinutes) * 60

        // Find the latest reset boundary to build a lattice
        let latestReset = series.entries.compactMap(\.resetsAt).max()

        // Group entries by period boundary
        var bestByPeriod: [Int: (date: Date, usedPercent: Double)] = [:]

        for entry in series.entries {
            let boundary: Date
            if let reset = entry.resetsAt ?? latestReset {
                // Align to period grid based on reset time
                let diff = reset.timeIntervalSince(entry.capturedAt)
                let periodIndex = Int(floor(diff / windowSeconds))
                boundary = reset.addingTimeInterval(-Double(periodIndex) * windowSeconds)
            } else {
                // Fallback: quantize by window size from epoch
                let epoch = entry.capturedAt.timeIntervalSince1970
                let slot = floor(epoch / windowSeconds) * windowSeconds
                boundary = Date(timeIntervalSince1970: slot)
            }

            let periodKey = Int(boundary.timeIntervalSince1970 / windowSeconds)

            if let existing = bestByPeriod[periodKey] {
                // Keep the highest observed value for this period
                if entry.usedPercent > existing.usedPercent {
                    bestByPeriod[periodKey] = (date: boundary, usedPercent: entry.usedPercent)
                }
            } else {
                bestByPeriod[periodKey] = (date: boundary, usedPercent: entry.usedPercent)
            }
        }

        guard !bestByPeriod.isEmpty else { return [] }

        // Build continuous sequence with gap filling
        let sortedKeys = bestByPeriod.keys.sorted()
        let minKey = sortedKeys.first!
        let maxKey = sortedKeys.last!

        var points: [DisplayPoint] = []
        var idx = 0

        for key in minKey ... maxKey {
            if let observed = bestByPeriod[key] {
                points.append(DisplayPoint(
                    id: idx,
                    date: observed.date,
                    usedPercent: min(100, max(0, observed.usedPercent)),
                    isObserved: true))
            } else {
                // Gap: no data for this period
                let gapDate = Date(timeIntervalSince1970: Double(key) * windowSeconds)
                points.append(DisplayPoint(
                    id: idx,
                    date: gapDate,
                    usedPercent: 0,
                    isObserved: false))
            }
            idx += 1
        }

        // Limit to last 60 points to keep scrolling manageable
        if points.count > 60 {
            points = Array(points.suffix(60))
            for i in points.indices {
                points[i] = DisplayPoint(
                    id: i,
                    date: points[i].date,
                    usedPercent: points[i].usedPercent,
                    isObserved: points[i].isObserved)
            }
        }

        return points
    }

    // MARK: - Capsule Chart

    private func capsuleChart(_ points: [DisplayPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("I", point.id),
                    yStart: .value("S", 0),
                    yEnd: .value("E", 100),
                    width: .fixed(self.barWidth))
                    .foregroundStyle(self.trackColor)
                    .cornerRadius(5)

                BarMark(
                    x: .value("I", point.id),
                    yStart: .value("S", 0),
                    yEnd: .value("E", point.usedPercent),
                    width: .fixed(self.barWidth))
                    .foregroundStyle(point.isObserved ? self.tintColor : self.tintColor.opacity(0.2))
                    .cornerRadius(5)
            }

            if let si = self.selectedIndex, si >= 0, si < points.count {
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
                    if let idx = value.as(Int.self), idx >= 0, idx < points.count {
                        Text(Self.axisLabel(for: points[idx].date))
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
    private func detailLine(_ points: [DisplayPoint]) -> some View {
        if let si = self.selectedIndex, si >= 0, si < points.count {
            let point = points[si]
            HStack {
                Text(Self.fullDateLabel(point.date))
                if !point.isObserved {
                    Text("(no data)")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(String(format: "%.0f%% used", point.usedPercent))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            let observed = points.filter(\.isObserved)
            let avg = observed.reduce(0.0) { $0 + $1.usedPercent } / Double(max(observed.count, 1))
            HStack {
                Text(String(format: String(localized: "%d data points"), observed.count))
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
