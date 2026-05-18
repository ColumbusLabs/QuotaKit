import Charts
import CodexBarSync
import SwiftUI

/// OpenAI Admin API usage dashboard — Today / 7d / 30d summary cards
/// + 30-day cost bar chart + top models / top line items lists.
///
/// Populated only when `ProviderUsageSnapshot.openAIAPIDashboard` is
/// non-nil (Mac 0.26.2+ on the `openai` provider, which gains the
/// inline Admin API dashboard from upstream v0.26.1).
struct OpenAIDashboardSection: View {
    let dashboard: SyncOpenAIAPIDashboard
    let tintColor: Color

    private var sortedBuckets: [SyncOpenAIDailyBucket] {
        dashboard.dailyBuckets.sorted { $0.dayKey < $1.dayKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header
            self.summaryGrid
            if !self.sortedBuckets.isEmpty {
                self.dailyChart
            }
            if !dashboard.topModels.isEmpty {
                self.topModelsSection
            }
            if !dashboard.topLineItems.isEmpty {
                self.topLineItemsSection
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("openai-dashboard-section")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(String(localized: "openai_dashboard_title", defaultValue: "OpenAI API Dashboard"))
                .font(.headline)
            Spacer()
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10)
        {
            self.summaryCard(
                title: String(localized: "openai_dashboard_today", defaultValue: "Today"),
                summary: dashboard.latestDay)
            self.summaryCard(
                title: String(localized: "openai_dashboard_7days", defaultValue: "7 Days"),
                summary: dashboard.last7Days)
            self.summaryCard(
                title: String(localized: "openai_dashboard_30days", defaultValue: "30 Days"),
                summary: dashboard.last30Days)
        }
    }

    private func summaryCard(title: String, summary: SyncOpenAISummary?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text(summary.map { Self.formatUSD($0.totalCostUSD) } ?? "—")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(self.tintColor)
            if let summary {
                Text(String(format: String(localized: "openai_dashboard_requests_format", defaultValue: "%@ req"), Self.formatCount(summary.totalRequests)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08)))
    }

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "openai_dashboard_30day_chart", defaultValue: "30-day spend"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Chart(self.sortedBuckets, id: \.dayKey) { bucket in
                BarMark(
                    x: .value("Day", bucket.dayKey),
                    y: .value("USD", bucket.costUSD))
                    .foregroundStyle(self.tintColor.gradient)
                    .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(MobileChartAxisFormatter.axisLabel(for: v))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 140)
        }
    }

    private var topModelsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "openai_dashboard_top_models", defaultValue: "Top models"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(dashboard.topModels.prefix(5), id: \.modelName) { model in
                HStack {
                    Text(model.modelName)
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(String(format: String(localized: "openai_dashboard_requests_format", defaultValue: "%@ req"), Self.formatCount(model.requests)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(Self.formatTokens(model.totalTokens))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var topLineItemsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "openai_dashboard_top_line_items", defaultValue: "Top line items"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(dashboard.topLineItems.prefix(5), id: \.name) { item in
                HStack {
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(Self.formatUSD(item.costUSD))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private static func formatUSD(_ value: Double) -> String { CostFormatting.usd(value) }
    private static func formatTokens(_ count: Int) -> String { CostFormatting.tokens(count) }
    private static func formatCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

#Preview {
    OpenAIDashboardSection(
        dashboard: SyncOpenAIAPIDashboard(
            last30Days: SyncOpenAISummary(totalCostUSD: 142.33, totalRequests: 4_201, totalTokens: 1_234_567),
            last7Days: SyncOpenAISummary(totalCostUSD: 38.50, totalRequests: 1_103, totalTokens: 312_000),
            latestDay: SyncOpenAISummary(totalCostUSD: 5.21, totalRequests: 142, totalTokens: 45_321),
            dailyBuckets: (1...30).map { day in
                SyncOpenAIDailyBucket(
                    dayKey: String(format: "2026-04-%02d", day),
                    costUSD: Double.random(in: 0.5...8.0),
                    requests: Int.random(in: 50...300),
                    inputTokens: Int.random(in: 1000...50000),
                    cachedInputTokens: Int.random(in: 0...10000),
                    outputTokens: Int.random(in: 200...10000),
                    totalTokens: Int.random(in: 1200...60000))
            },
            topModels: [
                SyncOpenAIModelBreakdown(modelName: "gpt-5", requests: 2_100, totalTokens: 800_000, costUSD: 0),
                SyncOpenAIModelBreakdown(modelName: "gpt-5.5", requests: 1_400, totalTokens: 380_000, costUSD: 0),
            ],
            topLineItems: [
                SyncOpenAILineItem(name: "Completions", costUSD: 100.40),
                SyncOpenAILineItem(name: "Embeddings", costUSD: 22.10),
            ]),
        tintColor: .green)
        .padding()
}
