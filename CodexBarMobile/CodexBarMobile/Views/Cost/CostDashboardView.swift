import Charts
import CodexBarSync
import Foundation
import SwiftUI

struct CostDashboardView: View {
    @Environment(\.quotaKitTheme) private var theme
    let insights: CostDashboardInsights
    let usageData: SyncedUsageData
    let isDemoMode: Bool
    @AppStorage(MobileSettingsKeys.dashboardCostChartStyle) private var chartStyleRawValue = CostChartStyle.line
        .rawValue
    @State private var selectedDay: Date?

    private var chartStyle: CostChartStyle {
        CostChartStyle(rawValue: self.chartStyleRawValue) ?? .line
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if self.isDemoMode {
                    DemoPreviewBanner(snapshot: self.usageData.snapshot)
                }
                self.summarySection

                if !self.insights.providerRows.isEmpty {
                    self.contributionSection(
                        title: "Provider Share",
                        subtitle: "30-day spend contribution across synced providers.",
                        accessibilityIdentifier: "cost-dashboard-section-provider-share",
                        rows: self.insights.providerRows.map {
                            // `identityOverride: $0.id` carries the
                            // `providerID|accountEmail` composite key so
                            // multi-account scenarios (e.g. two Codex
                            // accounts surfaced by Mac ≥ 0.25 once email
                            // extraction lands) render as distinct rows
                            // instead of one row drawn twice.
                            CostBreakdownRow(
                                label: $0.provider.providerName,
                                amountUSD: $0.thirtyDayCost,
                                subtitle: self.providerSubtitle(for: $0),
                                color: providerTint(for: $0.provider),
                                brandProviderID: $0.provider.providerID,
                                identityOverride: $0.id)
                        },
                        total: self.insights.total30DayCost)
                }

                if !self.insights.dailyPoints.isEmpty {
                    self.trendSection
                }

                // Subscription Utilization — independent section
                if let snapshot = self.usageData.snapshot {
                    UtilizationAggregateView(
                        providers: MockProviderDetector.filteredProviders(from: snapshot))
                        .padding(.top, 4)
                }

                if !self.insights.modelRows.isEmpty {
                    self.contributionSection(
                        title: "Model Mix",
                        subtitle: "Top cost drivers across providers that expose model-level billing.",
                        accessibilityIdentifier: "cost-dashboard-section-model-mix",
                        rows: self.insights.modelRows,
                        total: self.insights.modelRows.reduce(0) { $0 + $1.amountUSD })
                }

                if !self.insights.serviceRows.isEmpty {
                    self.contributionSection(
                        title: "Codex Service Mix",
                        subtitle: "Breakdown from Codex Cloud dashboard data, including Codex Run and other billable services.",
                        accessibilityIdentifier: "cost-dashboard-section-service-mix",
                        rows: self.insights.serviceRows,
                        total: self.insights.serviceRows.reduce(0) { $0 + $1.amountUSD })
                }

                if !self.insights.budgetRows.isEmpty {
                    self.budgetSection
                }

                SyncStatusChipView(
                    placement: .footer,
                    isDemoMode: self.isDemoMode,
                    snapshot: self.usageData.snapshot,
                    syncStatus: self.usageData.syncStatus,
                    refreshAction: self.isDemoMode ? nil : {
                        Task { await self.usageData.refresh() }
                    })
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(self.theme.canvas)
        .refreshable {
            await self.usageData.refresh()
        }
        .modifier(SoftScrollEdgeModifier())
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            QKSectionHeader(title: "Overview")
                .padding(.top, 4)

            CostHeroStrip(
                total30DayCost: Self.formatUSD(self.insights.total30DayCost),
                tokenSubtitle: self.insights.total30DayTokens > 0
                    ? Self.formatTokens(self.insights.total30DayTokens)
                    : String(localized: "No token data"),
                todayValue: Self.formatUSD(self.insights.totalTodayCost),
                todaySubtitle: self.providersActiveSubtitle,
                topDriverValue: Self.formatUSD(self.insights.topProvider?.thirtyDayCost ?? 0),
                topDriverSubtitle: self.topDriverSubtitle ?? String(localized: "No data"),
                activeDaysValue: "\(self.insights.activeDayCount)",
                activeDaysSubtitle: self.activeDaySubtitle ?? String(localized: "No active days"))
        }
    }

    /// Visible window on the Cost-tab daily-spend chart. 30 days is the user's
    /// cost-cycle mental model (monthly bills, budget windows) and matches
    /// `UtilizationAggregateView.windowSize` + `UtilizationHistoryView.windowSize`
    /// so every chart in the app tells the same 30-day story. This is the
    /// *maximum* on-screen viewport — `visibleDayCount` caps the visible window
    /// here, and the rest of a longer CWL window (50 / 90 / 365) scrolls
    /// horizontally instead of cramming every day into one screen.
    private static let chartVisibleDays: Int = 30

    /// Leading edge of the initial visible window, placed so the newest point
    /// sits at the right edge for whatever `visibleDayCount` is active. Must
    /// use `visibleDayCount`, not the static 30 — on a wider CWL window a
    /// 30-day anchor would scroll the viewport past the data into empty future
    /// space and hide the older days until the user scrolls back manually.
    private var chartScrollInitialDate: Date {
        guard let last = self.insights.dailyPoints.last?.date else { return Date() }
        return Calendar.current.date(
            byAdding: .day, value: -(self.visibleDayCount - 1), to: last) ?? last
    }

    /// Visible width of the daily-spend chart, in days — the on-screen *viewport*,
    /// NOT the data span. Capped at `chartVisibleDays` (30) so bars stay readable;
    /// the full accumulated history (e.g. a 50/90-day CWL window) scrolls
    /// horizontally via `.chartScrollableAxes`. With fewer than 30 days of data the
    /// window shrinks to the span so the chart isn't padded with empty space.
    /// (Previously this widened to the span — which crammed 50+ overlapping,
    /// non-scrollable bars into one screen; see the cost-chart scroll fix.)
    private var visibleDayCount: Int {
        let points = self.insights.dailyPoints
        guard let first = points.first?.date, let last = points.last?.date else {
            return Self.chartVisibleDays
        }
        let span = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        return min(Self.chartVisibleDays, span + 1)
    }

    /// Axis label stride in days — weekly for short windows, coarser for long
    /// ones so a 90- or 365-day chart doesn't cram a label every 7 days.
    private var axisStrideDays: Int {
        switch self.visibleDayCount {
        case ...35: 7
        case ...100: 14
        case ...200: 30
        default: 60
        }
    }

    /// Locale-independent "M/d" formatter (e.g. "4/18"), matching
    /// UtilizationHistoryView's axis style. Avoids `.dateTime` which rearranges
    /// to "d/M" on en_GB and similar locales.
    ///
    /// Static cached instance: this runs per axis label per chart re-render,
    /// and `chartXSelection` scrubbing re-renders every drag frame — a fresh
    /// `DateFormatter()` per call put allocator + locale-load work on the
    /// 60 Hz scrub path. Read-only after configuration and only touched from
    /// view-body rendering (main actor), same contract as
    /// `CostLedgerService.utcDayKeyFormatter`.
    private static let dailyAxisLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private static func dailyAxisLabel(for date: Date) -> String {
        self.dailyAxisLabelFormatter.string(from: date)
    }

    private var trendSection: some View {
        // Precompute axis values once per trendSection build. The input is `insights.dailyPoints`
        // which is stable across hover (`selectedDay`) changes, so we avoid recomputing
        // `axisValues(for:)` on every chart re-render triggered by selection.
        let yAxisValues = MobileChartAxisFormatter.axisValues(for: self.insights.dailyPoints.map(\.costUSD))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Daily Spend")
                    .font(.headline)
                    .foregroundStyle(self.theme.textPrimary)
                Text("(USD)")
                    .font(.subheadline)
                    .foregroundStyle(self.theme.textMuted)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("cost-dashboard-daily-spend-title")

            Chart(self.insights.dailyPoints) { point in
                switch self.chartStyle {
                case .bars:
                    BarMark(
                        x: .value(String(localized: "Date"), point.date),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(self.theme.spendWarm.gradient)
                        .cornerRadius(4)
                case .line:
                    AreaMark(
                        x: .value(String(localized: "Date"), point.date),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [self.theme.spendWarm.opacity(0.35), self.theme.spendWarm.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom))
                        .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value(String(localized: "Date"), point.date),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(self.theme.spendWarm)
                        .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }

                if let selectedPoint = self.selectedPoint, selectedPoint.id == point.id {
                    RuleMark(x: .value(String(localized: "Selected Date"), selectedPoint.date))
                        .foregroundStyle(self.theme.spendWarm.opacity(0.35))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value(String(localized: "Selected Date"), selectedPoint.date),
                        y: .value(String(localized: "Selected Cost"), selectedPoint.costUSD))
                        .foregroundStyle(self.theme.spendWarm)
                        .symbolSize(80)
                }
            }
            .chartXSelection(value: self.$selectedDay)
            .chartScrollableAxes(.horizontal)
            // No extra right-side padding — axis labels use anchor .topTrailing
            // below so the label extends LEFT of the tick (slash just left of
            // the rightmost bar), matching UtilizationHistoryView's style.
            // The latest data is always on the right, so left-anchored labels
            // never clip regardless of how close the last bar is to the edge.
            .chartXVisibleDomain(length: self.visibleDayCount * 24 * 60 * 60)
            .chartScrollPosition(initialX: self.chartScrollInitialDate)
            .chartXAxis {
                // Adaptive weekly→monthly stride (see `axisStrideDays`): a
                // 30-day window keeps the 7-day cadence that matches the
                // share-card's 7-day chart, while 90/365-day windows widen the
                // stride so labels don't crowd. Density scales with the CWL
                // window the user picked.
                AxisMarks(values: .stride(by: .day, count: self.axisStrideDays)) { value in
                    AxisGridLine()
                    // Hard-coded "M/d" (locale-independent, same as
                    // UtilizationHistoryView). Anchor `.top` centers the label
                    // horizontally on the gridline — default axis anchor is
                    // `.topLeading` which extends the label to the right of the
                    // tick (what the user saw as 'wrong-side padding').
                    AxisValueLabel(anchor: .top) {
                        if let date = value.as(Date.self) {
                            Text(Self.dailyAxisLabel(for: date))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: yAxisValues) {
                    value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(MobileChartAxisFormatter.axisLabel(for: v))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 220)
            .padding(16)
            .background(self.theme.chartPlot, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(self.theme.border, lineWidth: 1)
            }

            if let selectedPoint = self.selectedPoint {
                HStack {
                    Text(Self.shortDate(selectedPoint.date))
                        .font(.caption)
                        .foregroundStyle(self.theme.textMuted)
                    Spacer()
                    Text(Self.formatUSD(selectedPoint.costUSD))
                        .font(.caption.monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundStyle(self.theme.textPrimary)
                    if selectedPoint.totalTokens > 0 {
                        Text("· \(Self.formatTokens(selectedPoint.totalTokens))")
                            .font(.caption)
                            .foregroundStyle(self.theme.textMuted)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(self.theme.surfaceElevated, in: Capsule())
            } else {
                HStack(spacing: 12) {
                    Label(
                        "\(String(localized: "Peak")) \(Self.formatUSD(self.insights.highestDay?.costUSD ?? 0))",
                        systemImage: "arrow.up.right.circle.fill")
                    Label(
                        self.insights.highestDay.map { Self.shortDate($0.date) } ?? String(localized: "No data"),
                        systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(self.theme.textMuted)
            }
        }
    }

    private func contributionSection(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        accessibilityIdentifier: String,
        rows: [CostBreakdownRow],
        total: Double) -> some View
    {
        // iOS 1.9.0+: cap to top 5 + an "Others" row whenever there are 6 or
        // more entries; otherwise show all (a section with 3 real rows just
        // shows 3 — no Others fold below the 6-item threshold). The Others
        // row is wrapped in a NavigationLink that drills into a full list
        // with the same row style. Same cap automatically covers Provider
        // Share, Model Mix, and Codex Service Mix since all three call into
        // this function. Replaces the prior `prefix(6) without Others` which
        // silently dropped low-cost providers (e.g. Mistral at $0.85 in mock
        // would vanish behind 6 higher spenders even though it contributed
        // to the headline 30-day total).
        let cap = 5
        let usesOthers = rows.count >= cap + 1
        let visible: [CostBreakdownRow] = usesOthers ? Array(rows.prefix(cap)) : rows
        let tail: [CostBreakdownRow] = usesOthers ? Array(rows.dropFirst(cap)) : []
        let tailAmount = tail.reduce(0) { $0 + $1.amountUSD }

        return VStack(alignment: .leading, spacing: 10) {
            QKSectionHeader(title: title, subtitle: subtitle)
                .padding(.top, 4)

            VStack(spacing: 12) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                    CostBreakdownRowView(row: row, total: total, rank: index + 1)
                }
                if usesOthers {
                    NavigationLink {
                        FullBreakdownListView(
                            title: title,
                            rows: rows,
                            total: total)
                    } label: {
                        OthersBreakdownRowView(
                            count: tail.count,
                            amountUSD: tailAmount,
                            total: total)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var budgetSection: some View {
        // iOS 1.9.0+: cap to top 5 + Others when 6 or more budgets exist;
        // otherwise show all. Same rule as the contribution lists. The Others
        // row has no aggregate metric (summing budgets with different limits /
        // currencies isn't meaningful) — just the count + a chevron, tappable
        // → drills into a FullBudgetListView showing every budget.
        let cap = 5
        let rows = self.insights.budgetRows
        let usesOthers = rows.count >= cap + 1
        let visible: [CostBudgetRow] = usesOthers ? Array(rows.prefix(cap)) : rows
        let tailCount = usesOthers ? rows.count - cap : 0

        return VStack(alignment: .leading, spacing: 10) {
            Text("Budgets")
                .font(.headline)
                .padding(.top, 4)

            Text("Tracked provider budgets and how close they are to their current limit.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(visible) { row in
                    BudgetRowView(row: row)
                }
                if usesOthers {
                    NavigationLink {
                        FullBudgetListView(rows: rows)
                    } label: {
                        OthersBudgetRowView(count: tailCount)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func providerSubtitle(for row: CostDashboardInsights.ProviderRow) -> String {
        let today = row.todayCost > 0
            ? "\(String(localized: "Today")) \(Self.formatUSD(row.todayCost))"
            : String(localized: "No spend today")
        let tokens = row.thirtyDayTokens > 0 ? Self
            .formatTokens(row.thirtyDayTokens) : String(localized: "No token data")
        return "\(today) · \(tokens)"
    }

    private var topDriverSubtitle: String? {
        guard let topProvider = self.insights.topProvider else { return nil }
        return "\(topProvider.provider.providerName) · \(Self.formatShare(topProvider.thirtyDayCost, total: self.insights.total30DayCost))"
    }

    private var activeDaySubtitle: String? {
        guard self.insights.activeDayCount > 0 else { return nil }
        let average = self.insights.total30DayCost / Double(self.insights.activeDayCount)
        return "\(String(localized: "Avg")) \(Self.formatUSD(average)) \(String(localized: "per active day"))"
    }

    private var providersActiveSubtitle: String {
        "\(self.insights.providerRows.count(where: { $0.todayCost > 0 }).formatted()) \(String(localized: "providers active"))"
    }

    private var selectedPoint: CostDashboardInsights.DailyPoint? {
        guard let selectedDay else { return nil }
        return self.insights.dailyPoints.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDay)
        })
    }

    private static func safeRatio(_ value: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    private static func formatShare(_ value: Double, total: Double) -> String {
        guard total > 0 else { return "0%" }
        return String(format: "%.0f%%", (value / total) * 100)
    }

    private static func formatUSD(_ value: Double) -> String {
        CostFormatting.usd(value)
    }

    private static func formatTokens(_ count: Int) -> String {
        CostFormatting.tokens(count)
    }

    private static func shortDate(_ value: Date) -> String {
        value.formatted(.dateTime.month(.abbreviated).day())
    }
}
