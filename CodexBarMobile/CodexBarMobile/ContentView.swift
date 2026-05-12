import Charts
import CodexBarSync
import SwiftUI
import UIKit

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
                    if MockProviderDetector.filteredProviders(from: snapshot).isEmpty {
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
    /// Local per-launch suppression of linkage prompts the user clicked
    /// "Keep separate" on. Persisted only across the current session —
    /// next launch re-evaluates so a user who reconsidered can confirm.
    /// Long-term persistence isn't needed since the candidate goes away
    /// the moment the legacy Mac upgrades (Research/019 §9 logic).
    @State private var dismissedCandidateKeys = Set<String>()

    var body: some View {
        // Drop extinct mock zombies before any rendering so duplicate
        // cards (OLD vs NEW mock-injector designs) don't appear on the
        // Usage list. iOS 1.5.2+: see `MockProviderDetector.extinctMockProviderIDs`.
        let liveProviders = MockProviderDetector.filteredProviders(from: self.snapshot)
        // Compute linkage candidates ONCE per render. The detector handles
        // ambiguity rules (skips multi-account-named scenarios where we
        // can't tell which named card a legacy entry belongs to).
        let allCandidates = MultiAccountLinkageDetector.candidates(
            among: liveProviders,
            appVersionForProvider: { provider in
                // Find which device-snapshot this provider came from to
                // report its CodexBar version in the §9 hint. Falls back
                // to the merged snapshot's appVersion (the highest across
                // devices) — that's at least the "ceiling" of what other
                // Mac versions could be in play.
                let devices = self.usageData.deviceSnapshots
                if let device = devices.first(where: { snap in
                    snap.providers.contains { $0.cardIdentityKey == provider.cardIdentityKey }
                }) {
                    return device.appVersion
                }
                return nil
            })
        let candidatesByLegacyKey = Dictionary(
            uniqueKeysWithValues: allCandidates.map { ($0.legacy.cardIdentityKey, $0) })
        // Live linkages — used to expose an Unmerge context menu on cards
        // that originated from a confirmed merge group.
        let activeLinkagesByProviderID = Dictionary(
            grouping: self.usageData.providerLinkages.filter { !$0.unmerge },
            by: \.providerID)
        return ScrollView {
            LazyVStack(spacing: 16) {
                MockProviderBanner(snapshot: self.snapshot)
                // Pre-compute the per-providerID siblings-count lookup once.
                // `mergeSnapshots` on iCloud side already splits multi-account
                // Codex (or anything else with distinct accountEmails) into
                // separate `ProviderUsageSnapshot` entries — but previously
                // we used `\.providerID` as the ForEach identity, which
                // collapsed duplicates back into one view instance. Switch
                // to the composite key that matches `mergeSnapshots`'s bucket.
                let countsByProviderID = Dictionary(
                    grouping: liveProviders, by: \.providerID
                ).mapValues(\.count)
                ForEach(liveProviders, id: \.cardIdentityKey) { provider in
                    let siblingCount = countsByProviderID[provider.providerID] ?? 1
                    let ordinal: Int? = siblingCount > 1
                        ? liveProviders
                            .filter { $0.providerID == provider.providerID }
                            .firstIndex(where: { $0.cardIdentityKey == provider.cardIdentityKey })
                            .map { $0 + 1 }
                        : nil
                    // Linkage candidate prompt fires on the LEGACY card
                    // (the one that lacks identifiers). The named card
                    // doesn't show the prompt — the user only needs to
                    // confirm once, and the prompt anchors visually on
                    // the side that's "missing data".
                    let candidate: MultiAccountLinkageCandidate? = {
                        guard let c = candidatesByLegacyKey[provider.cardIdentityKey] else {
                            return nil
                        }
                        return self.dismissedCandidateKeys.contains(c.hashKey) ? nil : c
                    }()
                    let activeLinkage = activeLinkagesByProviderID[provider.providerID]?.first
                    NavigationLink {
                        ProviderDetailView(provider: provider)
                    } label: {
                        ProviderUsageView(
                            provider: provider,
                            duplicateOrdinal: ordinal,
                            linkageCandidate: candidate,
                            activeLinkage: activeLinkage,
                            onConfirmMerge: { c in
                                Task { @MainActor in
                                    await self.usageData.confirmLinkage(
                                        providerID: c.named.providerID,
                                        linkedIdentifiers: c.linkedIdentifiers)
                                }
                            },
                            onDismissMergeCandidate: { c in
                                self.dismissedCandidateKeys.insert(c.hashKey)
                            },
                            onRevokeLinkage: { linkage in
                                Task { @MainActor in
                                    await self.usageData.revokeLinkage(
                                        providerID: linkage.providerID,
                                        linkedIdentifiers: linkage.linkedIdentifiers)
                                }
                            })
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("provider-card-\(provider.cardIdentityKey)")
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

    /// Synchronous computed insights. `CostDashboardInsights.init` is O(providers × daily × breakdowns)
    /// which is fine to recompute per render here — Cost tab has no hover/selection state that would
    /// trigger frequent re-renders. (Hover-heavy views UtilizationAggregateView / UtilizationHistoryView
    /// use `@State` + `.task(id:)` caching because hover changes selection state every frame.)
    /// Synchronous compute ensures first render has data for UI tests and user-perceived responsiveness.
    private var currentInsights: CostDashboardInsights? {
        guard let snapshot = self.displaySnapshot else { return nil }
        let insights = CostDashboardInsights(snapshot: snapshot)
        return insights.hasDisplayData ? insights : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if self.displaySnapshot != nil {
                    if let insights = self.currentInsights {
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
                MockProviderBanner(snapshot: self.usageData.snapshot)
                self.summarySection

                if !self.insights.providerRows.isEmpty {
                    self.contributionSection(
                        title: "Provider Share",
                        subtitle: "30-day spend contribution across synced providers.",
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

    /// Visible window on the Cost-tab daily-spend chart. 30 days is the user's
    /// cost-cycle mental model (monthly bills, budget windows) and matches
    /// `UtilizationAggregateView.windowSize` + `UtilizationHistoryView.windowSize`
    /// so every chart in the app tells the same 30-day story. The week-grid
    /// stride-7 axis labels below depend on this being exactly 30 — changing
    /// it (to 14, 60, etc.) would un-align the gridlines from 7-day buckets.
    private static let chartVisibleDays: Int = 30

    private static func chartScrollInitialDate(points: [CostDashboardInsights.DailyPoint]) -> Date {
        guard let last = points.last else { return Date() }
        return Calendar.current.date(byAdding: .day, value: -(chartVisibleDays - 1), to: last.date) ?? last.date
    }

    /// Locale-independent "M/d" formatter (e.g. "4/18"), matching
    /// UtilizationHistoryView's axis style. Avoids `.dateTime` which rearranges
    /// to "d/M" on en_GB and similar locales.
    private static func dailyAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
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
            // No extra right-side padding — axis labels use anchor .topTrailing
            // below so the label extends LEFT of the tick (slash just left of
            // the rightmost bar), matching UtilizationHistoryView's style.
            // The latest data is always on the right, so left-anchored labels
            // never clip regardless of how close the last bar is to the edge.
            .chartXVisibleDomain(length: Self.chartVisibleDays * 24 * 60 * 60)
            .chartScrollPosition(initialX: Self.chartScrollInitialDate(points: self.insights.dailyPoints))
            .chartXAxis {
                // Stride 7 = one label per week. On a 30-day window this
                // yields ~5 gridlines (day 0, 7, 14, 21, 28) which is a
                // comfortable density for the bar width and keeps visual
                // weight aligned with the share-card's 7-day chart (the
                // two are meant to read as a matching pair; see
                // `CostShareService` dailyBars). Changing stride without
                // also re-tuning `chartVisibleDays` breaks that pairing.
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
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

    private static func formatUSD(_ value: Double) -> String { CostFormatting.usd(value) }
    private static func formatTokens(_ count: Int) -> String { CostFormatting.tokens(count) }

    private static func shortDate(_ value: Date) -> String {
        value.formatted(.dateTime.month(.abbreviated).day())
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

        /// Composite key (providerID|accountEmail) so multi-account rows
        /// with the same providerID don't collapse in SwiftUI ForEach.
        /// Hit on user QA 2026-05-04 — see RawSyncDataView fix in same commit.
        var id: String {
            self.provider.cardIdentityKey
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

        // Drop extinct mock zombies before aggregation so the Cost
        // dashboard's totals don't include them. iOS 1.5.2+: see
        // `MockProviderDetector.extinctMockProviderIDs`.
        let liveProviders = MockProviderDetector.filteredProviders(from: snapshot)
        for provider in liveProviders {
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

    /// Wire-format `dayKey` formatter used to match records to today's
    /// calendar day when reading `SyncCostSummary.daily`. The format
    /// `yyyy-MM-dd` + `en_US_POSIX` + `gregorian` is pinned here to match
    /// Mac-side `SyncCoordinator.daily[].dayKey` generation; changing any
    /// of the three values would make the keys stop round-tripping across
    /// the sync boundary. Do NOT "localize" this — `dayKey` is a machine
    /// contract, not user-facing text. See `SyncCostSummary+Today.swift`
    /// for the symmetric helper used outside this view.
    ///
    /// Only called from view-body (main-actor) synchronous paths —
    /// DateFormatter's documented thread-unsafety does not apply here.
    /// If a future refactor moves the call into a background Task, switch
    /// to `SyncCostSummary.iso8601DayKey(for:)` (per-call factory).
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
    /// Optional override for SwiftUI identity. Defaults to `label` for the
    /// existing Model Mix / Codex Service Mix sites where labels are
    /// guaranteed unique (one row per model name, one per service name).
    /// The Provider Share path on the Cost dashboard supplies a composite
    /// key because two Macs running the same provider with different
    /// `accountEmail` values produce two rows with the same `providerName`
    /// label — ForEach would otherwise collide on the duplicate id, render
    /// both rows with the first row's data, and the second account's $$
    /// vanishes from the UI (1.5.3 fix; see Research/021 §1).
    let identityOverride: String?

    init(
        label: String,
        amountUSD: Double,
        subtitle: String?,
        color: Color,
        identityOverride: String? = nil)
    {
        self.label = label
        self.amountUSD = amountUSD
        self.subtitle = subtitle
        self.color = color
        self.identityOverride = identityOverride
    }

    var id: String {
        self.identityOverride ?? self.label
    }
}

struct CostBudgetRow: Identifiable {
    let provider: ProviderUsageSnapshot
    let budget: SyncBudgetSnapshot

    /// Use the multi-account-aware composite key, not just `providerID`.
    /// Two budgets coming from two Macs on the same provider but different
    /// accounts would otherwise collide and the second budget would render
    /// with the first's data (1.5.3 fix; see Research/021 §1).
    var id: String {
        self.provider.cardIdentityKey
    }
}

/// Deterministic color palette for model / service breakdown chips on the Cost tab.
///
/// The HSB constants below are tuned for two competing requirements:
/// - Labels (e.g. model names like "claude-3-5-sonnet") must get a stable,
///   reproducible color — so we seed from `label` hash and look up HSB from a
///   small constant range rather than choosing randomly.
/// - Adjacent chips in a breakdown list must stay visually distinct — the
///   saturation and brightness ranges are narrow on purpose; widening them
///   introduces grey-ish or washed-out colors that blend into the card
///   material background.
///
/// - `hueBase = 0.08` (model) — warm orange/red family, reserved for model
///   chips (e.g. "claude-3-5-sonnet-20250219").
/// - `hueBase = 0.52` (service) — cool cyan/blue family, reserved for
///   service/deployment chips. The ~0.44 hue gap keeps the two families
///   easily distinguishable even when a user's list mixes both.
/// - Hue variation of `±0.21` (seed % 21 / 100) spreads labels across a
///   slice of the hue wheel without crossing into the other family.
/// - Saturation: 0.62–0.83 — below 0.62 reads as grey on the Cost tab's
///   `.ultraThinMaterial`; above ~0.85 looks harsh on iPad's wider gamut.
/// - Brightness: 0.78–0.93 — ensures WCAG-adjacent contrast on the dark-
///   mode material background; below 0.78 reads as muddy, above 0.93 blows
///   out text legibility overlaid on the chip.
///
/// Do NOT replace with `.random()` or a generic palette API — these
/// specific ranges are load-bearing for the Cost tab's visual clarity.
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
    ProviderColorPalette.color(for: provider?.providerID ?? "")
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

                if MockProviderDetector.hasAnyMock(in: self.usageData.snapshot) {
                    Section("Diagnostics") {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "testtube.2")
                                .foregroundStyle(.purple)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mock Data Active")
                                    .fontWeight(.medium)
                                Text(
                                    "\(MockProviderDetector.mockCount(in: self.usageData.snapshot)) synthetic providers from Mac. Toggle off in Mac CodexBar → Settings → Mobile → Debug · Mock Provider Data; iPhone updates within ~30s.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Open Source") {
                    Link(destination: URL(string: "https://github.com/o1xhack/CodexBar-Mobile")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("o1xhack/CodexBar-Mobile")
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
                    // When multiple Macs sync and at least one runs an older
                    // CodexBar version than the highest, surface a subtle hint
                    // under the Mac App row. Prompts the user to update the
                    // older Mac so both sides can emit new-schema sync data
                    // (perplexityCredits, loginMethod, budget, etc. — all the
                    // `latestNonNil` fields that silently degrade when an
                    // old Mac refreshes last). Per-device detail appears in
                    // the Devices section below.
                    if self.hasOutdatedMac {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Some Mac devices are on older versions. Update them for complete sync data.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                    Link(destination: URL(string: "https://github.com/o1xhack/CodexBar-Mobile/releases")!) {
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
                                // Per-device Mac version line. Appears only
                                // when the device reported a version (pre-1.1
                                // Macs left it nil — KVS fallback path). If
                                // this device lags the highest-semver Mac in
                                // the synced set, surface an orange "update
                                // available" chip so the user can identify
                                // which specific Mac to update.
                                if let version = device.appVersion {
                                    HStack(spacing: 6) {
                                        Text("CodexBar \(version)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        if self.isDeviceOutdated(device) {
                                            Text("· Update available")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                    }
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

    /// True when 2+ Macs are synced AND at least one runs an older
    /// `appVersion` than the highest-semver one. Drives the orange-tinted
    /// hint under the top-level "Mac App" row. Single-device setups never
    /// trip this (there's nothing to compare against).
    private var hasOutdatedMac: Bool {
        guard self.usageData.deviceSnapshots.count >= 2,
              let latestVersion = self.usageData.snapshot?.appVersion
        else { return false }
        return self.usageData.deviceSnapshots.contains { device in
            guard let deviceVersion = device.appVersion else { return false }
            return CloudSyncReader.semverLessThan(deviceVersion, latestVersion)
        }
    }

    /// True when this specific device's `appVersion` is strictly less than
    /// the highest-semver one across all synced devices. Drives the per-row
    /// "Update available" chip. Uses the same semver comparator as
    /// `CloudSyncReader.mergeSnapshots`'s `max(by:)` selection so the two
    /// views stay in lockstep — no device is both "chosen as the Mac App
    /// version shown at top" AND "flagged as outdated" simultaneously.
    private func isDeviceOutdated(_ device: SyncedUsageSnapshot) -> Bool {
        guard let deviceVersion = device.appVersion,
              let latestVersion = self.usageData.snapshot?.appVersion
        else { return false }
        return CloudSyncReader.semverLessThan(deviceVersion, latestVersion)
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

            // Use cardIdentityKey (providerID|accountEmail) so multi-account
            // and mock-vs-real entries with the SAME providerID don't get
            // collapsed by SwiftUI's diffing. Hit on user QA 2026-05-04 —
            // real `codex|msxiao113@gmail.com` and `codex|alice-mock@codex.test`
            // were rendering as a single row because both had providerID == "codex".
            ForEach(self.device.providers, id: \.cardIdentityKey) { provider in
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.provider.providerName)
                        .fontWeight(.medium)
                    // Email visible at a glance — distinguishes real vs mock
                    // and Codex multi-account on the spot. Hit during user QA
                    // 2026-05-04 (couldn't tell which 'Claude' row was real).
                    if let email = self.provider.accountEmail, !email.isEmpty {
                        Text(email)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("(no email)", comment: "Raw Sync Data row subtitle when provider has no account email (e.g. Claude / Ollama / Copilot)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let cost = self.provider.costSummary {
                        // 30-day cost is what iPhone Cost dashboard
                        // aggregates — show it inline so multi-device sync
                        // bugs are visible at a glance instead of needing
                        // a tap into detail.
                        Text(String(
                            format: String(localized: "$%.2f / 30d", comment: "Raw Sync Data row trailing label — 30-day cost"),
                            cost.last30DaysCostUSD ?? 0))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(
                            format: String(localized: "$%.2f / today", comment: "Raw Sync Data row trailing label — today's cost"),
                            cost.sessionCostUSD ?? 0))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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

    private func formatTokens(_ value: Int) -> String { CostFormatting.tokens(value) }
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
                    PushSetupDiagnosticView()
                } label: {
                    SettingSummaryRow(
                        title: "Push Setup",
                        symbolName: "bell.badge.waveform",
                        summary: "Alert push subscription state")
                }
            } footer: {
                Text("These tools expose internal sync and push state to help diagnose issues.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Developer Tools")
    }
}

// MARK: - Push Setup Diagnostic View

private struct PushSetupDiagnosticView: View {
    @State private var diag = PushSetupDiagnostic.shared
    @State private var persistenceTestResult: String?

    var body: some View {
        List {
            Section("Setup Status") {
                self.row("Zone", self.diag.zoneStatus)
                self.row("Depleted Sub", self.diag.depletedSubStatus)
                self.row("Restored Sub", self.diag.restoredSubStatus)
                self.row("Permission", self.diag.notificationPermission)
                self.row("APNs Registration", self.diag.remoteRegistration)
            }

            Section("Subscription List (from iOS)") {
                Text(self.diag.subscriptionList)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)

                Button("Refresh") {
                    Task {
                        await PushSetupDiagnostic.shared.refreshSubscriptionList()
                    }
                }
                .controlSize(.small)
            }

            if let error = self.diag.lastError {
                Section("Last Error") {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("Actions") {
                Button("Force Re-run Setup") {
                    Task { @MainActor in
                        await QuotaTransitionSubscriptions.shared.setupIfNeeded()
                    }
                }

                Button("Verify Subscription Persistence") {
                    self.persistenceTestResult = "Running…"
                    Task { @MainActor in
                        let result = await QuotaTransitionSubscriptions.shared.runPersistenceTest()
                        self.persistenceTestResult = result
                    }
                }

                if let result = self.persistenceTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                        .textSelection(.enabled)
                }
            }

            if let ts = self.diag.lastUpdated {
                Section {
                    Text("Last updated: \(ts.formatted(.dateTime))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle("Push Setup")
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.bold())
            Text(value)
                .font(.caption)
                .foregroundStyle(value.hasPrefix("✓") ? .green :
                    (value.hasPrefix("✗") ? .red : .secondary))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
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
            version: "1.5.3",
            status: String(localized: "Latest"),
            summary: String(localized: "Multi-account display fix on Cost and Subscription Utilization, plus a new cross-version account-link prompt with the related crash fix."),
            sections: [
                .init(
                    title: String(localized: "Recent updates"),
                    items: [
                        String(localized: "Abacus AI and Mistral support — monthly usage and renewal countdown sync to your iPhone, with quota push notifications."),
                        String(localized: "Claude Designs / Daily Routines / Web Sonnet usage bars on the Claude detail page; Cursor Extra budget gauge on the Cursor page."),
                        String(localized: "Synthetic 5h / weekly tokens / search hourly labels render correctly instead of generic fallbacks."),
                        String(localized: "Codex Pro $100 plan badge; estimated cost for newly-released models marked with *."),
                        String(localized: "Two Macs on different CodexBar versions during a rolling upgrade now show a single card per account."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(localized: "Requires CodexBar for Mac 0.23.4 or later for the new providers."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.5.2",
            status: "",
            summary: String(localized: "Primarily resolves multiple Codex accounts failing to display fully on iPhone. After configuring multiple Codex accounts on Mac, iPhone now shows each account as a separate card; Cost, Usage, and Provider Share all attribute correctly per account."),
            sections: [
                .init(
                    title: String(localized: "Stability"),
                    items: [
                        String(localized: "Added a real-data regression test suite covering all 27 providers to ensure sync stability across multi-account and multi-device scenarios."),
                    ]),
                .init(
                    title: String(localized: "Other fixes"),
                    items: [
                        String(localized: "Some accounts (Claude / Ollama / Copilot etc.) being incorrectly hidden in specific scenarios."),
                        String(localized: "Stale sync records left behind by previous Mac sessions persisting on iPhone."),
                        String(localized: "Cards being merged or lost in multi-account scenarios."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(localized: "Update Mac CodexBar to 0.23.6 for these changes to take effect."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.5.1",
            status: "",
            summary: String(localized: "Upstream v0.21–0.23 provider alignment — Abacus AI + Mistral as new providers, Claude Designs / Daily Routines / Web Sonnet bars, Cursor Extra usage, Synthetic 5h-weekly-search lanes. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(localized: "Our GitHub repo was renamed from `o1xhack/CodexBar` to `o1xhack/CodexBar-Mobile` to differentiate from the upstream Mac repo. Existing download links keep working via redirect; nothing in your iCloud sync setup needs to change."),
                        String(localized: "Update Mac CodexBar to **0.23.4 (Build 58.4.1.3.1) or later** for the new providers and accurate Cost numbers — earlier 0.23.x has a Codex parser bug. Download: [github.com/o1xhack/CodexBar-Mobile/releases](https://github.com/o1xhack/CodexBar-Mobile/releases)."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(localized: "Abacus AI support — when you enable Abacus on Mac 0.23+, your iPhone shows the monthly compute-credit usage with billing-cycle countdown. Quota depleted / restored push notifications work like the other 25 providers."),
                        String(localized: "Mistral support — monthly spend and renewal date sync to your iPhone. Push notifications fire on quota events."),
                        String(localized: "Claude extras — Designs, Daily Routines, and Web Sonnet usage bars now appear on the Claude detail page when your account exposes those quotas via OAuth or the Web app."),
                        String(localized: "Cursor Extra usage — on-demand budget gauge from Cursor's menu bar metric is now visible on the Cursor detail page when the budget is enabled."),
                        String(localized: "Synthetic 3-lane labels — five-hour quota, weekly tokens, and search hourly are labeled correctly on the detail page instead of generic Session / Weekly fallback labels."),
                        String(localized: "Codex Pro $100 plan badge — the new Pro $100 / prolite plan names from upstream v0.21 sync through and display in the account-info capsule on each Codex card."),
                        String(localized: "Color palette extended — Abacus uses a warm brown tone, Mistral a vibrant red. Both stay distinct from existing provider colors across cards, charts, and the share image."),
                        String(localized: "Estimated cost for newly-released models — when Mac sees a model name that isn't in its pricing table yet, it uses the closest known model's rate as a temporary estimate and marks the value with * on the Provider Detail cost card. Stops Daily Spend from quietly dropping to $0 the day a fresh model name appears."),
                        String(localized: "Two Macs, one card — when your two Macs are on different CodexBar versions during a rolling upgrade, your iPhone now correctly shows a single card per account rather than duplicates. Works for accounts whose email contains non-ASCII characters (café@…) too."),
                    ]),
                .init(
                    title: String(localized: "Under the hood"),
                    items: [
                        String(localized: "Mac-side ghost-records cleanup — when you disable a provider on Mac or your Codex account identity changes after a Mac upgrade, the old CloudKit record is now actively deleted at the source. Combines with the iOS 1.3.1 display-time filter for double protection against stale cards."),
                        String(localized: "27 providers / 54 push-subscription zones — the push-notification subscription set automatically expands on first launch to cover Abacus AI and Mistral alongside the existing 25 providers."),
                        String(localized: "Wire-format unchanged — iOS 1.3.x users on the same iCloud account see the new providers as fallback cards (color-tinted) without crashing or missing data; existing 25 providers stay fully functional. iOS 1.5.0 adds the structured rendering for the new ones."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.5.0",
            status: "",
            summary: String(localized: "Upstream v0.21–0.23 provider alignment — Abacus AI + Mistral as new providers, Claude Designs / Daily Routines / Web Sonnet bars, Cursor Extra usage, Synthetic 5h-weekly-search lanes. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(localized: "Update Mac CodexBar to **0.23.4 (Build 58.4.1.3.1) or later** for the new providers and accurate Cost numbers — earlier 0.23.x has a Codex parser bug. Download: [github.com/o1xhack/CodexBar-Mobile/releases](https://github.com/o1xhack/CodexBar-Mobile/releases)."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(localized: "Abacus AI support — when you enable Abacus on Mac 0.23+, your iPhone shows the monthly compute-credit usage with billing-cycle countdown. Quota depleted / restored push notifications work like the other 25 providers."),
                        String(localized: "Mistral support — monthly spend and renewal date sync to your iPhone. Push notifications fire on quota events."),
                        String(localized: "Claude extras — Designs, Daily Routines, and Web Sonnet usage bars now appear on the Claude detail page when your account exposes those quotas via OAuth or the Web app."),
                        String(localized: "Cursor Extra usage — on-demand budget gauge from Cursor's menu bar metric is now visible on the Cursor detail page when the budget is enabled."),
                        String(localized: "Synthetic 3-lane labels — five-hour quota, weekly tokens, and search hourly are labeled correctly on the detail page instead of generic Session / Weekly fallback labels."),
                        String(localized: "Codex Pro $100 plan badge — the new Pro $100 / prolite plan names from upstream v0.21 sync through and display in the account-info capsule on each Codex card."),
                        String(localized: "Color palette extended — Abacus uses a warm brown tone, Mistral a vibrant red. Both stay distinct from existing provider colors across cards, charts, and the share image."),
                        String(localized: "Estimated cost for newly-released models — when Mac sees a model name that isn't in its pricing table yet, it uses the closest known model's rate as a temporary estimate and marks the value with * on the Provider Detail cost card. Stops Daily Spend from quietly dropping to $0 the day a fresh model name appears."),
                        String(localized: "Two Macs, one card — when your two Macs are on different CodexBar versions during a rolling upgrade, your iPhone now correctly shows a single card per account rather than duplicates. Works for accounts whose email contains non-ASCII characters (café@…) too."),
                    ]),
                .init(
                    title: String(localized: "Under the hood"),
                    items: [
                        String(localized: "Mac-side ghost-records cleanup — when you disable a provider on Mac or your Codex account identity changes after a Mac upgrade, the old CloudKit record is now actively deleted at the source. Combines with the iOS 1.3.1 display-time filter for double protection against stale cards."),
                        String(localized: "27 providers / 54 push-subscription zones — the push-notification subscription set automatically expands on first launch to cover Abacus AI and Mistral alongside the existing 25 providers."),
                        String(localized: "Wire-format unchanged — iOS 1.3.x users on the same iCloud account see the new providers as fallback cards (color-tinted) without crashing or missing data; existing 25 providers stay fully functional. iOS 1.5.0 adds the structured rendering for the new ones."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.3.0",
            status: "",
            summary: String(localized: "Upstream v0.20 provider alignment — Perplexity + OpenCode Go, Codex multi-account cards, SwiftData-backed local cache. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(localized: "Update CodexBar on Mac to 0.20.3 (Build 55.3.1.3.0) or later to see Perplexity's structured credit breakdown (recurring / promo / purchased pools + Pro/Max plan + renewal countdown). Older Mac versions fall back to the legacy 3-bar rendering on the Perplexity detail page. Download from github.com/o1xhack/CodexBar-Mobile/releases."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(localized: "Perplexity credit breakdown — when Mac 0.20.3+ is installed, the Perplexity detail page shows a stacked 3-segment bar for monthly / bonus / purchased credits, a Pro/Max plan badge, and a renewal-date countdown."),
                        String(localized: "OpenCode Go support — separate provider from OpenCode Zen with its own tint (mint) and push subscriptions; cards are visually distinguishable at a glance even with both products enabled."),
                        String(localized: "Codex multi-account cards — if you have 2+ Codex accounts (e.g. a personal Pro and a work Business account), each now renders as its own card with the email as the subtitle. Accounts without an email get a localized ordinal fallback (\"Codex 2\", etc.)."),
                        String(localized: "Full push-notification coverage — quota depleted / restored pushes now work for Perplexity and OpenCode Go in addition to the 23 existing providers."),
                        String(localized: "Provider color palette consolidated — every tab and card uses the same color for a given provider, so the Subscription Utilization chart, the provider list, the share card, and the detail page all agree."),
                    ]),
                .init(
                    title: String(localized: "Under the hood"),
                    items: [
                        String(localized: "SwiftData-backed local cache — cold start time for Usage / Cost tabs reduced from 2-5 seconds to under 200 ms. Data persists across app relaunches instead of re-fetching from CloudKit every time."),
                        String(localized: "Per-provider CloudKit records with zlib compression — removes the 1 MB-per-record hard cap that long-term users were approaching as their utilization history grew."),
                        String(localized: "Push-driven incremental sync — Mac changes now land on iPhone within ~500 ms via CloudKit silent pushes instead of waiting for the next manual refresh."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.2.0",
            status: "",
            summary: String(localized: "Subscription Utilization, multi-Mac sync, and push notifications from Mac."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(localized: "You must update CodexBar on Mac to 0.19.0 (Build 54.1.2.0) or later to use this release. Subscription Utilization data collection and Mac→iOS push notifications both depend on Mac-side changes in that version. Download from github.com/o1xhack/CodexBar-Mobile/releases."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(localized: "Subscription Utilization visualization — see how much of each session / weekly / opus quota you're using, per provider and across all providers. 30-day daily bar chart in the Cost tab with Today / This Week / 14 Days / 30 Days summary cards, plus a utilization history chart on every provider detail page."),
                        String(localized: "Multi-Mac data merge — if you run CodexBar on more than one Mac, data from all of them is deduped by hour and combined on iPhone, so your iPhone charts stay consistent regardless of which Mac was last active."),
                        String(localized: "Push notifications from Mac — when a session quota hits 0% or becomes available again on any of your Macs, your iPhone receives a localized notification that includes the provider name (e.g. \"Codex session quota depleted\" / \"Codex 的会话额度已耗尽\"). Background App Refresh does not need to be enabled."),
                    ]),
                .init(
                    title: String(localized: "Improvements"),
                    items: [
                        String(localized: "Settings and Developer Tools streamlined — Setup Guide promoted to the top of Settings; Push Diagnostic tool added under Developer Tools to inspect the Mac→iOS push chain; redundant How It Works sections removed."),
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
                        String(localized: "Version 1.1.0 requires the latest CodexBar Mac app (0.18.0-mobile-1.1.0 or later) to unlock CloudKit sync. Download it from GitHub: github.com/o1xhack/CodexBar-Mobile/releases"),
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

                                // Use LocalizedStringKey init so markdown
                                // (specifically `[label](url)` links) renders
                                // as tappable, with bold / italic also
                                // honored. Existing items without markdown
                                // syntax continue to render as plain text.
                                Text(.init(item))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .tint(.accentColor)
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
