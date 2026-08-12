import Charts
import CodexBarSync
import SwiftUI

/// MiniMax 30-day billing history — Today / 30-day token totals,
/// a 30-day bar chart, and top-3 method / model breakdowns. Only
/// rendered when `ProviderUsageSnapshot.minimaxBilling` is non-nil
/// (Mac has an API key and saw at least one billing record).
struct MiniMaxBillingCard: View {
    let billing: SyncMiniMaxBillingHistory
    let tintColor: Color

    private var sortedDaily: [SyncMiniMaxBillingDay] {
        self.billing.daily.sorted { $0.day < $1.day }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header
            self.summaryGrid
            if !self.sortedDaily.isEmpty {
                self.dailyChart
            }
            if !self.billing.topMethods.isEmpty {
                self.topSection(
                    title: String(localized: "minimax_billing_top_methods", defaultValue: "Top methods"),
                    rows: self.billing.topMethods)
            }
            if !self.billing.topModels.isEmpty {
                self.topSection(
                    title: String(localized: "minimax_billing_top_models", defaultValue: "Top models"),
                    rows: self.billing.topModels)
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("minimax-billing-card")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(String(localized: "minimax_billing_title", defaultValue: "30-day billing"))
                .font(.headline)
            Spacer()
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10)
        {
            self.summaryCard(
                title: String(localized: "minimax_billing_today", defaultValue: "Today"),
                tokens: self.billing.todayTokens,
                cashUSD: self.billing.todayCashUSD)
            self.summaryCard(
                title: String(localized: "minimax_billing_30days", defaultValue: "30 Days"),
                tokens: self.billing.last30DaysTokens,
                cashUSD: self.billing.last30DaysCashUSD)
        }
    }

    private func summaryCard(title: String, tokens: Int, cashUSD: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text(Self.formatTokens(tokens))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(self.tintColor)
            if let cashUSD {
                Text(Self.formatUSD(cashUSD))
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
            Text(String(localized: "minimax_billing_chart_caption", defaultValue: "30-day tokens"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Chart(self.sortedDaily) { day in
                BarMark(
                    x: .value("Day", day.day),
                    y: .value("Tokens", day.tokens))
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

    private func topSection(title: String, rows: [SyncMiniMaxBillingBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                HStack {
                    Text(row.name)
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(Self.formatTokens(row.tokens))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let cash = row.cashUSD {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(Self.formatUSD(cash))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
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
}

#Preview {
    MiniMaxBillingCard(
        billing: SyncMiniMaxBillingHistory(
            todayTokens: 142_300,
            last30DaysTokens: 4_220_000,
            todayCashUSD: 1.42,
            last30DaysCashUSD: 38.50,
            daily: (1...30).map { day in
                SyncMiniMaxBillingDay(
                    day: String(format: "2026-04-%02d", day),
                    tokens: Int.random(in: 50000...300_000),
                    cashUSD: Double.random(in: 0.5...4.0))
            },
            topMethods: [
                SyncMiniMaxBillingBreakdown(name: "chat/completions", tokens: 3_120_000, cashUSD: 28.40),
                SyncMiniMaxBillingBreakdown(name: "embeddings", tokens: 820_000, cashUSD: 6.10),
            ],
            topModels: [
                SyncMiniMaxBillingBreakdown(name: "abab-7-chat", tokens: 2_580_000, cashUSD: 23.40),
                SyncMiniMaxBillingBreakdown(name: "abab-7-instruct", tokens: 980_000, cashUSD: 9.20),
            ],
            updatedAt: Date()),
        tintColor: .pink)
        .padding()
}
