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

    /// User-selected window from the picker. Defaults to the Mac-side
    /// `historyDays` so the displayed range matches what Mac fetched.
    /// Clamped to options actually available in `dashboard.historyDays`
    /// — picking 90 days when Mac only fetched 30 falls back to 30.
    @State private var selectedWindow: Int

    init(dashboard: SyncOpenAIAPIDashboard, tintColor: Color) {
        self.dashboard = dashboard
        self.tintColor = tintColor
        let defaultWindow = Self.snapToOption(
            dashboard.historyDays,
            availableMax: dashboard.historyDays)
        self._selectedWindow = State(initialValue: defaultWindow)
    }

    private static let windowOptions = [7, 30, 90, 180, 365]

    /// Options that fit inside Mac's fetched window — we never offer a
    /// window larger than what Mac actually has data for, so the
    /// picker never shows phantom days.
    private var availableWindowOptions: [Int] {
        Self.windowOptions.filter { $0 <= self.dashboard.historyDays }
    }

    private var effectiveWindow: Int {
        Self.snapToOption(
            self.selectedWindow,
            availableMax: self.dashboard.historyDays)
    }

    private static func snapToOption(_ desired: Int, availableMax: Int) -> Int {
        let allowed = Self.windowOptions.filter { $0 <= availableMax }
        if allowed.contains(desired) { return desired }
        return allowed.last ?? availableMax
    }

    private var sortedBuckets: [SyncOpenAIDailyBucket] {
        let buckets = self.dashboard.dailyBuckets.sorted { $0.dayKey < $1.dayKey }
        return Array(buckets.suffix(self.effectiveWindow))
    }

    /// Cost summary for the selected window, derived from the filtered
    /// `sortedBuckets`. Falls back to the Mac-side last30/last7
    /// pre-aggregates when the window matches exactly so the displayed
    /// totals match Mac's menu bar.
    private var selectedWindowSummary: SyncOpenAISummary {
        switch self.effectiveWindow {
        case 7: return self.dashboard.last7Days
        case 30: return self.dashboard.last30Days
        default:
            let buckets = self.sortedBuckets
            return SyncOpenAISummary(
                totalCostUSD: buckets.reduce(0) { $0 + $1.costUSD },
                totalRequests: buckets.reduce(0) { $0 + $1.requests },
                totalTokens: buckets.reduce(0) { $0 + $1.totalTokens })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header
            self.summaryGrid
            if !self.sortedBuckets.isEmpty {
                self.dailyChart
            }
            if !self.dashboard.topModels.isEmpty {
                self.topModelsSection
            }
            if !self.dashboard.topLineItems.isEmpty {
                self.topLineItemsSection
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("openai-dashboard-section")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(String(localized: "openai_dashboard_title", defaultValue: "OpenAI API Dashboard"))
                .font(.headline)
            Spacer()
            if self.availableWindowOptions.count >= 2 {
                Menu {
                    ForEach(self.availableWindowOptions, id: \.self) { days in
                        Button {
                            self.selectedWindow = days
                        } label: {
                            HStack {
                                Text(Self.windowLabel(days: days))
                                if days == self.effectiveWindow {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(Self.windowLabel(days: self.effectiveWindow))
                            .font(.caption.bold())
                            .foregroundStyle(self.tintColor)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(self.tintColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(self.tintColor.opacity(0.12)))
                }
                .accessibilityIdentifier("openai-dashboard-window-picker")
            }
        }
    }

    private static func windowLabel(days: Int) -> String {
        if days == 1 {
            return String(localized: "openai_window_today", defaultValue: "Today")
        }
        return String(format: String(localized: "openai_window_days_format", defaultValue: "%dd"), days)
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10)
        {
            self.summaryCard(
                title: String(localized: "openai_dashboard_today", defaultValue: "Today"),
                summary: self.dashboard.latestDay)
            self.summaryCard(
                title: String(localized: "openai_dashboard_7days", defaultValue: "7 Days"),
                summary: self.dashboard.last7Days)
            self.summaryCard(
                title: String(localized: "openai_dashboard_30days", defaultValue: "30 Days"),
                summary: self.dashboard.last30Days)
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
                Text(String(
                    format: String(localized: "openai_dashboard_requests_format", defaultValue: "%@ req"),
                    Self.formatCount(summary.totalRequests)))
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
            Text(String(
                format: String(localized: "openai_dashboard_window_chart_format", defaultValue: "Last %d days spend"),
                self.effectiveWindow))
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
            ForEach(self.dashboard.topModels.prefix(5), id: \.modelName) { model in
                HStack {
                    Text(model.modelName)
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(String(
                        format: String(localized: "openai_dashboard_requests_format", defaultValue: "%@ req"),
                        Self.formatCount(model.requests)))
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
            ForEach(self.dashboard.topLineItems.prefix(5), id: \.name) { item in
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

    private static func formatUSD(_ value: Double) -> String {
        CostFormatting.usd(value)
    }

    private static func formatTokens(_ count: Int) -> String {
        CostFormatting.tokens(count)
    }

    private static func formatCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

#Preview {
    OpenAIDashboardSection(
        dashboard: SyncOpenAIAPIDashboard(
            last30Days: SyncOpenAISummary(totalCostUSD: 142.33, totalRequests: 4201, totalTokens: 1_234_567),
            last7Days: SyncOpenAISummary(totalCostUSD: 38.50, totalRequests: 1103, totalTokens: 312_000),
            latestDay: SyncOpenAISummary(totalCostUSD: 5.21, totalRequests: 142, totalTokens: 45321),
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
                SyncOpenAIModelBreakdown(modelName: "gpt-5", requests: 2100, totalTokens: 800_000, costUSD: 0),
                SyncOpenAIModelBreakdown(modelName: "gpt-5.5", requests: 1400, totalTokens: 380_000, costUSD: 0),
            ],
            topLineItems: [
                SyncOpenAILineItem(name: "Completions", costUSD: 100.40),
                SyncOpenAILineItem(name: "Embeddings", costUSD: 22.10),
            ]),
        tintColor: .green)
        .padding()
}
