import Charts
import SwiftUI

// MARK: - Multi-Provider Sample Data

struct ProviderUtilData: Identifiable {
    let id: String
    let name: String
    let color: Color
    let entries: [(index: Int, usedPercent: Double)]
}

enum CostUtilSampleData {
    static let providers: [ProviderUtilData] = [
        ProviderUtilData(id: "claude", name: "Claude", color: Color(red: 0.82, green: 0.55, blue: 0.28),
                         entries: (0 ..< 20).map { ($0, Double.random(in: 30 ... 95)) }),
        ProviderUtilData(id: "codex", name: "Codex", color: .purple,
                         entries: (0 ..< 20).map { ($0, Double.random(in: 20 ... 80)) }),
        ProviderUtilData(id: "cursor", name: "Cursor", color: .blue,
                         entries: (0 ..< 20).map { ($0, Double.random(in: 10 ... 60)) }),
    ]

    static let maxPercent: Double = 300 // 3 providers × 100%
}

// MARK: - Variant 1: Stacked Bar

struct CostUtilV1_StackedBar: View {
    let providers: [ProviderUtilData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("1. Stacked Bar").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(providers) { provider in
                    ForEach(provider.entries, id: \.index) { entry in
                        BarMark(
                            x: .value("I", entry.index),
                            y: .value("V", entry.usedPercent),
                            width: .fixed(8))
                            .foregroundStyle(by: .value("Provider", provider.name))
                    }
                }
            }
            .chartForegroundStyleScale([
                "Claude": Color(red: 0.82, green: 0.55, blue: 0.28),
                "Codex": Color.purple,
                "Cursor": Color.blue,
            ])
            .chartYAxis(.hidden).chartXAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 15)
            .frame(height: 120)

            self.legendRow
        }
    }

    var legendRow: some View {
        HStack(spacing: 12) {
            ForEach(providers) { p in
                HStack(spacing: 4) {
                    Circle().fill(p.color).frame(width: 6, height: 6)
                    Text(p.name).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Variant 2: Grouped Bar

struct CostUtilV2_GroupedBar: View {
    let providers: [ProviderUtilData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("2. Grouped Bar").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(providers) { provider in
                    ForEach(provider.entries, id: \.index) { entry in
                        BarMark(
                            x: .value("I", entry.index),
                            y: .value("V", entry.usedPercent),
                            width: .fixed(4))
                            .foregroundStyle(by: .value("Provider", provider.name))
                            .position(by: .value("Provider", provider.name))
                    }
                }
            }
            .chartForegroundStyleScale([
                "Claude": Color(red: 0.82, green: 0.55, blue: 0.28),
                "Codex": Color.purple,
                "Cursor": Color.blue,
            ])
            .chartYScale(domain: 0 ... 100)
            .chartYAxis(.hidden).chartXAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 10)
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 3: Stacked Area

struct CostUtilV3_StackedArea: View {
    let providers: [ProviderUtilData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("3. Stacked Area").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(providers) { provider in
                    ForEach(provider.entries, id: \.index) { entry in
                        AreaMark(
                            x: .value("I", entry.index),
                            y: .value("V", entry.usedPercent))
                            .foregroundStyle(by: .value("Provider", provider.name))
                            .interpolationMethod(.catmullRom)
                    }
                }
            }
            .chartForegroundStyleScale([
                "Claude": Color(red: 0.82, green: 0.55, blue: 0.28).opacity(0.6),
                "Codex": Color.purple.opacity(0.6),
                "Cursor": Color.blue.opacity(0.6),
            ])
            .chartYAxis(.hidden).chartXAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 15)
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 4: Percentage Stacked

struct CostUtilV4_PercentStacked: View {
    let providers: [ProviderUtilData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("4. Percentage Stacked").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(providers) { provider in
                    ForEach(provider.entries, id: \.index) { entry in
                        let total = providers.reduce(0.0) { sum, p in
                            sum + (p.entries.first(where: { $0.index == entry.index })?.usedPercent ?? 0)
                        }
                        let normalized = total > 0 ? (entry.usedPercent / total) * 100 : 0
                        BarMark(
                            x: .value("I", entry.index),
                            y: .value("V", normalized),
                            width: .fixed(8))
                            .foregroundStyle(by: .value("Provider", provider.name))
                    }
                }
            }
            .chartForegroundStyleScale([
                "Claude": Color(red: 0.82, green: 0.55, blue: 0.28),
                "Codex": Color.purple,
                "Cursor": Color.blue,
            ])
            .chartYScale(domain: 0 ... 100)
            .chartYAxis(.hidden).chartXAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 15)
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 5: Ring Gauge

struct CostUtilV5_RingGauge: View {
    let providers: [ProviderUtilData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("5. Ring Gauge").font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ZStack {
                    ForEach(Array(providers.enumerated()), id: \.offset) { idx, provider in
                        let avg = provider.entries.reduce(0.0) { $0 + $1.usedPercent } / Double(max(provider.entries.count, 1))
                        Circle()
                            .trim(from: 0, to: avg / 100)
                            .stroke(provider.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(CGFloat(idx) * 12)
                    }
                }
                .frame(width: 100, height: 100)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(providers) { p in
                        let avg = p.entries.reduce(0.0) { $0 + $1.usedPercent } / Double(max(p.entries.count, 1))
                        HStack(spacing: 6) {
                            Circle().fill(p.color).frame(width: 8, height: 8)
                            Text(p.name).font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%%", avg)).font(.caption.bold())
                        }
                    }
                }
            }
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 6: Multi-Line

struct CostUtilV6_MultiLine: View {
    let providers: [ProviderUtilData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("6. Multi-Line Trend").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(providers) { provider in
                    ForEach(provider.entries, id: \.index) { entry in
                        LineMark(
                            x: .value("I", entry.index),
                            y: .value("V", entry.usedPercent))
                            .foregroundStyle(by: .value("Provider", provider.name))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
            }
            .chartForegroundStyleScale([
                "Claude": Color(red: 0.82, green: 0.55, blue: 0.28),
                "Codex": Color.purple,
                "Cursor": Color.blue,
            ])
            .chartYScale(domain: 0 ... 100)
            .chartYAxis(.hidden).chartXAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 15)
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 7: Heat Grid

struct CostUtilV7_HeatGrid: View {
    let providers: [ProviderUtilData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("7. Heat Grid").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(providers) { provider in
                    ForEach(provider.entries, id: \.index) { entry in
                        RectangleMark(
                            x: .value("Day", entry.index),
                            y: .value("Provider", provider.name),
                            width: .ratio(0.9),
                            height: .ratio(0.8))
                            .foregroundStyle(provider.color.opacity(entry.usedPercent / 100))
                            .cornerRadius(3)
                    }
                }
            }
            .chartYAxis(.hidden).chartXAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 15)
            .frame(height: 80)
        }
    }
}

// MARK: - Variant 8: Horizontal Stripes

struct CostUtilV8_HorizontalStripes: View {
    let providers: [ProviderUtilData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("8. Horizontal Stripes").font(.caption.bold()).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(providers) { provider in
                    let avg = provider.entries.reduce(0.0) { $0 + $1.usedPercent } / Double(max(provider.entries.count, 1))
                    HStack(spacing: 8) {
                        Text(provider.name).font(.caption2).frame(width: 50, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.06))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(provider.color)
                                    .frame(width: max(4, geo.size.width * avg / 100))
                            }
                        }
                        .frame(height: 14)
                        Text(String(format: "%.0f%%", avg)).font(.caption2.bold()).frame(width: 35, alignment: .trailing)
                    }
                }
            }
            .frame(height: 80)
        }
    }
}

// MARK: - Variant 9: Bubble Scatter

struct CostUtilV9_BubbleScatter: View {
    let providers: [ProviderUtilData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("9. Bubble Scatter").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(providers) { provider in
                    ForEach(provider.entries, id: \.index) { entry in
                        PointMark(
                            x: .value("I", entry.index),
                            y: .value("Provider", provider.name))
                            .foregroundStyle(provider.color)
                            .symbolSize(max(10, entry.usedPercent * 2))
                    }
                }
            }
            .chartYAxis(.hidden).chartXAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 15)
            .frame(height: 80)
        }
    }
}

// MARK: - Variant 10: Dashboard Summary

struct CostUtilV10_Dashboard: View {
    let providers: [ProviderUtilData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("10. Dashboard Summary").font(.caption.bold()).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                // Big number
                VStack(spacing: 2) {
                    let totalAvg = providers.reduce(0.0) { sum, p in
                        sum + p.entries.reduce(0.0) { $0 + $1.usedPercent } / Double(max(p.entries.count, 1))
                    }
                    let maxTotal = Double(providers.count) * 100
                    Text(String(format: "%.0f%%", totalAvg / maxTotal * 100))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("Overall").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(width: 80)

                // Mini stacked trend
                Chart {
                    ForEach(providers) { provider in
                        ForEach(provider.entries, id: \.index) { entry in
                            BarMark(
                                x: .value("I", entry.index),
                                y: .value("V", entry.usedPercent),
                                width: .fixed(4))
                                .foregroundStyle(by: .value("P", provider.name))
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "Claude": Color(red: 0.82, green: 0.55, blue: 0.28),
                    "Codex": Color.purple,
                    "Cursor": Color.blue,
                ])
                .chartYAxis(.hidden).chartXAxis(.hidden).chartLegend(.hidden)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 15)
            }
            .frame(height: 100)
        }
    }
}

// MARK: - All Cost Variants Gallery

struct CostUtilizationVariantsGallery: View {
    let providers = CostUtilSampleData.providers

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CostUtilV1_StackedBar(providers: providers)
                CostUtilV2_GroupedBar(providers: providers)
                CostUtilV3_StackedArea(providers: providers)
                CostUtilV4_PercentStacked(providers: providers)
                CostUtilV5_RingGauge(providers: providers)
                CostUtilV6_MultiLine(providers: providers)
                CostUtilV7_HeatGrid(providers: providers)
                CostUtilV8_HorizontalStripes(providers: providers)
                CostUtilV9_BubbleScatter(providers: providers)
                CostUtilV10_Dashboard(providers: providers)
            }
            .padding()
        }
    }
}

#Preview("Cost Utilization — 10 Variants") {
    CostUtilizationVariantsGallery()
        .preferredColorScheme(.dark)
}
