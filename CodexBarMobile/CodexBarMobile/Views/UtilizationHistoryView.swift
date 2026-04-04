import Charts
import CodexBarSync
import SwiftUI

/// Displays subscription utilization history as a bar chart.
/// Shows session/weekly usage percentage over time.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Subscription Utilization")
                    .font(.headline)
                Spacer()
                if self.series.count > 1 {
                    self.seriesPicker
                }
            }

            if let active = self.activeSeries, !active.entries.isEmpty {
                self.chartView(active)
                    .frame(height: 180)

                if let selected = self.selectedEntry {
                    self.detailRow(selected, windowMinutes: active.windowMinutes)
                } else {
                    self.summaryRow(active)
                }
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

    // MARK: - Series Picker

    private var seriesPicker: some View {
        Menu {
            ForEach(Array(self.series.enumerated()), id: \.offset) { index, s in
                Button {
                    self.selectedSeriesIndex = index
                    self.selectedEntry = nil
                } label: {
                    Label(Self.seriesDisplayName(s), systemImage: self.selectedSeriesIndex == index ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let active = self.activeSeries {
                    Text(Self.seriesDisplayName(active))
                        .font(.subheadline)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Chart

    private func chartView(_ series: SyncUtilizationSeries) -> some View {
        Chart {
            ForEach(Array(series.entries.enumerated()), id: \.offset) { _, entry in
                BarMark(
                    x: .value("Time", entry.capturedAt),
                    y: .value("Used %", entry.usedPercent))
                    .foregroundStyle(self.barColor(for: entry.usedPercent))
                    .cornerRadius(2)
            }
        }
        .chartYScale(domain: 0 ... 100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.shortDateLabel(date))
                            .font(.caption2)
                    }
                }
            }
        }
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
                                guard let date: Date = proxy.value(atX: xInPlot) else { return }
                                self.selectedEntry = Self.nearestEntry(to: date, in: series.entries)
                            }
                            .onEnded { _ in
                                self.selectedEntry = nil
                            })
            }
        }
    }

    // MARK: - Detail / Summary

    private func detailRow(_ entry: SyncUtilizationEntry, windowMinutes: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.fullDateLabel(entry.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reset = entry.resetsAt {
                    Text(String(format: String(localized: "Resets %@"), Self.relativeTime(reset)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(String(format: "%.0f%%", entry.usedPercent))
                .font(.title2.bold())
                .foregroundStyle(self.barColor(for: entry.usedPercent))
        }
    }

    private func summaryRow(_ series: SyncUtilizationSeries) -> some View {
        HStack {
            let avg = series.entries.reduce(0.0) { $0 + $1.usedPercent } / Double(max(series.entries.count, 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "%d data points"), series.entries.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Press and hold to inspect"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(localized: "Avg"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", avg))
                    .font(.headline)
                    .foregroundStyle(self.barColor(for: avg))
            }
        }
    }

    // MARK: - Helpers

    private func barColor(for percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return self.tintColor
    }

    private static func seriesDisplayName(_ series: SyncUtilizationSeries) -> String {
        switch series.name {
        case "session": String(localized: "Session")
        case "weekly": String(localized: "Weekly")
        case "opus": String(localized: "Opus")
        default: series.name.capitalized
        }
    }

    private static func nearestEntry(to date: Date, in entries: [SyncUtilizationEntry]) -> SyncUtilizationEntry? {
        entries.min(by: { abs($0.capturedAt.timeIntervalSince(date)) < abs($1.capturedAt.timeIntervalSince(date)) })
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

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
