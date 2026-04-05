import Charts
import CodexBarSync
import SwiftUI

/// Aggregate utilization dashboard for the Cost tab.
/// Design: C10 Dashboard — big summary number + mini stacked trend chart.
/// Shows combined utilization across all providers.
struct UtilizationAggregateView: View {
    let providers: [ProviderUsageSnapshot]

    private var providerData: [(name: String, color: Color, avgPercent: Double)] {
        self.providers.compactMap { provider in
            guard let history = provider.utilizationHistory,
                  let session = history.first(where: { $0.name == "session" }) ?? history.first,
                  !session.entries.isEmpty
            else { return nil }

            let avg = session.entries.reduce(0.0) { $0 + $1.usedPercent } / Double(session.entries.count)
            let color = Self.providerColor(for: provider.providerID)
            return (name: provider.providerName, color: color, avgPercent: avg)
        }
    }

    private var overallPercent: Double {
        let data = self.providerData
        guard !data.isEmpty else { return 0 }
        let total = data.reduce(0.0) { $0 + $1.avgPercent }
        let maxTotal = Double(data.count) * 100
        return total / maxTotal * 100
    }

    var body: some View {
        if !self.providerData.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Subscription Utilization")
                    .font(.headline)

                HStack(alignment: .top, spacing: 16) {
                    // Big summary number
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f%%", self.overallPercent))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("Overall")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 80)

                    // Mini stacked trend
                    self.miniStackedChart
                }

                // Legend
                self.legendRow
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Mini Stacked Chart

    private var miniStackedChart: some View {
        let allProviderEntries = self.providers.compactMap { provider -> (id: String, name: String, color: Color, entries: [SyncUtilizationEntry])? in
            guard let history = provider.utilizationHistory,
                  let session = history.first(where: { $0.name == "session" }) ?? history.first,
                  !session.entries.isEmpty
            else { return nil }
            return (id: provider.providerID, name: provider.providerName,
                    color: Self.providerColor(for: provider.providerID),
                    entries: session.entries)
        }

        let maxCount = allProviderEntries.map(\.entries.count).max() ?? 0

        return Chart {
            ForEach(allProviderEntries, id: \.id) { provider in
                ForEach(Array(provider.entries.enumerated()), id: \.offset) { index, entry in
                    BarMark(
                        x: .value("I", index),
                        y: .value("V", entry.usedPercent),
                        width: .fixed(5))
                        .foregroundStyle(by: .value("Provider", provider.name))
                }
            }
        }
        .chartForegroundStyleScale(
            domain: allProviderEntries.map(\.name),
            range: allProviderEntries.map(\.color))
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: min(maxCount, 15))
        .frame(height: 80)
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 12) {
            ForEach(self.providerData, id: \.name) { data in
                HStack(spacing: 4) {
                    Circle().fill(data.color).frame(width: 6, height: 6)
                    Text(data.name).font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%.0f%%", data.avgPercent))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Provider Colors

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
