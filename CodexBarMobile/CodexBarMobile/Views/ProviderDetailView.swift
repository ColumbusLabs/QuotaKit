import Charts
import CodexBarSync
import SwiftUI

struct ProviderDetailView: View {
    /// All accounts for the provider whose row the user tapped. When
    /// `group.hasMultipleAccounts`, a segmented control at the top of
    /// the body switches between accounts and the rest of the view
    /// re-renders against the selected snapshot — mirroring Mac's
    /// "click into provider menu → tabs" UX.
    let group: ProviderAccountGroup
    let isDemoMode: Bool
    @Environment(ProEntitlementStore.self) private var proEntitlementStore
    @Environment(RemoteConfigStore.self) private var remoteConfigStore

    @State private var selectedAccountIndex: Int = 0

    @AppStorage(MobileSettingsKeys.usageCostChartStyle) private var chartStyleRawValue = CostChartStyle.bars.rawValue
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidePersonalInfo = false
    @State private var selectedDate: String?

    /// Single-account convenience init — used by call sites that
    /// haven't been refactored to pass a group yet (e.g., `RawProviderDetailView`
    /// in `ContentView`, SwiftUI previews). Wraps the snapshot in a
    /// 1-element group so the body code path is uniform.
    init(provider: ProviderUsageSnapshot, isDemoMode: Bool = false) {
        self.group = ProviderAccountGroup(
            providerID: provider.providerID,
            providerName: provider.providerName,
            accounts: [provider])
        self.isDemoMode = isDemoMode
    }

    /// Multi-account init — preferred path from the post-merge,
    /// post-grouping Usage list.
    init(group: ProviderAccountGroup, isDemoMode: Bool = false) {
        self.group = group
        self.isDemoMode = isDemoMode
    }

    /// Computed accessor for the currently-selected snapshot. **All
    /// downstream rendering code references `self.provider`** — this
    /// computed property is the only thing that changes when the user
    /// taps a different tab. Keeps the body code identical to the
    /// pre-refactor single-account version.
    private var provider: ProviderUsageSnapshot {
        guard self.group.accounts.indices.contains(self.selectedAccountIndex) else {
            return self.group.accounts[0]
        }
        return self.group.accounts[self.selectedAccountIndex]
    }

    private var chartStyle: CostChartStyle {
        CostChartStyle(rawValue: self.chartStyleRawValue) ?? .bars
    }

    /// True when the displayed provider holds synthetic mock data.
    /// Drives the MOCK badge in the nav header.
    private var isMockProvider: Bool {
        MockProviderDetector.isMock(self.provider)
    }

    private var isUsageHistoryUnlocked: Bool {
        ProFeatureAccess.isUnlocked(
            .usageHistory,
            isDemoMode: self.isDemoMode,
            isProUnlocked: self.proEntitlementStore.isProUnlocked,
            isRemotelyDisabled: self.remoteConfigStore.isDisabled(.usageHistory))
    }

    private var isCostDetailUnlocked: Bool {
        ProFeatureAccess.isUnlocked(
            .fullCostDashboard,
            isDemoMode: self.isDemoMode,
            isProUnlocked: self.proEntitlementStore.isProUnlocked,
            isRemotelyDisabled: self.remoteConfigStore.isDisabled(.fullCostDashboard))
    }

    private var hasLockedDetailContent: Bool {
        guard !self.isUsageHistoryUnlocked || !self.isCostDetailUnlocked else { return false }
        if !self.isCostDetailUnlocked {
            if self.provider.costSummary != nil || self.provider.budget != nil { return true }
        }
        if !self.isUsageHistoryUnlocked {
            if let history = self.provider.utilizationHistory, !history.isEmpty { return true }
        }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if self.group.hasMultipleAccounts {
                    self.accountTabBar
                }
                self.providerIdentityHeader
                if self.isMockProvider {
                    self.mockBanner
                }

                ProviderDetailPrimarySectionView(
                    section: ProviderDetailSectionDispatcher.primarySection(for: self.provider),
                    tintColor: self.providerColor)
                {
                    self.rateLimitSection
                }

                ForEach(ProviderDetailSectionDispatcher.sections(
                    for: self.provider,
                    hasRateWindowPace: self.hasRateWindowPace))
                { section in
                    ProviderDetailSectionView(section: section, tintColor: self.providerColor)
                }

                // Claude peak-hours indicator (Anthropic peak window
                // 8am-2pm America/New_York, weekdays). Pure time-of-day
                // logic in `ClaudePeakHours` — no wire field involved.
                if self.provider.providerID == "claude" {
                    self.claudePeakHoursSection
                }

                // Cost summary grid
                if let cost = self.provider.costSummary,
                   cost.sessionCostUSD != nil || cost.last30DaysCostUSD != nil,
                   self.isCostDetailUnlocked
                {
                    self.costSummarySection(cost)
                }

                // Budget progress
                if let budget = self.provider.budget, self.isCostDetailUnlocked {
                    BudgetProgressView(budget: budget, tintColor: self.providerColor)
                }

                // Utilization history chart
                if let history = self.provider.utilizationHistory, !history.isEmpty, self.isUsageHistoryUnlocked {
                    UtilizationHistoryView(series: history, tintColor: self.providerColor)
                }

                // Daily chart
                if let cost = self.provider.costSummary, !cost.daily.isEmpty, self.isCostDetailUnlocked {
                    self.dailyChartSection(cost.daily, currencyCode: cost.currencyCode)
                }

                if self.hasLockedDetailContent {
                    ProFeatureLockedCard(
                        store: self.proEntitlementStore,
                        feature: .usageHistory,
                        message: String(
                            localized: "Unlock QuotaKit Pro to view usage history charts, cost details, budgets, and daily spend for this provider."))
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

    private var providerIdentityHeader: some View {
        HStack(spacing: 12) {
            ProviderBrandMark(
                providerID: self.provider.providerID,
                size: 28,
                tint: self.providerColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(self.provider.providerName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if self.isMockProvider {
                        MockBadgeView()
                    }
                }

                if let subtitle = self.providerIdentitySubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }

    private var providerIdentitySubtitle: String? {
        if let accountEmail = self.provider.accountEmail, !accountEmail.isEmpty {
            return MobilePersonalInfoRedactor.redactEmail(accountEmail, isEnabled: self.hidePersonalInfo)
        }
        if let loginMethod = self.provider.loginMethod, !loginMethod.isEmpty {
            return MobilePersonalInfoRedactor.redactEmails(
                in: loginMethod,
                isEnabled: self.hidePersonalInfo) ?? loginMethod
        }
        return nil
    }

    /// Inline banner at the top of the detail page reminding the user
    /// Segmented control at the top of the detail view — one tab per
    /// account in `group`. Mirrors Mac's per-provider account tabs
    /// (e.g., OpenAI menu card showing `admin-msxiao113 / admin-outlook`).
    /// Resets `selectedDate` (daily-chart hover state) on tab switch so
    /// the chart hover from one account doesn't bleed into another.
    private var accountTabBar: some View {
        Picker(
            selection: Binding(
                get: { self.selectedAccountIndex },
                set: { newIndex in
                    self.selectedAccountIndex = newIndex
                    // A tab switch changes the daily series. Keep the detail
                    // card useful immediately by selecting that account's
                    // latest day instead of carrying a stale day key across
                    // accounts.
                    let daily = self.group.accounts.indices.contains(newIndex)
                        ? self.group.accounts[newIndex].costSummary?.daily ?? []
                        : []
                    self.selectedDate = ProviderDailySpendPresentation.latestDayKey(in: daily)
                }),
            label: Text(""))
        {
            ForEach(self.group.accounts.indices, id: \.self) { index in
                Text(self.group.tabLabel(forIndex: index))
                    .tag(index)
                    .accessibilityIdentifier(
                        self.group.tabAccessibilityIdentifier(forIndex: index))
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("provider-account-tab-bar-\(self.group.providerID)")
    }

    /// this provider's data is synthetic. Mirrors the global
    /// `MockProviderBanner` in spirit (so users hitting the detail page
    /// directly without seeing the global banner still understand) but
    /// scoped to this single provider.
    private var mockBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "testtube.2")
                .font(.subheadline.bold())
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("This is mock data")
                    .font(.caption.bold())
                Text(
                    "Synthetic provider injected by Mac for testing. Real numbers are restored ~30s after Mac toggles mock off.")
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
                .fill(Color.secondary.opacity(0.08)))
    }

    private var hasRateWindowPace: Bool {
        self.provider.allRateWindows.contains { $0.pace != nil }
    }

    // MARK: - Rate Limits

    @ViewBuilder
    private var rateLimitSection: some View {
        let windows = self.provider.allRateWindows
        if !windows.isEmpty {
            VStack(spacing: 12) {
                ForEach(Array(windows.enumerated()), id: \.offset) { index, window in
                    let warning = self.provider.quotaWarning(forWindowIndex: index)
                    UsageCardView(
                        label: window.label ?? self.defaultLabel(at: index),
                        window: window,
                        tintColor: self.providerColor,
                        percentageAccessibilityIdentifier: "provider-detail-percent-\(self.provider.providerID)-\(index)",
                        quotaWarningThresholds: warning.thresholds,
                        quotaWarningsEnabled: warning.enabled)
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
        let today = cost.todayTotals(providerLastUpdated: self.provider.lastUpdated)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Cost & Usage")
                .font(.headline)
                .padding(.top, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let todayCost = today.costUSD {
                    CostMetricCard(
                        title: "Today",
                        value: CostFormatting.cost(todayCost, currencyCode: cost.currencyCode),
                        subtitle: today.tokens.map { Self.formatTokens($0) },
                        tintColor: self.providerColor,
                        isEstimated: today.isEstimated == true)
                } else {
                    CostMetricCard(
                        title: "Today",
                        value: "—",
                        subtitle: String(localized: "Not updated today"),
                        tintColor: self.providerColor)
                }
                if let monthCost = cost.last30DaysCostUSD {
                    CostMetricCard(
                        // Reflect the Mac's configurable 1–365 day window (gap F)
                        // instead of a hardcoded "30 Days"; nil/30 → "30 Days".
                        title: cost.historyDays.flatMap {
                            $0 == 30 ? nil : LocalizedStringResource("\($0) Days")
                        } ?? "30 Days",
                        value: CostFormatting.cost(monthCost, currencyCode: cost.currencyCode),
                        subtitle: Self.costSubtitle(
                            tokens: cost.last30DaysTokens,
                            requests: cost.last30DaysRequests),
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

    private func dailyChartSection(_ daily: [SyncDailyPoint], currencyCode: String?) -> some View {
        // Precompute axis values once per section build. `daily` is stable across
        // `selectedDate` hover changes, so pulling this out of the `.chartYAxis`
        // closure eliminates redundant axis recomputation on every chart re-render.
        let yAxisValues = MobileChartAxisFormatter.axisValues(for: daily.map(\.costUSD))
        // Resolve a latest-day fallback for the first render. The state is
        // initialized on appearance below, while this fallback keeps the
        // selected mark and detail card visible during that first pass.
        let selectedDayKey = self.selectedDate
            ?? ProviderDailySpendPresentation.latestDayKey(in: daily)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Daily Spend")
                    .font(.headline)
                Text("(\(currencyCode ?? "USD"))")
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

                if selectedDayKey == point.dayKey {
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
            .accessibilityIdentifier("provider-daily-spend-chart-\(self.provider.providerID)")
            .accessibilityLabel(Text("Daily Spend"))
            .accessibilityValue(
                Text(
                    ProviderDailySpendPresentation.accessibilityValue(
                        for: daily,
                        selectedDayKey: selectedDayKey,
                        currencyCode: currencyCode)))
            .accessibilityAdjustableAction { direction in
                self.adjustDailySelection(direction, in: daily)
            }
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
            .qkCardBackground(cornerRadius: 14)

            if let selectedDayKey,
               let point = daily.first(where: { $0.dayKey == selectedDayKey })
            {
                ProviderDailySpendDetailCard(
                    detail: ProviderDailySpendPresentation.detail(for: point),
                    currencyCode: currencyCode,
                    tintColor: self.providerColor,
                    viewportRowCount: ProviderDailySpendPresentation.detailViewportRowCount(in: daily),
                    onAdjustSelection: { direction in
                        self.adjustDailySelection(direction, in: daily)
                    })
            }
        }
        .onAppear {
            self.selectLatestDayIfNeeded(in: daily)
        }
        .onChange(of: daily.map(\.dayKey)) { _, _ in
            self.selectLatestDayIfNeeded(in: daily)
        }
    }

    private func selectLatestDayIfNeeded(in daily: [SyncDailyPoint]) {
        guard let latest = ProviderDailySpendPresentation.latestDayKey(in: daily) else {
            self.selectedDate = nil
            return
        }
        guard self.selectedDate == nil || !daily.contains(where: { $0.dayKey == self.selectedDate }) else {
            return
        }
        self.selectedDate = latest
    }

    private func adjustDailySelection(
        _ direction: AccessibilityAdjustmentDirection,
        in daily: [SyncDailyPoint])
    {
        let keys = ProviderDailySpendPresentation.orderedDayKeys(in: daily)
        guard !keys.isEmpty else { return }
        let currentKey = self.selectedDate ?? keys.last!
        guard let currentIndex = keys.firstIndex(of: currentKey) else {
            self.selectedDate = keys.last
            return
        }
        let offset = direction == .increment ? 1 : -1
        let nextIndex = min(max(currentIndex + offset, 0), keys.count - 1)
        self.selectedDate = keys[nextIndex]
    }

    // MARK: - Chart Constants

    private static let chartVisibleDays = 30

    private static func chartScrollInitialDayKey(daily: [SyncDailyPoint]) -> String {
        let startIndex = max(0, daily.count - self.chartVisibleDays)
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

    static func formatUSD(_ value: Double) -> String {
        CostFormatting.usd(value)
    }

    static func formatTokens(_ count: Int) -> String {
        CostFormatting.tokens(count)
    }

    /// Cost-card subtitle combining the token count with an optional request
    /// count (upstream #1163; nil for providers/Mac builds without it).
    static func costSubtitle(tokens: Int?, requests: Int?) -> String? {
        var parts: [String] = []
        if let tokens { parts.append(Self.formatTokens(tokens)) }
        if let requests, requests > 0 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.usesGroupingSeparator = true
            let n = f.string(from: NSNumber(value: requests)) ?? "\(requests)"
            parts.append(String(format: String(localized: "cost_requests_inline", defaultValue: "%@ req"), n))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Daily Spend presentation model

/// A testable, provider-detail-only projection of one synced daily point.
/// Keeping this separate from `SyncCostBreakdown` lets the view aggregate
/// duplicate model labels defensively while preserving optional wire fields
/// from older Mac payloads.
struct ProviderDailySpendModelRow: Identifiable, Equatable {
    let label: String
    let costUSD: Double
    let totalTokens: Int?
    let isEstimated: Bool
    let standardCostUSD: Double?
    let priorityCostUSD: Double?
    let standardTokens: Int?
    let priorityTokens: Int?

    var id: String {
        self.label
    }

    /// Older payloads may omit `totalTokens`; Codex standard/priority token
    /// fields are a compatible fallback when either field is available.
    var modelTokens: Int? {
        if let totalTokens {
            return totalTokens
        }
        guard self.standardTokens != nil || self.priorityTokens != nil else { return nil }
        return (self.standardTokens ?? 0) + (self.priorityTokens ?? 0)
    }

    static func modeSubtitle(for row: Self, currencyCode: String?) -> String? {
        var parts: [String] = []
        if let standardCost = row.standardCostUSD {
            let cost = CostFormatting.cost(standardCost, currencyCode: currencyCode)
            if let tokens = row.standardTokens {
                parts.append(String(format: String(localized: "Std %1$@ · %2$@"), cost, CostFormatting.tokens(tokens)))
            } else {
                parts.append(String(format: String(localized: "Std %1$@"), cost))
            }
        }
        if let priorityCost = row.priorityCostUSD {
            let cost = CostFormatting.cost(priorityCost, currencyCode: currencyCode)
            if let tokens = row.priorityTokens {
                parts.append(String(format: String(localized: "Fast %1$@ · %2$@"), cost, CostFormatting.tokens(tokens)))
            } else {
                parts.append(String(format: String(localized: "Fast %1$@"), cost))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }
}

struct ProviderDailySpendDetail: Equatable {
    let dayKey: String
    let costUSD: Double
    let totalTokens: Int
    let isEstimated: Bool
    let models: [ProviderDailySpendModelRow]
    let splitSubtitle: String?
}

enum ProviderDailySpendPresentation {
    static let maxVisibleModelRows = 4

    static func orderedDayKeys(in daily: [SyncDailyPoint]) -> [String] {
        Array(Set(daily.map(\.dayKey))).sorted()
    }

    static func latestDayKey(in daily: [SyncDailyPoint]) -> String? {
        self.orderedDayKeys(in: daily).last
    }

    static func detail(for point: SyncDailyPoint) -> ProviderDailySpendDetail {
        var byLabel: [String: Aggregate] = [:]
        for breakdown in point.modelBreakdowns {
            let label = breakdown.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, breakdown.costUSD >= 0 else { continue }
            byLabel[label, default: Aggregate()].add(breakdown)
        }

        let models = byLabel.map { label, aggregate in
            ProviderDailySpendModelRow(
                label: label,
                costUSD: aggregate.costUSD,
                totalTokens: aggregate.totalTokens,
                isEstimated: aggregate.isEstimated,
                standardCostUSD: aggregate.standardCostUSD,
                priorityCostUSD: aggregate.priorityCostUSD,
                standardTokens: aggregate.standardTokens,
                priorityTokens: aggregate.priorityTokens)
        }
        .sorted { lhs, rhs in
            if lhs.costUSD != rhs.costUSD {
                return lhs.costUSD > rhs.costUSD
            }
            let lhsTokens = lhs.modelTokens ?? -1
            let rhsTokens = rhs.modelTokens ?? -1
            if lhsTokens != rhsTokens {
                return lhsTokens > rhsTokens
            }
            return lhs.label > rhs.label
        }

        return ProviderDailySpendDetail(
            dayKey: point.dayKey,
            costUSD: point.costUSD,
            totalTokens: point.totalTokens,
            isEstimated: point.isEstimated == true || models.contains(where: \.isEstimated),
            models: models,
            splitSubtitle: CodexCostSplit.subtitle(summing: point.modelBreakdowns))
    }

    static func detailViewportRowCount(for itemCount: Int) -> Int {
        min(max(itemCount, 0), self.maxVisibleModelRows)
    }

    /// Matches the Mac chart's stable detail viewport: reserve rows for the
    /// largest model mix in the loaded range so scrubbing between days does
    /// not make the card jump in height.
    static func detailViewportRowCount(in daily: [SyncDailyPoint]) -> Int {
        let largestModelMix = daily.map { self.detail(for: $0).models.count }.max() ?? 0
        return self.detailViewportRowCount(for: largestModelMix)
    }

    static func rowsNeedScrolling(itemCount: Int) -> Bool {
        itemCount > self.maxVisibleModelRows
    }

    static func accessibilityValue(
        for daily: [SyncDailyPoint],
        selectedDayKey: String?,
        currencyCode: String?) -> String
    {
        guard let selectedDayKey,
              let point = daily.first(where: { $0.dayKey == selectedDayKey })
        else {
            return String(localized: "No cost history data")
        }
        return self.accessibilityValue(for: self.detail(for: point), currencyCode: currencyCode)
    }

    static func accessibilityValue(
        for detail: ProviderDailySpendDetail,
        currencyCode: String?) -> String
    {
        var parts = [
            detail.dayKey,
            CostFormatting.cost(detail.costUSD, currencyCode: currencyCode),
            CostFormatting.tokens(detail.totalTokens),
        ]
        if detail.isEstimated {
            parts.append(String(localized: "Estimated"))
        }
        return parts.joined(separator: " · ")
    }

    private struct Aggregate {
        var costUSD = 0.0
        var totalTokens: Int?
        var isEstimated = false
        var standardCostUSD: Double?
        var priorityCostUSD: Double?
        var standardTokens: Int?
        var priorityTokens: Int?

        mutating func add(_ breakdown: SyncCostBreakdown) {
            self.costUSD += breakdown.costUSD
            if let tokens = breakdown.modelTokens {
                self.totalTokens = (self.totalTokens ?? 0) + tokens
            }
            self.isEstimated = self.isEstimated || breakdown.isEstimated == true
            self.standardCostUSD = Self.sumOptional(self.standardCostUSD, breakdown.standardCostUSD)
            self.priorityCostUSD = Self.sumOptional(self.priorityCostUSD, breakdown.priorityCostUSD)
            self.standardTokens = Self.sumOptional(self.standardTokens, breakdown.standardTokens)
            self.priorityTokens = Self.sumOptional(self.priorityTokens, breakdown.priorityTokens)
        }

        private static func sumOptional(_ lhs: Double?, _ rhs: Double?) -> Double? {
            guard lhs != nil || rhs != nil else { return nil }
            return (lhs ?? 0) + (rhs ?? 0)
        }

        private static func sumOptional(_ lhs: Int?, _ rhs: Int?) -> Int? {
            guard lhs != nil || rhs != nil else { return nil }
            return (lhs ?? 0) + (rhs ?? 0)
        }
    }
}

private struct ProviderDailySpendDetailCard: View {
    let detail: ProviderDailySpendDetail
    let currencyCode: String?
    let tintColor: Color
    let viewportRowCount: Int
    let onAdjustSelection: (AccessibilityAdjustmentDirection) -> Void

    private static let rowHeight: CGFloat = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.detail.dayKey)
                        .font(.subheadline.weight(.semibold))
                    if self.detail.isEstimated {
                        Text("* \(String(localized: "Estimated"))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(CostFormatting.cost(self.detail.costUSD, currencyCode: self.currencyCode))
                        .font(.headline.monospacedDigit())
                        .fontWeight(.semibold)
                    Text(CostFormatting.tokens(self.detail.totalTokens))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let split = self.detail.splitSubtitle {
                Text(split)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if self.viewportRowCount > 0 {
                Divider()
                Text("Model Mix")
                    .font(.subheadline.weight(.semibold))
                if self.detail.models.isEmpty {
                    Text("No data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: Self.rowHeight * CGFloat(self.viewportRowCount),
                            alignment: .topLeading)
                        .accessibilityIdentifier("provider-daily-spend-model-list")
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(self.detail.models) { row in
                                self.modelRow(row)
                            }
                        }
                    }
                    // Keep the detail viewport stable as the selected day changes;
                    // users can scroll to any models beyond the four-row window.
                    .frame(height: Self.rowHeight * CGFloat(self.viewportRowCount))
                    .scrollIndicators(
                        ProviderDailySpendPresentation.rowsNeedScrolling(itemCount: self.detail.models.count)
                            ? .visible
                            : .hidden)
                    .accessibilityIdentifier("provider-daily-spend-model-list")
                }
            }
        }
        .padding(14)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("provider-daily-spend-selection-detail")
        .accessibilityLabel(Text("Daily Spend"))
        .accessibilityValue(
            Text(
                ProviderDailySpendPresentation.accessibilityValue(
                    for: self.detail,
                    currencyCode: self.currencyCode)))
        .accessibilityAdjustableAction { direction in
            self.onAdjustSelection(direction)
        }
    }

    private func modelRow(_ row: ProviderDailySpendModelRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(self.tintColor.opacity(0.75))
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let mode = ProviderDailySpendModelRow.modeSubtitle(for: row, currencyCode: self.currencyCode) {
                    Text(mode)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    CostFormatting.cost(row.costUSD, currencyCode: self.currencyCode)
                        + (row.isEstimated ? " *" : ""))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.medium)
                if let tokens = row.modelTokens {
                    Text(CostFormatting.tokens(tokens))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: Self.rowHeight, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("provider-daily-spend-model-row-\(row.id)")
        .accessibilityValue(
            Text(
                ProviderDailySpendModelRow.accessibilityValue(
                    row,
                    currencyCode: self.currencyCode)))
    }
}

extension ProviderDailySpendModelRow {
    static func accessibilityValue(_ row: Self, currencyCode: String?) -> String {
        var parts = [CostFormatting.cost(row.costUSD, currencyCode: currencyCode)]
        if let tokens = row.modelTokens {
            parts.append(CostFormatting.tokens(tokens))
        }
        if row.isEstimated {
            parts.append(String(localized: "Estimated"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Previews

#Preview("With Cost Data") {
    NavigationStack {
        ProviderDetailView(provider: PreviewData.claudeProvider)
    }
    .environment(ProEntitlementStore.preview(state: .unlocked(source: .storeKit)))
    .environment(RemoteConfigStore())
}

#Preview("No Cost Data") {
    NavigationStack {
        ProviderDetailView(provider: PreviewData.cursorProvider)
    }
    .environment(ProEntitlementStore.preview(state: .unlocked(source: .storeKit)))
    .environment(RemoteConfigStore())
}
