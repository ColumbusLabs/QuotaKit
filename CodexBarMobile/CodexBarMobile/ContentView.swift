import Charts
import CodexBarSync
import SwiftUI

enum CostChartStyle: String, CaseIterable, Identifiable {
    case bars
    case line

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .bars:
            String(localized: "Bar Chart")
        case .line:
            String(localized: "Line Chart")
        }
    }
}

private enum MobileRootTab: Hashable {
    case usage
    case cost
    case settings
}

struct ContentView: View {
    let usageData: SyncedUsageData
    @State private var isDemoMode = false
    @State private var selectedTab: MobileRootTab
    @AppStorage("onboardingSeenVersion") private var onboardingSeenVersion = ""

    init(usageData: SyncedUsageData) {
        self.usageData = usageData
        _selectedTab = State(initialValue: UserDefaults.standard.bool(forKey: MobileSettingsKeys.openCostByDefault) ? .cost : .usage)
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var shouldShowOnboarding: Bool {
        self.onboardingSeenVersion != self.currentVersion
    }

    var body: some View {
        TabView(selection: self.$selectedTab) {
            UsageTab(usageData: self.usageData, isDemoMode: self.$isDemoMode)
                .tag(MobileRootTab.usage)
                .tabItem {
                    Label("Usage", systemImage: "chart.bar.fill")
                }

            CostTab(usageData: self.usageData, isDemoMode: self.$isDemoMode)
                .tag(MobileRootTab.cost)
                .tabItem {
                    Label("Cost", systemImage: "dollarsign.circle.fill")
                }

            SettingsTab(usageData: self.usageData)
                .tag(MobileRootTab.settings)
                .tabItem {
                    Label("Setting", systemImage: "gearshape")
                }
        }
        .modifier(TabBarMinimizeModifier())
        .fullScreenCover(isPresented: .init(
            get: { self.shouldShowOnboarding },
            set: { if !$0 { self.onboardingSeenVersion = self.currentVersion } }))
        {
            OnboardingSheet(onDismiss: {
                self.onboardingSeenVersion = self.currentVersion
            }, onDemo: {
                self.onboardingSeenVersion = self.currentVersion
                self.isDemoMode = true
            })
        }
    }
}

private struct OnboardingSheet: View {
    let onDismiss: () -> Void
    let onDemo: () -> Void

    var body: some View {
        NavigationStack {
            OnboardingView(onDemo: self.onDemo)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            self.onDismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}

/// Keeps the tab bar always visible (no auto-minimize on scroll).
private struct TabBarMinimizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}

// MARK: - Usage Tab

private struct UsageTab: View {
    let usageData: SyncedUsageData
    @Binding var isDemoMode: Bool

    private var displaySnapshot: SyncedUsageSnapshot? {
        if self.isDemoMode {
            return PreviewData.sampleSnapshot
        }
        return self.usageData.snapshot
    }

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = self.displaySnapshot {
                    if snapshot.providers.isEmpty {
                        EmptyStateView(
                            title: "No Providers Enabled",
                            message: "Enable providers in CodexBar on your Mac to see usage data here.",
                            systemImage: "slider.horizontal.3")
                    } else {
                        ProviderListView(
                            snapshot: snapshot,
                            usageData: self.usageData,
                            isDemoMode: self.isDemoMode)
                    }
                } else {
                    OnboardingView(onDemo: { self.isDemoMode = true })
                }
            }
            .navigationTitle(self.isDemoMode ? String(localized: "CodexBar (Demo)") : String(localized: "CodexBar"))
            .toolbar {
                if self.isDemoMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            self.isDemoMode = false
                        } label: {
                            Text("Exit Demo")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Provider List

private struct ProviderListView: View {
    let snapshot: SyncedUsageSnapshot
    let usageData: SyncedUsageData
    let isDemoMode: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(self.snapshot.providers, id: \.providerID) { provider in
                    NavigationLink {
                        ProviderDetailView(provider: provider)
                    } label: {
                        ProviderUsageView(provider: provider)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("provider-card-\(provider.providerID)")
                }

                // Sync status at scroll bottom
                if self.isDemoMode {
                    Label("Showing demo data", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    SyncStatusBar(usageData: self.usageData)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            await self.usageData.refresh()
        }
        .modifier(SoftScrollEdgeModifier())
    }
}

/// Applies `.scrollEdgeEffectStyle(.soft)` on iOS 26+, no-op on older systems.
private struct SoftScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

// MARK: - Sync Status Bar

private struct SyncStatusBar: View {
    let usageData: SyncedUsageData

    var body: some View {
        VStack(spacing: 4) {
            if let snapshot = self.usageData.snapshot {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(snapshot.syncTimestamp.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("Data pushed by Mac · Pull to check for updates")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
    }
}

// MARK: - Cost Tab

private struct CostTab: View {
    let usageData: SyncedUsageData
    @Binding var isDemoMode: Bool
    @State private var showShareSheet = false

    private var displaySnapshot: SyncedUsageSnapshot? {
        if self.isDemoMode {
            return PreviewData.sampleSnapshot
        }
        return self.usageData.snapshot
    }

    private var currentInsights: CostDashboardInsights? {
        guard let snapshot = self.displaySnapshot else { return nil }
        let insights = CostDashboardInsights(snapshot: snapshot)
        return insights.hasDisplayData ? insights : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = self.displaySnapshot {
                    let insights = CostDashboardInsights(snapshot: snapshot)
                    if insights.hasDisplayData {
                        CostDashboardView(
                            insights: insights,
                            usageData: self.usageData,
                            isDemoMode: self.isDemoMode)
                    } else {
                        EmptyStateView(
                            title: "No Cost Data Yet",
                            message: "Enable cost collection in CodexBar on your Mac to see provider spend, breakdowns, and budgets here.",
                            systemImage: "dollarsign.gauge.chart.lefthalf.righthalf")
                    }
                } else {
                    OnboardingView(onDemo: { self.isDemoMode = true })
                }
            }
            .navigationTitle(self.isDemoMode ? String(localized: "Cost (Demo)") : String(localized: "Cost"))
            .toolbar {
                if self.isDemoMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            self.isDemoMode = false
                        } label: {
                            Text("Exit Demo")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
                if self.currentInsights != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            self.showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let insights = self.currentInsights {
                    CostShareSheet(insights: insights)
                }
            }
        }
    }
}

private struct CostDashboardView: View {
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
                self.summarySection

                if !self.insights.providerRows.isEmpty {
                    self.contributionSection(
                        title: "Provider Share",
                        subtitle: "30-day spend contribution across synced providers.",
                        rows: self.insights.providerRows.map {
                            CostBreakdownRow(
                                label: $0.provider.providerName,
                                amountUSD: $0.thirtyDayCost,
                                subtitle: self.providerSubtitle(for: $0),
                                color: providerTint(for: $0.provider))
                        },
                        total: self.insights.total30DayCost)
                }

                if !self.insights.dailyPoints.isEmpty {
                    self.trendSection
                }

                // Subscription Utilization — independent section
                if let snapshot = self.usageData.snapshot {
                    UtilizationAggregateView(providers: snapshot.providers)
                        .padding(.top, 4)
                }

                if !self.insights.modelRows.isEmpty {
                    self.contributionSection(
                        title: "Model Mix",
                        subtitle: "Top cost drivers across providers that expose model-level billing.",
                        rows: self.insights.modelRows,
                        total: self.insights.modelRows.reduce(0) { $0 + $1.amountUSD })
                }

                if !self.insights.serviceRows.isEmpty {
                    self.contributionSection(
                        title: "Codex Service Mix",
                        subtitle: "Breakdown from Codex Cloud dashboard data, including Codex Run and other billable services.",
                        rows: self.insights.serviceRows,
                        total: self.insights.serviceRows.reduce(0) { $0 + $1.amountUSD })
                }

                if !self.insights.budgetRows.isEmpty {
                    self.budgetSection
                }

                if self.isDemoMode {
                    Label("Showing demo data", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    SyncStatusBar(usageData: self.usageData)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            await self.usageData.refresh()
        }
        .modifier(SoftScrollEdgeModifier())
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
                .padding(.top, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                CostMetricCard(
                    title: "30 Days",
                    value: Self.formatUSD(self.insights.total30DayCost),
                    subtitle: self.insights.total30DayTokens > 0 ? Self
                        .formatTokens(self.insights.total30DayTokens) : nil,
                    tintColor: .orange)

                CostMetricCard(
                    title: "Today",
                    value: Self.formatUSD(self.insights.totalTodayCost),
                    subtitle: self.providersActiveSubtitle,
                    tintColor: .mint)

                CostMetricCard(
                    title: "Top Driver",
                    value: Self.formatUSD(self.insights.topProvider?.thirtyDayCost ?? 0),
                    subtitle: self.topDriverSubtitle,
                    tintColor: providerTint(for: self.insights.topProvider?.provider))

                CostMetricCard(
                    title: "Active Days",
                    value: "\(self.insights.activeDayCount)",
                    subtitle: self.activeDaySubtitle,
                    tintColor: .blue)
            }
        }
    }

    private static let chartVisibleDays: Int = 30

    private static func chartScrollInitialDate(points: [CostDashboardInsights.DailyPoint]) -> Date {
        guard let last = points.last else { return Date() }
        return Calendar.current.date(byAdding: .day, value: -(chartVisibleDays - 1), to: last.date) ?? last.date
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Daily Spend")
                    .font(.headline)
                Text("(USD)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(Color.orange.gradient)
                        .cornerRadius(4)
                case .line:
                    AreaMark(
                        x: .value(String(localized: "Date"), point.date),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.35), Color.orange.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom))
                        .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value(String(localized: "Date"), point.date),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(Color.orange)
                        .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }

                if let selectedPoint = self.selectedPoint, selectedPoint.id == point.id {
                    RuleMark(x: .value(String(localized: "Selected Date"), selectedPoint.date))
                        .foregroundStyle(Color.orange.opacity(0.35))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value(String(localized: "Selected Date"), selectedPoint.date),
                        y: .value(String(localized: "Selected Cost"), selectedPoint.costUSD))
                        .foregroundStyle(Color.orange)
                        .symbolSize(80)
                }
            }
            .chartXSelection(value: self.$selectedDay)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: Self.chartVisibleDays * 24 * 60 * 60)
            .chartScrollPosition(initialX: Self.chartScrollInitialDate(points: self.insights.dailyPoints))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(values: MobileChartAxisFormatter.axisValues(for: self.insights.dailyPoints.map(\.costUSD))) {
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let selectedPoint = self.selectedPoint {
                HStack {
                    Text(Self.shortDate(selectedPoint.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.formatUSD(selectedPoint.costUSD))
                        .font(.caption.monospacedDigit())
                        .fontWeight(.medium)
                    if selectedPoint.totalTokens > 0 {
                        Text("· \(Self.formatTokens(selectedPoint.totalTokens))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
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
                .foregroundStyle(.secondary)
            }
        }
    }

    private func contributionSection(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        rows: [CostBreakdownRow],
        total: Double) -> some View
    {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.top, 4)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(Array(rows.prefix(6))) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(row.color)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if let subtitle = row.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            CostBreakdownMetricColumn(
                                amountText: Self.formatUSD(row.amountUSD),
                                shareText: Self.formatShare(row.amountUSD, total: total))
                        }

                        ProgressView(value: Self.safeRatio(row.amountUSD, total: total))
                            .tint(row.color)
                            .scaleEffect(y: 1.8, anchor: .center)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Budgets")
                .font(.headline)
                .padding(.top, 4)

            Text("Tracked provider budgets and how close they are to their current limit.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(self.insights.budgetRows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(row.provider.providerName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            if let method = row.provider.loginMethod {
                                Text(method)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        BudgetProgressView(
                            budget: row.budget,
                            tintColor: providerTint(for: row.provider))
                    }
                }
            }
        }
    }

    private func providerSubtitle(for row: CostDashboardInsights.ProviderRow) -> String {
        let today = row.todayCost > 0
            ? "\(String(localized: "Today")) \(Self.formatUSD(row.todayCost))"
            : String(localized: "No spend today")
        let tokens = row.thirtyDayTokens > 0 ? Self.formatTokens(row.thirtyDayTokens) : String(localized: "No token data")
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
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return "\(Self.formatCompactNumber(Double(count) / 1_000_000)) \(String(localized: "M tokens"))"
        } else if count >= 1000 {
            return "\(Self.formatCompactNumber(Double(count) / 1000)) \(String(localized: "K tokens"))"
        }
        return "\(count.formatted()) \(String(localized: "tokens"))"
    }

    private static func shortDate(_ value: Date) -> String {
        value.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func formatCompactNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct CostBreakdownMetricColumn: View {
    let amountText: String
    let shareText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(self.amountText)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                Text(self.shareText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .trailing, spacing: 2) {
                Text(self.amountText)
                    .font(.headline.monospacedDigit())
                    .fontWeight(.bold)
                Text(self.shareText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .layoutPriority(1)
    }
}

struct CostDashboardInsights {
    struct ProviderRow: Identifiable {
        let provider: ProviderUsageSnapshot
        let thirtyDayCost: Double
        let todayCost: Double
        let thirtyDayTokens: Int

        var id: String {
            self.provider.providerID
        }
    }

    struct DailyPoint: Identifiable {
        let dayKey: String
        let date: Date
        let costUSD: Double
        let totalTokens: Int

        var id: String {
            self.dayKey
        }
    }

    let providerRows: [ProviderRow]
    let dailyPoints: [DailyPoint]
    let modelRows: [CostBreakdownRow]
    let serviceRows: [CostBreakdownRow]
    let budgetRows: [CostBudgetRow]

    var total30DayCost: Double {
        self.providerRows.reduce(0) { $0 + $1.thirtyDayCost }
    }

    var totalTodayCost: Double {
        self.providerRows.reduce(0) { $0 + $1.todayCost }
    }

    var total30DayTokens: Int {
        self.providerRows.reduce(0) { $0 + $1.thirtyDayTokens }
    }

    var topProvider: ProviderRow? {
        self.providerRows.max { $0.thirtyDayCost < $1.thirtyDayCost }
    }

    var highestDay: DailyPoint? {
        self.dailyPoints.max { $0.costUSD < $1.costUSD }
    }

    var activeDayCount: Int {
        self.dailyPoints.count(where: { $0.costUSD > 0 })
    }

    var hasDisplayData: Bool {
        !self.providerRows.isEmpty || !self.dailyPoints.isEmpty || !self.budgetRows.isEmpty
    }

    init(snapshot: SyncedUsageSnapshot) {
        let todayKey = Self.dayKeyFormatter.string(from: Date())
        var providerRows: [ProviderRow] = []
        var dailyTotals: [String: (costUSD: Double, totalTokens: Int)] = [:]
        var modelTotals: [String: Double] = [:]
        var serviceTotals: [String: Double] = [:]
        var budgetRows: [CostBudgetRow] = []

        for provider in snapshot.providers {
            if let budget = provider.budget {
                budgetRows.append(CostBudgetRow(provider: provider, budget: budget))
            }

            guard let costSummary = provider.costSummary else { continue }

            let thirtyDayCost = costSummary.last30DaysCostUSD
                ?? costSummary.daily.reduce(0) { $0 + $1.costUSD }
            let thirtyDayTokens = costSummary.last30DaysTokens
                ?? costSummary.daily.reduce(0) { $0 + $1.totalTokens }

            let todayPoint = costSummary.daily.first(where: { $0.dayKey == todayKey })
            let todayCost = todayPoint?.costUSD ?? costSummary.sessionCostUSD ?? 0

            guard thirtyDayCost > 0 || todayCost > 0 || !costSummary.daily.isEmpty else { continue }

            providerRows.append(
                ProviderRow(
                    provider: provider,
                    thirtyDayCost: thirtyDayCost,
                    todayCost: todayCost,
                    thirtyDayTokens: thirtyDayTokens))

            for point in costSummary.daily {
                dailyTotals[point.dayKey, default: (0, 0)].costUSD += point.costUSD
                dailyTotals[point.dayKey, default: (0, 0)].totalTokens += point.totalTokens

                for breakdown in point.modelBreakdowns where breakdown.costUSD > 0 {
                    modelTotals[breakdown.label, default: 0] += breakdown.costUSD
                }

                for breakdown in point.serviceBreakdowns where breakdown.costUSD > 0 {
                    serviceTotals[breakdown.label, default: 0] += breakdown.costUSD
                }
            }
        }

        self.providerRows = providerRows.sorted { lhs, rhs in
            if lhs.thirtyDayCost == rhs.thirtyDayCost {
                return lhs.provider.providerName
                    .localizedCaseInsensitiveCompare(rhs.provider.providerName) == .orderedAscending
            }
            return lhs.thirtyDayCost > rhs.thirtyDayCost
        }

        self.dailyPoints = dailyTotals.keys.compactMap { dayKey in
            guard let date = Self.dayKeyFormatter.date(from: dayKey),
                  let totals = dailyTotals[dayKey] else { return nil }
            return DailyPoint(dayKey: dayKey, date: date, costUSD: totals.costUSD, totalTokens: totals.totalTokens)
        }
        .sorted { $0.date < $1.date }

        self.modelRows = Self.breakdownRows(from: modelTotals, palette: .model)
        self.serviceRows = Self.breakdownRows(from: serviceTotals, palette: .service)
        self.budgetRows = budgetRows.sorted { lhs, rhs in
            let lhsRatio = lhs.budget.limitAmount > 0 ? lhs.budget.usedAmount / lhs.budget.limitAmount : 0
            let rhsRatio = rhs.budget.limitAmount > 0 ? rhs.budget.usedAmount / rhs.budget.limitAmount : 0
            return lhsRatio > rhsRatio
        }
    }

    private static func breakdownRows(from totals: [String: Double], palette: BreakdownPalette) -> [CostBreakdownRow] {
        totals
            .filter { $0.value > 0 }
            .map { label, amount in
                CostBreakdownRow(
                    label: label,
                    amountUSD: amount,
                    subtitle: nil,
                    color: palette.color(for: label))
            }
            .sorted { lhs, rhs in
                if lhs.amountUSD == rhs.amountUSD {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.amountUSD > rhs.amountUSD
            }
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct CostBreakdownRow: Identifiable {
    let label: String
    let amountUSD: Double
    let subtitle: String?
    let color: Color

    var id: String {
        self.label
    }
}

struct CostBudgetRow: Identifiable {
    let provider: ProviderUsageSnapshot
    let budget: SyncBudgetSnapshot

    var id: String {
        self.provider.providerID
    }
}

private enum BreakdownPalette {
    case model
    case service

    func color(for label: String) -> Color {
        let seed = label.lowercased().unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        let hueBase = switch self {
        case .model: 0.08
        case .service: 0.52
        }
        let hue = (hueBase + (Double(seed % 21) / 100)).truncatingRemainder(dividingBy: 1)
        let saturation = 0.62 + Double(seed % 7) * 0.03
        let brightness = 0.78 + Double(seed % 5) * 0.03
        return Color(hue: hue, saturation: min(saturation, 0.95), brightness: min(brightness, 0.98))
    }
}

private func providerTint(for provider: ProviderUsageSnapshot?) -> Color {
    let id = provider?.providerID.lowercased() ?? ""
    if id.contains("claude") || id.contains("anthropic") {
        return Color(red: 0.82, green: 0.55, blue: 0.28)
    } else if id.contains("codex") || id.contains("cursor") {
        return .purple
    } else if id.contains("openai") || id.contains("chatgpt") {
        return .green
    } else if id.contains("openrouter") {
        return Color(red: 0.42, green: 0.35, blue: 0.83)
    } else {
        return .blue
    }
}

// MARK: - Setting Tab

private struct SettingsTab: View {
    let usageData: SyncedUsageData
    @State private var showingSetupGuide = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        self.showingSetupGuide = true
                    } label: {
                        SettingSummaryRow(
                            title: "Setup Guide",
                            symbolName: "sparkles",
                            summary: String(localized: "Walk through how CodexBar syncs from Mac to iPhone"))
                    }
                    .tint(.primary)

                    NavigationLink {
                        AboutSyncDetailView(usageData: self.usageData)
                    } label: {
                        SettingSummaryRow(
                            title: "About & Sync",
                            symbolName: "iphone.and.arrow.forward",
                            summary: "\(String(localized: "iPhone")) \(self.mobileVersionSummary) · \(String(localized: "Mac")) \(self.macVersionSummary)")
                    }

                    NavigationLink {
                        ReleaseNotesView()
                    } label: {
                        SettingSummaryRow(
                            title: "Release Notes",
                            symbolName: "text.document",
                            summary: String(localized: "Latest updates and version history"))
                    }
                }

                Section {
                    NavigationLink {
                        UsageSettingsView()
                    } label: {
                        SettingSummaryRow(
                            title: "Usage Setting",
                            symbolName: "chart.bar.fill",
                            summary: String(localized: "Configure the Usage page"))
                    }

                    NavigationLink {
                        CostSettingsView()
                    } label: {
                        SettingSummaryRow(
                            title: "Cost Setting",
                            symbolName: "dollarsign.circle.fill",
                            summary: String(localized: "Configure the Cost page"))
                    }
                }

                Section("Developer") {
                    Link(destination: URL(string: "https://x.com/o1xhack")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Yuxiao")
                                    .fontWeight(.medium)
                                Text("@o1xhack on X")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.fill")
                        }
                    }
                }

                Section("Developer") {
                    NavigationLink {
                        DeveloperToolsView(usageData: self.usageData)
                    } label: {
                        SettingSummaryRow(
                            title: "Developer Tools",
                            symbolName: "wrench.and.screwdriver",
                            summary: String(localized: "Sync inspector, push diagnostic, and more"))
                    }
                }

                Section("Open Source") {
                    Link(destination: URL(string: "https://github.com/o1xhack/CodexBar")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("o1xhack/CodexBar")
                                    .fontWeight(.medium)
                                Text("Install the Mac app from this repo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                        }
                    }

                    Link(destination: URL(string: "https://github.com/steipete/CodexBar")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("steipete/CodexBar")
                                    .fontWeight(.medium)
                                Text("Original Mac app — MIT License")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.triangle.branch")
                        }
                    }
                }
            }
            .contentMargins(.top, 12, for: .scrollContent)
            .navigationTitle("Setting")
            .sheet(isPresented: self.$showingSetupGuide) {
                NavigationStack {
                    OnboardingView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    self.showingSetupGuide = false
                                }
                                .fontWeight(.semibold)
                            }
                        }
                }
            }
        }
    }

    private var mobileVersionSummary: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return version
    }

    private var macVersionSummary: String {
        guard let snapshot = self.usageData.snapshot else { return String(localized: "Not synced") }
        return snapshot.appVersion ?? String(localized: "Unknown")
    }
}

private struct SettingSummaryRow: View {
    let title: LocalizedStringResource
    let symbolName: String
    let summary: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: self.symbolName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(self.title)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(self.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AboutSyncDetailView: View {
    let usageData: SyncedUsageData

    private var appDisplayVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section("Versions") {
                LabeledContent("iPhone App", value: self.appDisplayVersion)
                if let snapshot = self.usageData.snapshot {
                    LabeledContent("Mac App", value: snapshot.appVersion ?? String(localized: "Unknown"))
                    if let mobileVersion = snapshot.mobileVersion {
                        LabeledContent("Synced Mobile Version", value: mobileVersion)
                    }
                } else {
                    LabeledContent("Mac App", value: String(localized: "Not synced"))
                }
            }

            // MARK: Mac Update Prompt
            if self.usageData.usingKVSFallback {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.app.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mac Update Available")
                                .font(.subheadline.weight(.semibold))
                            Text("Your Mac is using legacy sync. Update CodexBar on Mac to unlock CloudKit multi-device sync.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://github.com/o1xhack/CodexBar/releases")!) {
                        Label("Download Latest Mac Version", systemImage: "arrow.down.circle")
                    }
                }
            }

            // MARK: Sync Status
            Section {
                HStack {
                    self.syncStatusIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.syncStatusTitle)
                            .font(.body)
                        if let detail = self.syncStatusDetail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await self.usageData.refresh() }
                    } label: {
                        if case .syncing = self.usageData.syncStatus {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(self.usageData.syncStatus == .syncing)
                }
            } header: {
                Text("Sync Status")
            } footer: {
                if let error = self.usageData.lastSyncError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            // MARK: Devices
            Section {
                if self.usageData.deviceSnapshots.isEmpty {
                    Text("No devices synced yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(self.usageData.deviceSnapshots.enumerated()), id: \.offset) { _, device in
                        HStack {
                            Image(systemName: "laptopcomputer")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.deviceName)
                                    .font(.body)
                                HStack(spacing: 8) {
                                    Text(device.syncTimestamp.formatted(.relative(presentation: .named)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .foregroundStyle(.quaternary)
                                    Text("\(device.providers.count) providers")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                HStack {
                    Text("Devices")
                    Spacer()
                    Text("\(self.usageData.deviceCount)")
                        .foregroundStyle(.secondary)
                }
            }

        }
        .navigationTitle("About & Sync")
    }

    private var syncStatusIcon: some View {
        Group {
            switch self.usageData.syncStatus {
            case .synced:
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                    .foregroundStyle(.blue)
            case .error:
                Image(systemName: "exclamationmark.icloud.fill")
                    .foregroundStyle(.red)
            case .noData:
                Image(systemName: "icloud.slash.fill")
                    .foregroundStyle(.orange)
            case .incompatibleData:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.title2)
    }

    private var syncStatusTitle: String {
        switch self.usageData.syncStatus {
        case .synced: String(localized: "Synced")
        case .syncing: String(localized: "Syncing…")
        case .error: String(localized: "Sync Error")
        case .noData: String(localized: "No Data")
        case .incompatibleData: String(localized: "Incompatible Data")
        }
    }

    private var syncStatusDetail: String? {
        switch self.usageData.syncStatus {
        case .synced(let ago):
            if ago < 60 { return String(localized: "Last synced just now") }
            if let snapshot = self.usageData.snapshot {
                return String(localized: "Last synced \(snapshot.syncTimestamp.formatted(.relative(presentation: .named)))")
            }
            return nil
        case .syncing: return nil
        case .noData: return String(localized: "Waiting for Mac to push data")
        case .incompatibleData: return String(localized: "Please update CodexBar on Mac")
        case .error: return nil
        }
    }
}

// MARK: - Raw Sync Data (Developer Debug View)

private struct RawSyncDataView: View {
    let usageData: SyncedUsageData

    var body: some View {
        List {
            if self.usageData.deviceSnapshots.isEmpty {
                Section {
                    Text("No device data available")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(self.usageData.deviceSnapshots.enumerated()), id: \.offset) { _, device in
                    RawDeviceSection(device: device)
                }
            }
        }
        .navigationTitle("Raw Sync Data")
    }
}

private struct RawDeviceSection: View {
    let device: SyncedUsageSnapshot

    var body: some View {
        Section {
            LabeledContent("Device ID", value: self.device.deviceID ?? "N/A")
            LabeledContent("Device Name", value: self.device.deviceName)
            LabeledContent("App Version", value: self.device.appVersion ?? "Unknown")
            LabeledContent("Sync Time", value: self.device.syncTimestamp.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Providers", value: "\(self.device.providers.count)")

            ForEach(self.device.providers, id: \.providerID) { provider in
                RawProviderRow(provider: provider)
            }
        } header: {
            HStack {
                Image(systemName: "laptopcomputer")
                Text(self.device.deviceName)
            }
        }
    }
}

private struct RawProviderRow: View {
    let provider: ProviderUsageSnapshot

    var body: some View {
        NavigationLink {
            RawProviderDetailView(provider: self.provider)
        } label: {
            HStack {
                Text(self.provider.providerName)
                    .fontWeight(.medium)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let cost = self.provider.costSummary {
                        Text(String(format: "$%.2f", cost.sessionCostUSD ?? 0))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let window = self.provider.allRateWindows.first {
                        Text("\(window.label ?? "Usage"): \(Int(window.usedPercent))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

private struct RawProviderDetailView: View {
    let provider: ProviderUsageSnapshot

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Provider", value: self.provider.providerName)
                LabeledContent("ID", value: self.provider.providerID)
                if let email = self.provider.accountEmail {
                    LabeledContent("Account", value: email)
                }
                if let login = self.provider.loginMethod {
                    LabeledContent("Login", value: login)
                }
                LabeledContent("Last Updated", value: self.provider.lastUpdated.formatted(date: .abbreviated, time: .shortened))
                if self.provider.isError {
                    LabeledContent("Status", value: self.provider.statusMessage ?? "Error")
                        .foregroundStyle(.red)
                }
            }

            if let cost = self.provider.costSummary {
                Section("Cost Summary") {
                    LabeledContent("Session", value: self.formatCost(cost.sessionCostUSD))
                    LabeledContent("Session Tokens", value: self.formatTokens(cost.sessionTokens))
                    LabeledContent("30 Days", value: self.formatCost(cost.last30DaysCostUSD))
                    LabeledContent("30 Days Tokens", value: self.formatTokens(cost.last30DaysTokens))
                }
            }

            self.rateWindowsSection

            if let cost = self.provider.costSummary, !cost.daily.isEmpty {
                self.dailyCostSection(cost.daily)
            }
        }
        .navigationTitle(self.provider.providerName)
    }

    @ViewBuilder
    private var rateWindowsSection: some View {
        let windows = self.provider.allRateWindows
        if !windows.isEmpty {
            Section("Rate Limits") {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    RawRateWindowRow(window: window)
                }
            }
        }
    }

    @ViewBuilder
    private func dailyCostSection(_ daily: [SyncDailyPoint]) -> some View {
        let sorted = daily.sorted { $0.dayKey > $1.dayKey }
        Section("Daily Cost (\(sorted.count) days)") {
            ForEach(sorted, id: \.dayKey) { day in
                RawDailyPointRow(day: day)
            }
        }
    }

    private func formatCost(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "$%.2f", value)
    }

    private func formatTokens(_ value: Int?) -> String {
        guard let value else { return "N/A" }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

private struct RawRateWindowRow: View {
    let window: SyncRateWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(self.window.label ?? "Rate Limit")
                Spacer()
                Text("\(Int(self.window.usedPercent))% used")
                    .foregroundStyle(self.window.usedPercent > 80 ? .red : .secondary)
            }
            ProgressView(value: min(self.window.usedPercent, 100), total: 100)
                .tint(self.window.usedPercent > 80 ? .red : .blue)
            if let reset = self.window.resetDescription {
                Text("Resets \(reset)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RawDailyPointRow: View {
    let day: SyncDailyPoint

    var body: some View {
        DisclosureGroup {
            self.breakdownContent
        } label: {
            HStack {
                Text(self.day.dayKey)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "$%.2f", self.day.costUSD))
                        .font(.body.monospacedDigit())
                    Text(self.formatTokens(self.day.totalTokens))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var breakdownContent: some View {
        if !self.day.modelBreakdowns.isEmpty {
            ForEach(self.day.modelBreakdowns, id: \.label) { item in
                LabeledContent(item.label, value: String(format: "$%.2f", item.costUSD))
            }
        }
        if !self.day.serviceBreakdowns.isEmpty {
            ForEach(self.day.serviceBreakdowns, id: \.label) { item in
                LabeledContent(item.label, value: String(format: "$%.2f", item.costUSD))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM tokens", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK tokens", Double(value) / 1_000)
        }
        return "\(value) tokens"
    }
}

// MARK: - Developer Tools (container listing all dev tools)

private struct DeveloperToolsView: View {
    let usageData: SyncedUsageData

    var body: some View {
        List {
            Section {
                NavigationLink {
                    RawSyncDataView(usageData: self.usageData)
                } label: {
                    SettingSummaryRow(
                        title: "Raw Sync Data",
                        symbolName: "doc.text.magnifyingglass",
                        summary: String(localized: "Per-device unmerged data for debugging"))
                }

                NavigationLink {
                    PushDiagnosticView(usageData: self.usageData)
                } label: {
                    SettingSummaryRow(
                        title: "Push Diagnostic",
                        symbolName: "bell.badge.waveform",
                        summary: String(localized: "Mac→iOS notification chain state"))
                }
            } footer: {
                Text("These tools expose internal sync and notification state to help diagnose issues. No sensitive data is shown.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Developer Tools")
    }
}

// MARK: - Push Diagnostic (Developer Debug View)

private struct PushDiagnosticView: View {
    let usageData: SyncedUsageData
    @State private var store = PushDiagnosticStore.shared
    @State private var isFetching = false

    var body: some View {
        List {
            Section {
                self.chainRow(
                    title: "APNS Registration",
                    status: self.store.registrationState.label,
                    timestamp: self.store.registrationUpdatedAt,
                    level: self.level(for: self.store.registrationState))
                self.chainRow(
                    title: "CKSubscription",
                    status: self.store.subscriptionState.label,
                    timestamp: self.store.subscriptionUpdatedAt,
                    level: self.level(for: self.store.subscriptionState))
                self.chainRow(
                    title: "UN Authorization",
                    status: self.authLabel,
                    timestamp: nil,
                    level: self.store.notificationAuthorized == true ? .ok :
                        (self.store.notificationAuthorized == false ? .error : .pending))
                self.chainRow(
                    title: "Last Silent Push",
                    status: self.store.lastPushReceivedAt.map { self.relativeTime($0) } ?? "—",
                    timestamp: self.store.lastPushReceivedAt,
                    level: self.store.lastPushReceivedAt == nil ? .pending : .ok)
                self.chainRow(
                    title: "Last Fetch",
                    status: self.store.lastFetchState.label,
                    timestamp: self.store.lastFetchAt,
                    level: self.level(for: self.store.lastFetchState))
                self.chainRow(
                    title: "Last Transitions",
                    status: self.store.lastTransitionSummary,
                    timestamp: self.store.lastTransitionAt,
                    level: self.store.totalTransitionCount > 0 ? .ok : .pending)
                self.chainRow(
                    title: "Last Local Notification",
                    status: self.store.lastNotificationState.label,
                    timestamp: self.store.lastNotificationAt,
                    level: self.level(for: self.store.lastNotificationState))
            } header: {
                Text("Push Chain State")
            } footer: {
                Text("Each row should transition from pending → OK after Mac pushes a test. If any row stays pending or shows FAILED, that's where the chain breaks.")
                    .font(.caption2)
            }

            Section("Counters") {
                LabeledContent("Silent pushes received", value: "\(self.store.totalPushCount)")
                LabeledContent("Transitions detected (total)", value: "\(self.store.totalTransitionCount)")
                LabeledContent("Connected devices", value: "\(self.usageData.deviceCount)")
            }

            Section("Manual Actions") {
                Button {
                    Task {
                        self.isFetching = true
                        await self.usageData.fetchFromCloudKit()
                        PushDiagnosticStore.shared.recordFetch(
                            .success(deviceCount: self.usageData.deviceCount))
                        self.isFetching = false
                    }
                } label: {
                    HStack {
                        Label("Fetch Now", systemImage: "arrow.clockwise.icloud")
                        if self.isFetching {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(self.isFetching)

                Button {
                    Task {
                        await self.usageData.forceResubscribe()
                    }
                } label: {
                    Label("Re-create CKSubscription", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    Task {
                        let ok = await LocalNotificationManager.shared.postDiagnosticTestNotification()
                        await MainActor.run {
                            PushDiagnosticStore.shared.recordNotificationPost(
                                ok ? .success(count: 1)
                                   : .failed(message: "Could not add notification request"))
                        }
                    }
                } label: {
                    Label("Post Test Local Notification", systemImage: "bell.badge")
                }

                Button(role: .destructive) {
                    self.store.clearLog()
                } label: {
                    Label("Clear Event Log", systemImage: "trash")
                }
            }

            if !self.store.log.isEmpty {
                Section("Event Log (\(self.store.log.count))") {
                    ForEach(self.store.log) { entry in
                        self.logRow(entry)
                    }
                }
            }
        }
        .navigationTitle("Push Diagnostic")
    }

    // MARK: - Helpers

    private enum Level {
        case pending, ok, warning, error
        var color: Color {
            switch self {
            case .pending: .secondary
            case .ok: .green
            case .warning: .orange
            case .error: .red
            }
        }
        var symbol: String {
            switch self {
            case .pending: "circle"
            case .ok: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.circle.fill"
            }
        }
    }

    private func level(for state: PushDiagnosticStore.RegistrationState) -> Level {
        switch state {
        case .pending: .pending
        case .success: .ok
        case .failed: .error
        }
    }

    private func level(for state: PushDiagnosticStore.SubscriptionState) -> Level {
        switch state {
        case .pending: .pending
        case .created, .alreadyExists: .ok
        case .failed: .error
        }
    }

    private func level(for state: PushDiagnosticStore.FetchState) -> Level {
        switch state {
        case .none: .pending
        case .success: .ok
        case .empty: .warning
        case .failed: .error
        }
    }

    private func level(for state: PushDiagnosticStore.NotificationPostState) -> Level {
        switch state {
        case .none: .pending
        case .success: .ok
        case .suppressed: .warning
        case .failed: .error
        }
    }

    private var authLabel: String {
        switch self.store.notificationAuthorized {
        case true: "Granted"
        case false: "Denied"
        case nil: "Not yet requested"
        case .some: "Unknown"
        }
    }

    private func chainRow(title: String, status: String, timestamp: Date?, level: Level) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: level.symbol)
                    .foregroundStyle(level.color)
                    .font(.footnote)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let ts = timestamp {
                    Text(self.relativeTime(ts))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func logRow(_ entry: PushDiagnosticStore.LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(self.entryTimestamp(entry.timestamp))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .leading)
            Circle()
                .fill(self.color(for: entry.level))
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            Text(entry.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func color(for level: PushDiagnosticStore.LogEntry.Level) -> Color {
        switch level {
        case .info: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    private func entryTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct ReleaseNotesVersion: Identifiable {
    struct Section: Identifiable {
        let title: String
        let items: [String]

        var id: String {
            self.title
        }
    }

    let version: String
    let status: String
    let summary: String
    let sections: [Section]

    var id: String {
        self.version
    }
}

private enum MobileReleaseNotesCatalog {
    static let versions: [ReleaseNotesVersion] = [
        ReleaseNotesVersion(
            version: "1.2.0",
            status: String(localized: "Latest"),
            summary: String(localized: "Subscription Utilization charts and cleaner Settings."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(localized: "Version 1.2.0 works best with the latest CodexBar Mac app (0.19.0 or later). Utilization History sync relies on Mac-side fixes shipped in that release. Download from GitHub: github.com/o1xhack/CodexBar/releases"),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(localized: "Subscription Utilization in the Cost tab — 30-day daily chart with Today / This Week / 14 Days / 30 Days summary cards, each with delta vs the previous period."),
                        String(localized: "Provider Share breakdown — each provider's proportional share of total utilization, summing to 100%."),
                        String(localized: "Subscription Utilization History chart on every provider detail page."),
                        String(localized: "Push Diagnostic developer tool — inspect the Mac→iOS notification chain in Settings → Developer Tools."),
                        String(localized: "Setup Guide is now a top-level Settings row."),
                    ]),
                .init(
                    title: String(localized: "Improvements"),
                    items: [
                        String(localized: "Multi-device utilization merge — data from all your Macs is combined and deduped by hour for consistent charts."),
                        String(localized: "Developer Tools consolidated — Raw Sync Data and Push Diagnostic share one entry."),
                        String(localized: "Removed the redundant How It Works sections from Settings and About & Sync."),
                        String(localized: "About page build timestamp is now always shown in English regardless of system language."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.1.0",
            status: "",
            summary: String(localized: "Multi-device CloudKit sync. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(localized: "Version 1.1.0 requires the latest CodexBar Mac app (0.18.0-mobile-1.1.0 or later) to unlock CloudKit sync. Download it from GitHub: github.com/o1xhack/CodexBar/releases"),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(localized: "CloudKit multi-device sync — data from multiple Macs is now merged on iPhone instead of last-write-wins."),
                        String(localized: "New Sync Detail page in Settings — view sync status, connected devices, and detailed error info."),
                        String(localized: "Raw Sync Data inspector — per-device unmerged data with daily cost breakdowns for debugging."),
                        String(localized: "Specific CloudKit error messages — network, auth, quota issues now show exact cause instead of generic errors."),
                    ]),
                .init(
                    title: String(localized: "Improvements"),
                    items: [
                        String(localized: "Tab bar no longer hides when scrolling."),
                        String(localized: "Simplified sync status bar at the bottom of Usage and Cost tabs."),
                        String(localized: "Legacy KVS sync maintained as fallback for older Mac app versions."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.0.0 (21)",
            status: "",
            summary: String(localized: "The first App Store release. Works with CodexBar on Mac."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(localized: "Share your AI spending as a beautiful image card — choose Classic or Vibe style, supports Today, 7 Days, and 30 Days, and adapts to dark mode."),
                        String(localized: "Usage percentages now stay crisp without blur on provider cards."),
                        String(localized: "Cost summaries and breakdown amounts remain sharp in tighter layouts."),
                        String(localized: "View AI coding tool usage on iPhone, synced from Mac via iCloud."),
                        String(localized: "Provider cards with real-time rate limits, budget progress, and daily cost breakdowns."),
                        String(localized: "Cost dashboard with provider share, model and service mix, and 30-day spend analysis."),
                        String(localized: "Interactive charts with Bar and Line styles, press-and-hold inspection, and horizontal scrolling for history."),
                        String(localized: "Supports English, Simplified Chinese, Traditional Chinese, and Japanese."),
                        String(localized: "Liquid Glass design, demo mode, onboarding guide, and pull-to-refresh."),
                    ]),
                .init(
                    title: String(localized: "Improvements & Fixes"),
                    items: [
                        String(localized: "Percentage and cost labels are now sharper and easier to read."),
                        String(localized: "Toggle between used and remaining quota display in Settings."),
                        String(localized: "Smarter chart axis scaling with clean integer tick marks."),
                        String(localized: "Improved iCloud sync reliability and error reporting."),
                    ]),
            ]),
    ]
}

private struct ReleaseNotesView: View {
    private let versions = MobileReleaseNotesCatalog.versions

    private var latestVersion: ReleaseNotesVersion? {
        self.versions.first
    }

    private var historicalVersions: ArraySlice<ReleaseNotesVersion> {
        self.versions.dropFirst()
    }

    var body: some View {
        List {
            if let latestVersion = self.latestVersion {
                Section("Latest") {
                    ReleaseNotesCard(version: latestVersion)
                }
            }

            Section("History") {
                if self.historicalVersions.isEmpty {
                    Text("Older iOS release notes will appear here as new versions ship.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(self.historicalVersions)) { version in
                        DisclosureGroup {
                            ReleaseNotesContent(version: version)
                                .padding(.top, 8)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                    Text("\(String(localized: "Version")) \(version.version)")
                                        .fontWeight(.semibold)
                                    ReleaseNotesBadge(title: version.status)
                                }

                                Text(version.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Release Notes")
    }
}

private struct ReleaseNotesCard: View {
    let version: ReleaseNotesVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(String(localized: "Version")) \(self.version.version)")
                        .font(.headline)
                    Text(self.version.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                ReleaseNotesBadge(title: self.version.status)
            }

            ReleaseNotesContent(version: self.version)
        }
        .padding(.vertical, 8)
    }
}

private struct ReleaseNotesContent: View {
    let version: ReleaseNotesVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(self.version.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 7)

                                Text(item)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ReleaseNotesBadge: View {
    let title: String

    var body: some View {
        Text(self.title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.tint.opacity(0.12), in: Capsule())
    }
}

private struct UsageSettingsView: View {
    @AppStorage(MobileSettingsKeys.usageCostChartStyle) private var usageCostChartStyleRawValue = CostChartStyle.bars
        .rawValue
    @AppStorage(MobileSettingsKeys.showRemainingUsage) private var showRemainingUsage =
        UserDefaults.standard.string(forKey: MobileSettingsKeys.usagePercentDisplayMode) == UsagePercentDisplayMode.remaining.rawValue
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidePersonalInfo = false
    @AppStorage(MobileSettingsKeys.sessionQuotaNotificationsEnabled) private var sessionQuotaNotifications = true

    var body: some View {
        List {
            Section {
                Toggle("Show remaining usage", isOn: self.$showRemainingUsage)
                    .toggleStyle(.switch)
                    .font(.body)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("show-remaining-usage-toggle")
            } header: {
                Text("Usage")
            } footer: {
                Text("Display the quota you have left instead of the quota you have used on usage cards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Chart Style", selection: self.usageChartStyle) {
                    ForEach(CostChartStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Charts")
            } footer: {
                Text("Press and hold on the chart to inspect the exact value for a given day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: self.$sessionQuotaNotifications) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session quota notifications")
                        Text("Notifies when the 5-hour session quota hits 0% and when it becomes available again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Notifications")
            }

            Section {
                Toggle(isOn: self.$hidePersonalInfo) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hide personal information")
                        Text("Obscure email addresses in the Usage page.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Usage Setting")
        .listStyle(.insetGrouped)
    }

    private var usageChartStyle: Binding<CostChartStyle> {
        Binding(
            get: { CostChartStyle(rawValue: self.usageCostChartStyleRawValue) ?? .bars },
            set: { self.usageCostChartStyleRawValue = $0.rawValue })
    }
}

private struct CostSettingsView: View {
    @AppStorage(MobileSettingsKeys.dashboardCostChartStyle) private var dashboardCostChartStyleRawValue =
        CostChartStyle.line.rawValue
    @AppStorage(MobileSettingsKeys.openCostByDefault) private var openCostByDefault = false

    var body: some View {
        List {
            Section("Charts") {
                Picker("Chart Style", selection: self.dashboardChartStyle) {
                    ForEach(CostChartStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                Toggle(isOn: self.$openCostByDefault) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Cost by default")
                        Text("Launch the app on the Cost tab next time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("Press and hold on the chart to inspect the exact value for a given day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cost Setting")
    }

    private var dashboardChartStyle: Binding<CostChartStyle> {
        Binding(
            get: { CostChartStyle(rawValue: self.dashboardCostChartStyleRawValue) ?? .line },
            set: { self.dashboardCostChartStyleRawValue = $0.rawValue })
    }
}

// MARK: - Previews

#Preview("With Data") {
    ContentView(usageData: PreviewData.makeSyncedUsageData())
}

#Preview("Empty State") {
    ContentView(usageData: PreviewData.makeEmptyUsageData())
}
