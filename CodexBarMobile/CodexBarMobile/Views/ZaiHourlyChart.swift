import Charts
import CodexBarSync
import SwiftUI

/// Per-model hourly token usage chart for z.ai. Mirrors the upstream
/// menu addition from PR #913 (v0.26.0) — stacked bars where each
/// segment is a model's contribution to that hour's total.
///
/// Populated only when `ProviderUsageSnapshot.zaiHourlyUsage` is
/// non-nil (Mac 0.26.2+ on the `zai` provider).
struct ZaiHourlyChart: View {
    let usage: SyncZaiHourlyUsage
    let tintColor: Color

    /// Flattened bar points for SwiftUI Charts. Each point represents
    /// one model's tokens at one hour. A nil/zero token slot is
    /// skipped so the stacked bars don't render zero-height segments.
    private struct Point: Identifiable {
        let id: String
        let hour: Date
        let model: String
        let tokens: Int
    }

    private var points: [Point] {
        var out: [Point] = []
        for (hourIndex, hour) in usage.xTime.enumerated() {
            for series in usage.modelSeries {
                guard hourIndex < series.tokens.count else { continue }
                guard let value = series.tokens[hourIndex], value > 0 else { continue }
                out.append(Point(
                    id: "\(hour.timeIntervalSince1970)-\(series.modelName)",
                    hour: hour,
                    model: series.modelName,
                    tokens: value))
            }
        }
        return out
    }

    private var totalTokens: Int {
        usage.modelSeries.reduce(0) { acc, series in
            acc + series.tokens.compactMap(\.self).reduce(0, +)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(String(localized: "zai_hourly_chart_title", defaultValue: "Hourly token usage"))
                    .font(.headline)
                Text("(\(Self.formatTokens(self.totalTokens)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if self.points.isEmpty {
                Text(String(localized: "zai_chart_no_data", defaultValue: "No model usage in the last 24h"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                Chart(self.points) { point in
                    BarMark(
                        x: .value("Hour", point.hour, unit: .hour),
                        y: .value("Tokens", point.tokens))
                        .foregroundStyle(by: .value("Model", point.model))
                }
                .chartForegroundStyleScale(domain: usage.modelSeries.map(\.modelName))
                .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(Self.formatTokens(v))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zai-hourly-chart")
    }

    private static func formatTokens(_ count: Int) -> String {
        CostFormatting.tokens(count)
    }
}

#Preview {
    let now = Date()
    let cal = Calendar.current
    let xTime: [Date] = (0..<24).compactMap { offset in
        cal.date(byAdding: .hour, value: -23 + offset, to: now)
    }
    let series = [
        SyncZaiModelSeries(
            modelName: "glm-4.6",
            tokens: (0..<24).map { ($0 % 4 == 0) ? Int.random(in: 1000...6000) : nil }),
        SyncZaiModelSeries(
            modelName: "glm-4.6-plus",
            tokens: (0..<24).map { ($0 % 3 == 0) ? Int.random(in: 800...3000) : nil }),
    ]
    return ZaiHourlyChart(
        usage: SyncZaiHourlyUsage(xTime: xTime, modelSeries: series),
        tintColor: Color(red: 0.18, green: 0.44, blue: 0.50))
        .padding()
}
