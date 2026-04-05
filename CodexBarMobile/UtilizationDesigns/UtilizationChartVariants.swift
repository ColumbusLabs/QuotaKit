import Charts
import CodexBarSync
import SwiftUI

// MARK: - Sample Data

enum UtilizationSampleData {
    static let sampleEntries: [SyncUtilizationEntry] = (0 ..< 40).map { i in
        let hoursAgo = Double(40 - i) * 5
        let usage = Double.random(in: 10 ... 95)
        return SyncUtilizationEntry(
            capturedAt: Date().addingTimeInterval(-hoursAgo * 3600),
            usedPercent: usage,
            resetsAt: Date().addingTimeInterval(-hoursAgo * 3600 + 18000))
    }

    static let tintColor = Color(red: 0.82, green: 0.55, blue: 0.28) // Claude color
}

// MARK: - Variant 1: Mac Replica (dual-layer, index-based)

struct UtilVariant1_MacReplica: View {
    let entries: [SyncUtilizationEntry]
    let tintColor: Color

    @State private var selectedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("1. Mac Replica").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    BarMark(x: .value("I", index), yStart: .value("S", 0), yEnd: .value("E", 100), width: .fixed(6))
                        .foregroundStyle(Color.primary.opacity(0.08))
                    BarMark(x: .value("I", index), yStart: .value("S", 0), yEnd: .value("E", entry.usedPercent), width: .fixed(6))
                        .foregroundStyle(tintColor)
                }
                if let si = selectedIndex {
                    RuleMark(x: .value("S", si))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: 0 ... 100).chartYAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 20)
            .chartXAxis(.hidden)
            .chartXSelection(value: $selectedIndex)
            .frame(height: 120)

            self.detailLine
        }
    }

    @ViewBuilder var detailLine: some View {
        if let si = selectedIndex, si >= 0, si < entries.count {
            let e = entries[si]
            HStack {
                Text(e.capturedAt, style: .date).font(.caption2)
                Spacer()
                Text(String(format: "%.0f%% used", e.usedPercent)).font(.caption2.bold())
            }.foregroundStyle(.secondary)
        } else {
            let avg = entries.reduce(0.0) { $0 + $1.usedPercent } / Double(max(entries.count, 1))
            HStack {
                Text("\(entries.count) points").font(.caption2)
                Spacer()
                Text(String(format: "Avg %.0f%%", avg)).font(.caption2.bold())
            }.foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Variant 2: Gradient Fill

struct UtilVariant2_GradientFill: View {
    let entries: [SyncUtilizationEntry]
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("2. Gradient Fill").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    BarMark(x: .value("I", index), y: .value("V", entry.usedPercent), width: .fixed(7))
                        .foregroundStyle(tintColor.gradient)
                        .cornerRadius(3)
                }
            }
            .chartYScale(domain: 0 ... 100).chartYAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 20)
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 3: Area Line

struct UtilVariant3_AreaLine: View {
    let entries: [SyncUtilizationEntry]
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("3. Area Line").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    AreaMark(x: .value("I", index), y: .value("V", entry.usedPercent))
                        .foregroundStyle(tintColor.opacity(0.2).gradient)
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("I", index), y: .value("V", entry.usedPercent))
                        .foregroundStyle(tintColor)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartYScale(domain: 0 ... 100).chartYAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 20)
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 4: Capsule Bar

struct UtilVariant4_Capsule: View {
    let entries: [SyncUtilizationEntry]
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("4. Capsule Bar").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    BarMark(x: .value("I", index), yStart: .value("S", 0), yEnd: .value("E", 100), width: .fixed(10))
                        .foregroundStyle(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                    BarMark(x: .value("I", index), yStart: .value("S", 0), yEnd: .value("E", entry.usedPercent), width: .fixed(10))
                        .foregroundStyle(tintColor)
                        .cornerRadius(5)
                }
            }
            .chartYScale(domain: 0 ... 100).chartYAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 15)
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 5: Signal Waveform

struct UtilVariant5_Signal: View {
    let entries: [SyncUtilizationEntry]
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("5. Signal Waveform").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    BarMark(x: .value("I", index), y: .value("V", entry.usedPercent), width: .fixed(3))
                        .foregroundStyle(tintColor)
                }
            }
            .chartYScale(domain: 0 ... 100).chartYAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 30)
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 6: Heat Color Scale

struct UtilVariant6_HeatColor: View {
    let entries: [SyncUtilizationEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("6. Heat Color Scale").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    BarMark(x: .value("I", index), y: .value("V", entry.usedPercent), width: .fixed(6))
                        .foregroundStyle(Self.heatColor(for: entry.usedPercent))
                        .cornerRadius(2)
                }
            }
            .chartYScale(domain: 0 ... 100).chartYAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 20)
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
    }

    static func heatColor(for percent: Double) -> Color {
        if percent >= 80 { return .red }
        if percent >= 60 { return .orange }
        if percent >= 40 { return .yellow }
        return .green
    }
}

// MARK: - Variant 7: Dot Matrix

struct UtilVariant7_DotMatrix: View {
    let entries: [SyncUtilizationEntry]
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("7. Dot Matrix").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    PointMark(x: .value("I", index), y: .value("V", entry.usedPercent))
                        .foregroundStyle(tintColor)
                        .symbolSize(max(20, entry.usedPercent * 1.5))
                }
            }
            .chartYScale(domain: 0 ... 100).chartYAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 20)
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 8: Step Line

struct UtilVariant8_StepLine: View {
    let entries: [SyncUtilizationEntry]
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("8. Step Line").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    AreaMark(x: .value("I", index), y: .value("V", entry.usedPercent))
                        .foregroundStyle(tintColor.opacity(0.12))
                        .interpolationMethod(.stepCenter)
                    LineMark(x: .value("I", index), y: .value("V", entry.usedPercent))
                        .foregroundStyle(tintColor)
                        .interpolationMethod(.stepCenter)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartYScale(domain: 0 ... 100).chartYAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 20)
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 9: Dual Color (Used + Remaining)

struct UtilVariant9_DualColor: View {
    let entries: [SyncUtilizationEntry]
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("9. Dual Color (Used + Remaining)").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    BarMark(x: .value("I", index), yStart: .value("S", entry.usedPercent), yEnd: .value("E", 100), width: .fixed(6))
                        .foregroundStyle(Color.gray.opacity(0.2))
                    BarMark(x: .value("I", index), yStart: .value("S", 0), yEnd: .value("E", entry.usedPercent), width: .fixed(6))
                        .foregroundStyle(tintColor)
                }
            }
            .chartYScale(domain: 0 ... 100).chartYAxis(.hidden).chartLegend(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 20)
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
    }
}

// MARK: - Variant 10: Mini Spark

struct UtilVariant10_MiniSpark: View {
    let entries: [SyncUtilizationEntry]
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("10. Mini Spark").font(.caption.bold()).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 0) {
                Chart {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        BarMark(x: .value("I", index), y: .value("V", entry.usedPercent), width: .fixed(4))
                            .foregroundStyle(tintColor)
                    }
                }
                .chartYScale(domain: 0 ... 100).chartYAxis(.hidden).chartXAxis(.hidden).chartLegend(.hidden)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 30)
                .frame(height: 50)

                VStack(alignment: .trailing, spacing: 2) {
                    let avg = entries.reduce(0.0) { $0 + $1.usedPercent } / Double(max(entries.count, 1))
                    Text(String(format: "%.0f%%", avg)).font(.title3.bold()).foregroundStyle(tintColor)
                    Text("avg").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(width: 60)
            }
        }
    }
}

// MARK: - All Variants Preview

struct UtilizationVariantsGallery: View {
    let entries = UtilizationSampleData.sampleEntries
    let tint = UtilizationSampleData.tintColor

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                UtilVariant1_MacReplica(entries: entries, tintColor: tint)
                UtilVariant2_GradientFill(entries: entries, tintColor: tint)
                UtilVariant3_AreaLine(entries: entries, tintColor: tint)
                UtilVariant4_Capsule(entries: entries, tintColor: tint)
                UtilVariant5_Signal(entries: entries, tintColor: tint)
                UtilVariant6_HeatColor(entries: entries)
                UtilVariant7_DotMatrix(entries: entries, tintColor: tint)
                UtilVariant8_StepLine(entries: entries, tintColor: tint)
                UtilVariant9_DualColor(entries: entries, tintColor: tint)
                UtilVariant10_MiniSpark(entries: entries, tintColor: tint)
            }
            .padding()
        }
    }
}

#Preview("Provider Utilization — 10 Variants") {
    UtilizationVariantsGallery()
        .preferredColorScheme(.dark)
}
