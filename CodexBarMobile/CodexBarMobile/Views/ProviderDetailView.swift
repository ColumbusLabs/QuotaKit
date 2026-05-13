import Charts
import CodexBarSync
import SwiftUI

struct ProviderDetailView: View {
    let provider: ProviderUsageSnapshot

    @AppStorage(MobileSettingsKeys.usageCostChartStyle) private var chartStyleRawValue = CostChartStyle.bars.rawValue
    @State private var selectedDate: String?

    private var chartStyle: CostChartStyle {
        CostChartStyle(rawValue: self.chartStyleRawValue) ?? .bars
    }

    /// True when the displayed provider holds synthetic mock data.
    /// Drives the MOCK badge in the nav header.
    private var isMockProvider: Bool {
        MockProviderDetector.isMock(self.provider)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if self.isMockProvider {
                    self.mockBanner
                }

                // Rate limit cards (or Perplexity credit breakdown when available)
                self.primaryUsageSection

                // Claude peak-hours indicator (Anthropic peak window
                // 8am-2pm America/New_York, weekdays). Pure time-of-day
                // logic in `ClaudePeakHours` — no wire field involved.
                if self.provider.providerID == "claude" {
                    self.claudePeakHoursSection
                }

                // Cost summary grid
                if let cost = self.provider.costSummary,
                   cost.sessionCostUSD != nil || cost.last30DaysCostUSD != nil
                {
                    self.costSummarySection(cost)
                }

                // Budget progress
                if let budget = self.provider.budget {
                    BudgetProgressView(budget: budget, tintColor: self.providerColor)
                }

                // Utilization history chart
                if let history = self.provider.utilizationHistory, !history.isEmpty {
                    UtilizationHistoryView(series: history, tintColor: self.providerColor)
                }

                // Daily chart
                if let cost = self.provider.costSummary, !cost.daily.isEmpty {
                    self.dailyChartSection(cost.daily)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(self.provider.providerName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if self.isMockProvider {
                ToolbarItem(placement: .topBarTrailing) {
                    MockBadgeView()
                }
            }
        }
    }

    // MARK: - Mock Detail Banner

    /// Inline banner at the top of the detail page reminding the user
    /// this provider's data is synthetic. Mirrors the global
    /// `MockProviderBanner` in spirit (so users hitting the detail page
    /// directly without seeing the global banner still understand) but
    /// scoped to this single provider.
    @ViewBuilder
    private var mockBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "testtube.2")
                .font(.subheadline.bold())
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("This is mock data")
                    .font(.caption.bold())
                Text("Synthetic provider injected by Mac for testing. Real numbers are restored ~30s after Mac toggles mock off.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.purple.opacity(0.10)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.purple.opacity(0.30), lineWidth: 1))
    }

    // MARK: - Claude Peak Hours

    /// Displays Anthropic's Claude peak window status for the current
    /// moment. Pure client-side computation in `ClaudePeakHours`
    /// (mirrors the Mac-side logic byte-for-byte; both sides use the
    /// same hardcoded window: 8am–2pm America/New_York, weekdays).
    /// Visible on the Claude provider detail page only; other providers
    /// don't render this section.
    @ViewBuilder
    private var claudePeakHoursSection: some View {
        let status = ClaudePeakHours.status(at: Date())
        HStack(spacing: 10) {
            Image(systemName: status.isPeak ? "sun.max.fill" : "moon.fill")
                .font(.subheadline)
                .foregroundStyle(status.isPeak ? .orange : .secondary)
            Text(status.label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    // MARK: - Primary usage section

    /// Chooses between the Perplexity-specialized credit card and the generic
    /// rate-window list. Perplexity ships its rich structured breakdown via
    /// `perplexityCredits` starting Mac 0.20.3 — when that field is present
    /// we render the stacked 3-segment card; otherwise (every other provider,
    /// or a pre-0.20.3 Mac client) we fall through to the generic list.
    @ViewBuilder
    private var primaryUsageSection: some View {
        if self.provider.providerID == "perplexity",
           let credits = self.provider.perplexityCredits
        {
            PerplexityCreditsCard(credits: credits, tintColor: self.providerColor)
        } else {
            self.rateLimitSection
        }
    }

    // MARK: - Rate Limits

    @ViewBuilder
    private var rateLimitSection: some View {
        let windows = self.provider.allRateWindows
        if !windows.isEmpty {
            VStack(spacing: 12) {
                ForEach(Array(windows.enumerated()), id: \.offset) { index, window in
                    UsageCardView(
                        label: window.label ?? self.defaultLabel(at: index),
                        window: window,
                        tintColor: self.providerColor,
                        percentageAccessibilityIdentifier: "provider-detail-percent-\(self.provider.providerID)-\(index)")
                }
            }
        }
    }

    // MARK: - Cost Summary

    private func costSummarySection(_ cost: SyncCostSummary) -> some View {
        // Prefer daily[today] over sessionCostUSD so the "Today" card here
        // matches what the Cost-tab summary card shows for this provider.
        // See `SyncCostSummary+Today.swift` for reasoning. Cost + tokens
        // are resolved through one `todayTotals()` call so they can't
        // straddle midnight with mismatched day keys.
        let today = cost.todayTotals()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Cost & Usage")
                .font(.headline)
                .padding(.top, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let todayCost = today.costUSD {
                    CostMetricCard(
                        title: "Today",
                        value: Self.formatUSD(todayCost),
                        subtitle: today.tokens.map { Self.formatTokens($0) },
                        tintColor: self.providerColor,
                        isEstimated: today.isEstimated == true)
                }
                if let monthCost = cost.last30DaysCostUSD {
                    CostMetricCard(
                        title: "30 Days",
                        value: Self.formatUSD(monthCost),
                        subtitle: cost.last30DaysTokens.map { Self.formatTokens($0) },
                        tintColor: self.providerColor,
                        isEstimated: cost.isEstimated == true)
                }
            }

            if today.isEstimated == true || cost.isEstimated == true {
                Text("* Estimated cost · auto-corrects after Mac upgrades to the latest pricing table")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Daily Chart

    private func dailyChartSection(_ daily: [SyncDailyPoint]) -> some View {
        // Precompute axis values once per section build. `daily` is stable across
        // `selectedDate` hover changes, so pulling this out of the `.chartYAxis`
        // closure eliminates redundant axis recomputation on every chart re-render.
        let yAxisValues = MobileChartAxisFormatter.axisValues(for: daily.map(\.costUSD))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Daily Spend")
                    .font(.headline)
                Text("(USD)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("provider-daily-spend-title")

            Chart(daily, id: \.dayKey) { point in
                switch self.chartStyle {
                case .bars:
                    BarMark(
                        x: .value(String(localized: "Date"), point.dayKey),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(self.providerColor.gradient)
                        .cornerRadius(3)
                case .line:
                    AreaMark(
                        x: .value(String(localized: "Date"), point.dayKey),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(self.providerColor.opacity(0.16))
                        .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value(String(localized: "Date"), point.dayKey),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(self.providerColor)
                        .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }

                if self.selectedDate == point.dayKey {
                    RuleMark(x: .value(String(localized: "Selected Date"), point.dayKey))
                        .foregroundStyle(self.providerColor.opacity(0.3))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value(String(localized: "Selected Date"), point.dayKey),
                        y: .value(String(localized: "Selected Cost"), point.costUSD))
                        .foregroundStyle(self.providerColor)
                        .symbolSize(80)
                }
            }
            .chartXSelection(value: self.$selectedDate)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: min(daily.count, Self.chartVisibleDays))
            .chartScrollPosition(initialX: Self.chartScrollInitialDayKey(daily: daily))
            .chartXAxis {
                AxisMarks(values: .stride(by: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(values: yAxisValues) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(MobileChartAxisFormatter.axisLabel(for: v))
                                .font(.caption2)
                        }
                    }
                }
            }
            // 200pt chart height — tuned so the Daily Spend chart fits below
            // the primary-usage / cost-summary / budget sections without
            // pushing the provider's utilization history off-screen on a
            // compact iPhone (iPhone SE 3rd gen, 667pt total height). A
            // taller chart improves readability for outliers but requires
            // the user to scroll more; 200pt is the empirically-tuned
            // balance. If increasing this, verify the page still works on
            // the smallest supported device.
            .frame(height: 200)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let selectedDate, let point = daily.first(where: { $0.dayKey == selectedDate }) {
                HStack {
                    Text(point.dayKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.formatUSD(point.costUSD))
                        .font(.caption.monospacedDigit())
                        .fontWeight(.medium)
                    Text("· \(Self.formatTokens(point.totalTokens))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Chart Constants

    private static let chartVisibleDays = 30

    private static func chartScrollInitialDayKey(daily: [SyncDailyPoint]) -> String {
        let startIndex = max(0, daily.count - chartVisibleDays)
        return daily[startIndex].dayKey
    }

    // MARK: - Helpers

    private var providerColor: Color {
        ProviderColorPalette.color(for: self.provider.providerID)
    }

    private func defaultLabel(at index: Int) -> String {
        switch index {
        case 0: String(localized: "Session")
        case 1: String(localized: "Weekly")
        default: "\(String(localized: "Limit")) \(index + 1)"
        }
    }

    static func formatUSD(_ value: Double) -> String { CostFormatting.usd(value) }
    static func formatTokens(_ count: Int) -> String { CostFormatting.tokens(count) }
}

// MARK: - Previews

#Preview("With Cost Data") {
    NavigationStack {
        ProviderDetailView(provider: PreviewData.claudeProvider)
    }
}

#Preview("No Cost Data") {
    NavigationStack {
        ProviderDetailView(provider: PreviewData.cursorProvider)
    }
}
