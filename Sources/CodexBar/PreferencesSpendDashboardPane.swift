import AppKit
import Charts
import CodexBarCore
import SwiftUI
import UniformTypeIdentifiers

func spendDashboardDayRangeText(_ days: Int) -> String {
    if days >= SpendDashboardSource.scanDays {
        return L("All")
    }
    let template: String
    switch days {
    case 7: template = L("7d")
    case 30: template = L("30d")
    case 90: template = L("90d")
    default: return codexBarLocalizedInteger(days)
    }
    return template.replacingOccurrences(
        of: String(days),
        with: codexBarLocalizedInteger(days))
}

func spendDashboardRankText(_ rank: Int) -> String {
    "#\(codexBarLocalizedInteger(rank))"
}

func spendDashboardRefreshFailureText(_ count: Int) -> String {
    "\(L("Refresh failures")): \(codexBarLocalizedInteger(count))"
}

func spendDashboardCoverageText(covered: Int, requested: Int) -> String {
    "\(L("Coverage")): \(codexBarLocalizedInteger(covered)) / \(codexBarLocalizedInteger(requested))"
}

func spendDashboardTokenMixValue(_ value: Int?) -> String {
    value.map(UsageFormatter.tokenCountString) ?? "—"
}

func spendDashboardMetricText(
    cost: Double?,
    tokens: Int?,
    currencyCode: String,
    incompleteRequestCount: Int = 0,
    costIsLowerBound: Bool = false,
    tokensAreLowerBound: Bool = false) -> String
{
    // A truncated scan or an unpriced request makes the subtotal a floor, not an exact value.
    // The row must say so with the same `≥` marker the header and menu card already use.
    let parts = [
        cost.map {
            spendDashboardLowerBoundText(
                UsageFormatter.currencyString($0, currencyCode: currencyCode), isLowerBound: costIsLowerBound)
        },
        tokens.map {
            spendDashboardLowerBoundText(
                L("%@ tokens", UsageFormatter.tokenCountString($0)), isLowerBound: tokensAreLowerBound)
        },
    ].compactMap(\.self)
    return (parts.isEmpty ? "—" : parts.joined(separator: " · "))
        + UsageFormatter.incompleteUsageSuffix(incompleteRequestCount)
}

func spendDashboardLowerBoundText(_ value: String, isLowerBound: Bool) -> String {
    isLowerBound ? "≥ \(value)" : value
}

func spendDashboardCoverageChipText(_ coverage: CostUsageCoverageCounts) -> String {
    "\(L("Priced")) \(codexBarLocalizedInteger(coverage.priced)) · "
        + "\(L("Unpriced")) \(codexBarLocalizedInteger(coverage.unpriced)) · "
        + "\(L("Unmetered")) \(codexBarLocalizedInteger(coverage.unmetered)) · "
        + "\(L("Estimated")) \(codexBarLocalizedInteger(coverage.estimated))"
}

func spendDashboardProvenanceText(_ provenance: CostProvenance) -> String {
    switch provenance {
    case .listPriceEstimate: L("List-price equivalent")
    case .vendorMetered: L("Plan metered")
    case .mixed: L("Metered and list-price")
    case .unknown: L("Spend unavailable")
    }
}

func spendDashboardHourlyChartAccessibilityValue(hourCount: Int, serviceCount: Int) -> String {
    switch (hourCount == 1, serviceCount == 1) {
    case (true, true):
        L("1 hour of usage data across 1 service")
    case (false, true):
        L("%d hours of usage data across 1 service", hourCount)
    case (true, false):
        L("1 hour of usage data across %d services", serviceCount)
    case (false, false):
        L("%d hours of usage data across %d services", hourCount, serviceCount)
    }
}

func spendDashboardHourlyPointAccessibilityLabel(
    providerName: String,
    hour: Date,
    timeZone: TimeZone,
    includeDate: Bool,
    locale: Locale = codexBarLocalizedLocale()) -> String
{
    var timeStyle = Date.FormatStyle().hour().minute().locale(locale)
    timeStyle.timeZone = timeZone
    var time = hour.formatted(timeStyle)
    if let abbreviation = timeZone.abbreviation(for: hour), !abbreviation.isEmpty {
        time = "\(time) \(abbreviation)"
    }
    guard includeDate else {
        return "\(providerName), \(time)"
    }
    var dayStyle = Date.FormatStyle().month(.abbreviated).day().locale(locale)
    dayStyle.timeZone = timeZone
    return "\(providerName), \(hour.formatted(dayStyle)), \(time)"
}

func codexCostCatchUpProgressText(_ activity: CodexCostCatchUpActivity) -> String {
    if activity.totalBytes > 0 {
        let processed = ByteCountFormatter.string(
            fromByteCount: activity.processedBytes,
            countStyle: .file)
        let total = ByteCountFormatter.string(
            fromByteCount: activity.totalBytes,
            countStyle: .file)
        return "\(processed) / \(total)"
    }
    if activity.totalFiles > 0 {
        return "\(codexBarLocalizedInteger(activity.completedFiles)) / "
            + codexBarLocalizedInteger(activity.totalFiles)
    }
    return L("Loading…")
}

enum SpendDashboardModelHistoryPresentation: Equatable {
    case unavailable
    case empty
    case partial
    case complete
}

enum SpendDashboardModelMetric: String, CaseIterable {
    case cost
    case tokens

    var title: String {
        switch self {
        case .cost: L("Cost")
        case .tokens: L("Tokens")
        }
    }
}

private func spendDashboardDescending<Value: Comparable>(_ left: Value?, _ right: Value?) -> Bool? {
    switch (left, right) {
    case let (left?, right?) where left != right: left > right
    case (_?, nil): true
    case (nil, _?): false
    default: nil
    }
}

func spendDashboardModelRows(
    _ rows: [SpendDashboardModel.ModelRow],
    metric: SpendDashboardModelMetric) -> [SpendDashboardModel.ModelRow]
{
    rows.enumerated()
        .sorted { lhs, rhs in
            let preferredOrder = switch metric {
            case .cost:
                spendDashboardDescending(lhs.element.totalCost, rhs.element.totalCost)
            case .tokens:
                spendDashboardDescending(lhs.element.totalTokens, rhs.element.totalTokens)
            }
            if let preferredOrder {
                return preferredOrder
            }
            if lhs.element.providerName != rhs.element.providerName {
                return lhs.element.providerName < rhs.element.providerName
            }
            if lhs.element.modelName != rhs.element.modelName {
                return lhs.element.modelName < rhs.element.modelName
            }
            return lhs.offset < rhs.offset
        }
        .enumerated()
        .map { rank, entry in
            SpendDashboardModel.ModelRow(
                rank: rank + 1,
                provider: entry.element.provider,
                providerName: entry.element.providerName,
                modelName: entry.element.modelName,
                totalTokens: entry.element.totalTokens,
                totalCost: entry.element.totalCost)
        }
}

func spendDashboardModelValueText(
    _ row: SpendDashboardModel.ModelRow,
    metric: SpendDashboardModelMetric,
    currencyCode: String) -> String
{
    switch metric {
    case .cost:
        row.totalCost.map {
            UsageFormatter.currencyString($0, currencyCode: currencyCode)
        } ?? "—"
    case .tokens:
        row.totalTokens.map(UsageFormatter.tokenCountString) ?? "—"
    }
}

func spendDashboardModelHistoryPresentation(
    _ group: SpendDashboardModel.CurrencyGroup) -> SpendDashboardModelHistoryPresentation
{
    if group.models.isEmpty {
        return group.modelHistoryCompleteness == .incomplete ? .unavailable : .empty
    }
    return group.modelHistoryCompleteness == .incomplete ? .partial : .complete
}

func spendDashboardModelHistoryPresentation(
    _ group: SpendDashboardModel.CurrencyGroup,
    metric: SpendDashboardModelMetric) -> SpendDashboardModelHistoryPresentation
{
    guard metric == .tokens else {
        return spendDashboardModelHistoryPresentation(group)
    }
    guard !group.models.isEmpty else {
        return spendDashboardModelHistoryPresentation(group)
    }
    let tokenValues = group.models.map(\.totalTokens)
    if tokenValues.allSatisfy({ $0 == nil }) {
        return .unavailable
    }
    if tokenValues.contains(where: { $0 == nil }) {
        return .partial
    }
    return .complete
}

enum SpendDashboardDetailSection: Hashable, Identifiable {
    case providers
    case projects
    case sessions

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .providers: L("Providers")
        case .projects: L("Projects")
        case .sessions: L("Sessions")
        }
    }
}

func spendDashboardAvailableDetailSections(
    hasProjects: Bool,
    hasSessions: Bool) -> [SpendDashboardDetailSection]
{
    var sections: [SpendDashboardDetailSection] = [.providers]
    if hasProjects { sections.append(.projects) }
    if hasSessions { sections.append(.sessions) }
    return sections
}

enum SpendDashboardTrendSection: Hashable, Identifiable {
    case daily
    case hourly

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .daily: L("Daily estimated spend")
        case .hourly: L("Hourly estimated spend")
        }
    }

    var pickerTitle: String {
        switch self {
        case .daily: L("Day")
        case .hourly: L("Hour")
        }
    }
}

func spendDashboardAvailableTrendSections(hasHourlyData: Bool) -> [SpendDashboardTrendSection] {
    hasHourlyData ? [.daily, .hourly] : [.daily]
}

func spendDashboardHasTokenMix(_ group: SpendDashboardModel.CurrencyGroup) -> Bool {
    group.tokenMix.inputTokens != nil
        || group.tokenMix.outputTokens != nil
        || group.tokenMix.cacheReadTokens != nil
        || group.tokenMix.cacheCreationTokens != nil
        || group.tokenMix.reasoningTokens != nil
}

@MainActor
struct SpendDashboardPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @State private var isVisible = false
    @State private var userSelectedBackground = false
    @State private var isDataControlsExpanded = true

    init(settings: SettingsStore, store: UsageStore) {
        self.settings = settings
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                self.header
                self.refreshStatus
                self.codexCostCatchUpPanel
                self.content
                self.dataControls
            }
            .padding(24)
        }
        .background(FocusResigningBackground())
        .onAppear {
            self.isVisible = true
            // #160: persisted selection is presentation preference only. Activate
            // it as ephemeral history demand before the first visible source
            // request so configuration capture sees the active range.
            self.controller.activateHistoryDemandForVisibleDashboard()
            self.controller.update(configuration: self.configuration)
            if !self.controller.isRefreshing {
                self.synchronizeCodexCostCatchUp()
            }
        }
        .onChange(of: self.configuration) { _, configuration in
            self.controller.update(configuration: configuration)
        }
        .onChange(of: self.configuration.codexAccountIdentities) { _, _ in
            if self.isVisible, !self.controller.isRefreshing {
                self.synchronizeCodexCostCatchUp()
            }
        }
        .onChange(of: self.configuration.costUsageEnabled) { _, _ in
            if self.isVisible, !self.controller.isRefreshing {
                self.synchronizeCodexCostCatchUp()
            }
        }
        .onChange(of: self.controller.isRefreshing) { _, isRefreshing in
            if self.isVisible, !isRefreshing {
                self.synchronizeCodexCostCatchUp()
            }
        }
        .onDisappear {
            self.isVisible = false
            // #160 correction: clear ephemeral demand, then synchronously
            // re-scope an in-flight controller load to the routine horizon
            // before routine catch-up. `deactivateHistoryDemand` alone cannot
            // cancel a 365-day load already running; the explicit update lets
            // #159 hard-scope semantics cancel/reject the old wide work.
            // Persisted selection stays intact for the next open.
            self.controller.deactivateHistoryDemand()
            self.controller.update(configuration: self.configuration)
            self.synchronizeCodexCostCatchUp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            self.controller.refreshDateWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            self.controller.refreshDateWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.controller.refreshDateWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .codexbarCurrencyExchangeRatesDidChange)) { _ in
            self.controller.refreshDateWindow()
        }
    }

    private var configuration: SpendDashboardConfiguration {
        SpendDashboardSource.configuration(settings: self.settings, store: self.store)
    }

    private var controller: SpendDashboardController {
        self.store.sharedSpendDashboardController()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Usage & Spend"))
                    .font(.title2.weight(.semibold))
                Text(L("Local estimated cost history across supported providers."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker(L("Time range"), selection: self.periodBinding) {
                Text(spendDashboardDayRangeText(7)).tag(CostReportingPeriod.rolling(days: 7))
                Text(spendDashboardDayRangeText(30)).tag(CostReportingPeriod.rolling(days: 30))
                Text(spendDashboardDayRangeText(90)).tag(CostReportingPeriod.rolling(days: 90))
                Text(L("Month to date")).tag(CostReportingPeriod.monthToDate)
                Text(spendDashboardDayRangeText(365)).tag(CostReportingPeriod.allTime)
                if case let .rolling(days) = self.controller.selectedPeriod, ![7, 30, 90].contains(days) {
                    Text(spendDashboardDayRangeText(days)).tag(self.controller.selectedPeriod)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 248)

            Button {
                self.controller.refresh()
            } label: {
                if self.controller.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L("Refresh"), systemImage: "arrow.clockwise")
                }
            }
            .disabled(self.controller.isRefreshing || !self.settings.costUsageEnabled)
        }
    }

    @ViewBuilder
    private var codexCostCatchUpPanel: some View {
        if let activity = self.store.spendDashboardCodexCostCatchUpActivity,
           activity.phase != .complete
        {
            SpendDashboardPanel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label(
                            self.codexCostCatchUpTitle(activity),
                            systemImage: activity.phase == .paused ? "pause.circle" : "externaldrive")
                            .font(.headline)
                        Spacer()
                        Text(codexCostCatchUpProgressText(activity))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if let progress = activity.fractionCompleted {
                        ProgressView(value: progress)
                    } else if activity.phase == .indexing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let staleSnapshotUpdatedAt = activity.staleSnapshotUpdatedAt {
                        HStack(spacing: 6) {
                            Label(L("stale data"), systemImage: "clock.badge.exclamationmark")
                            Text(L(
                                "Updated relative %@",
                                staleSnapshotUpdatedAt.relativeDescription()))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    }

                    Text(self.codexCostCatchUpDetail(activity))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        if activity.pauseReason == .user
                            || activity.pauseReason == .noProgress
                            || self.codexCostCatchUpHasError(activity)
                        {
                            Button(L("Refresh")) {
                                self.startCodexCostCatchUp(mode: .automatic)
                            }
                        } else if activity.mode == .automatic {
                            Button(L("Finish now")) {
                                self.startCodexCostCatchUp(mode: .accelerated)
                            }
                        } else {
                            Button(L("Continue in background")) {
                                self.userSelectedBackground = true
                                self.startCodexCostCatchUp(mode: .automatic)
                            }
                        }

                        if activity.pauseReason != .user,
                           activity.pauseReason != .noProgress,
                           !self.codexCostCatchUpHasError(activity)
                        {
                            Button(L("Cancel")) {
                                self.store.stopSpendDashboardCodexCostCatchUp()
                            }
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func codexCostCatchUpHasError(_ activity: CodexCostCatchUpActivity) -> Bool {
        if case .error = activity.pauseReason {
            return true
        }
        return false
    }

    private func synchronizeCodexCostCatchUp() {
        guard self.isVisible else {
            self.userSelectedBackground = false
            self.store.synchronizeSpendDashboardCodexCostCatchUp(
                accounts: self.codexSpendScanRequests,
                preferredMode: .automatic)
            return
        }
        let preferredMode: CodexCostCatchUpMode? = self.userSelectedBackground ? nil : .accelerated
        self.store.synchronizeSpendDashboardCodexCostCatchUp(
            accounts: self.codexSpendScanRequests,
            preferredMode: preferredMode)
    }

    private func startCodexCostCatchUp(mode: CodexCostCatchUpMode) {
        if mode == .accelerated {
            self.userSelectedBackground = false
        }
        self.store.startSpendDashboardCodexCostCatchUpIfNeeded(
            accounts: self.codexSpendScanRequests,
            mode: mode)
    }

    private var codexSpendScanRequests: [CodexSpendScanRequest] {
        guard self.configuration.costUsageEnabled,
              self.configuration.providerIDs.contains(UsageProvider.codex.rawValue)
        else { return [] }
        return SpendDashboardSource.codexRequests(settings: self.settings, store: self.store)
    }

    private func codexCostCatchUpTitle(_ activity: CodexCostCatchUpActivity) -> String {
        let prefix = L("Local estimated history")
        switch activity.phase {
        case .indexing:
            return "\(prefix) · \(L("Refreshing"))"
        case .paused:
            return "\(prefix) · \(L("Inactive"))"
        case .complete:
            return "\(prefix) · \(L("Done"))"
        }
    }

    private func codexCostCatchUpDetail(_ activity: CodexCostCatchUpActivity) -> String {
        switch activity.pauseReason {
        case .lowPower:
            L("Battery Saver")
        case .thermal, .user:
            L("Inactive")
        case .noProgress:
            L("Error")
        case let .error(message):
            L("cost_status_error", L("Cost"), message)
        case nil:
            L("Estimated from local Codex logs for the selected account.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if !self.settings.costUsageEnabled {
            SpendDashboardPanel {
                ContentUnavailableView {
                    Label(L("Cost tracking is off"), systemImage: "chart.bar.xaxis")
                } description: {
                    Text(L("Turn on Track costs to build local estimates."))
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        } else if self.controller.model.groups.isEmpty {
            let emptyState = SpendDashboardEmptyState.make(isRefreshing: self.controller.isRefreshing)
            SpendDashboardPanel {
                ContentUnavailableView {
                    Label(emptyState.title, systemImage: "chart.bar.xaxis")
                } description: {
                    Text(emptyState.message)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        } else {
            ForEach(self.controller.model.groups) { group in
                SpendDashboardCurrencySection(
                    group: group,
                    requestedDays: self.controller.model.requestedDays,
                    hidePersonalInfo: self.settings.hidePersonalInfo,
                    onClearSelectedDay: { self.controller.selectDay(nil) })
            }
        }

        if self.settings.costUsageEnabled, !self.controller.model.tokenActivity.isEmpty {
            SpendDashboardPanel {
                SpendActivityHeatmapView(
                    points: self.controller.model.tokenActivity,
                    calendar: self.settings.costUsageBucketCalendar,
                    selectedDay: self.controller.selectedDay,
                    onSelectDay: { day in
                        self.controller.selectDay(day)
                    })
            }
        }
    }

    @ViewBuilder
    private var refreshStatus: some View {
        if self.controller.failedSourceCount > 0 {
            Label(
                spendDashboardRefreshFailureText(self.controller.failedSourceCount),
                systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dataControls: some View {
        SpendDashboardPanel {
            DisclosureGroup(isExpanded: self.$isDataControlsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    self.provenance
                    Divider()
                    self.shareAction
                }
                .padding(.top, 12)
            } label: {
                Label {
                    Text(L("List-price equivalent — not a billing receipt."))
                        .font(.caption)
                } icon: {
                    Image(systemName: "lock.shield.fill")
                }
            }
            .accessibilityIdentifier("spend-dashboard-data-controls")
        }
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L("Track costs"), isOn: self.$settings.costUsageEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
            if self.settings.costUsageEnabled {
                Toggle(L("Include OpenCodex usage logs"), isOn: self.$settings.openCodexUsageLogsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if self.settings.openCodexUsageLogsEnabled {
                    Toggle(
                        L("Hide native Codex when OpenCodex is present"),
                        isOn: self.$settings.hideNativeCodexCostWhenOpenCodexPresent)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                if !self.controller.model.groups.isEmpty {
                    SpendDashboardSourceFilter(settings: self.settings, model: self.controller.model)
                }
            }
        }
    }

    private var shareAction: some View {
        HStack {
            Button {
                self.copyJSON()
            } label: {
                Label(L("Copy JSON"), systemImage: "doc.on.doc")
            }
            .disabled(self.controller.model.groups.isEmpty)
            Button {
                self.exportJSON()
            } label: {
                Label(L("Export JSON"), systemImage: "square.and.arrow.down")
            }
            .disabled(self.controller.model.groups.isEmpty)
            Spacer()
            Button {
                guard let payload = self.sharePayload else { return }
                ShareStatsPresenter.shared.present(payload: payload)
            } label: {
                Label(L("Share Stats…"), systemImage: "square.and.arrow.up")
            }
            .disabled(self.sharePayload == nil)
        }
    }

    private func copyJSON() {
        _ = SpendDashboardJSONExporter.copyToPasteboard(
            model: self.controller.model,
            hiddenSourceIDs: self.settings.spendDashboardHiddenSourceIDs)
    }

    private func exportJSON() {
        _ = SpendDashboardJSONExporter.save(
            model: self.controller.model,
            hiddenSourceIDs: self.settings.spendDashboardHiddenSourceIDs)
    }

    private var sharePayload: ShareStatsPayload? {
        ShareStatsPayloadFactory.make(model: self.controller.model, store: self.store)
    }

    private var periodBinding: Binding<CostReportingPeriod> {
        Binding(
            get: { self.controller.selectedPeriod },
            set: { period in
                self.controller.selectPeriod(period)
                if self.isVisible {
                    self.controller.update(configuration: self.configuration)
                    self.synchronizeCodexCostCatchUp()
                }
            })
    }
}

struct SpendDashboardEmptyState: Equatable {
    let title: String
    let message: String

    static func make(isRefreshing: Bool) -> Self {
        if isRefreshing {
            return Self(
                title: L("Refreshing"),
                message: L("Local estimated cost history across supported providers."))
        }
        return Self(
            title: L("No local cost history yet"),
            message: L("Turn on cost tracking or refresh after using a supported provider."))
    }
}

struct SpendDashboardCurrencySection: View {
    let group: SpendDashboardModel.CurrencyGroup
    let requestedDays: Int
    let hidePersonalInfo: Bool
    let onClearSelectedDay: (() -> Void)?
    @State private var selectedDetailSection: SpendDashboardDetailSection
    @State private var selectedTrendSection: SpendDashboardTrendSection

    init(
        group: SpendDashboardModel.CurrencyGroup,
        requestedDays: Int,
        hidePersonalInfo: Bool = false,
        onClearSelectedDay: (() -> Void)? = nil)
    {
        self.group = group
        self.requestedDays = requestedDays
        self.hidePersonalInfo = hidePersonalInfo
        self.onClearSelectedDay = onClearSelectedDay
        self._selectedDetailSection = State(initialValue: .providers)
        self._selectedTrendSection = State(
            initialValue: group.selectedDay != nil && !group.hourlyPoints.isEmpty ? .hourly : .daily)
    }

    private var availableDetailSections: [SpendDashboardDetailSection] {
        spendDashboardAvailableDetailSections(
            hasProjects: !self.group.projects.isEmpty,
            hasSessions: !self.group.sessions.isEmpty)
    }

    private var activeDetailSection: SpendDashboardDetailSection {
        self.availableDetailSections.contains(self.selectedDetailSection)
            ? self.selectedDetailSection : .providers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(self.group.currencyCode)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(spendDashboardHistoryCaption(self.group, requestedDays: self.requestedDays))
                .font(.caption)
                .foregroundStyle(.secondary)

            SpendDashboardSummary(
                group: self.group,
                onClearSelectedDay: self.onClearSelectedDay)

            if self.availableDetailSections.count > 1 {
                Picker(L("Usage & Spend"), selection: self.$selectedDetailSection) {
                    ForEach(self.availableDetailSections) { section in
                        Text(section.title).tag(section)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: 460, alignment: .leading)
                .accessibilityIdentifier("spend-dashboard-detail-picker")
            }

            if self.activeDetailSection == .providers {
                SpendDashboardPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Usage & Spend")).font(.headline)
                        SpendProviderBreakdownRows(
                            group: self.group,
                            hidePersonalInfo: self.hidePersonalInfo)
                    }
                }
            } else if self.activeDetailSection == .projects {
                SpendProjectPanel(group: self.group, hidePersonalInfo: self.hidePersonalInfo)
            } else {
                SpendSessionPanel(group: self.group, hidePersonalInfo: self.hidePersonalInfo)
            }
            if !self.group.hourlyPoints.isEmpty {
                Picker(L("Usage & Spend"), selection: self.$selectedTrendSection) {
                    ForEach(spendDashboardAvailableTrendSections(hasHourlyData: true)) { section in
                        Text(section.pickerTitle).tag(section)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 140)
                .accessibilityIdentifier("spend-dashboard-trend-picker")
            }
            if self.selectedTrendSection == .hourly, !self.group.hourlyPoints.isEmpty {
                SpendHourlyChart(group: self.group)
            } else {
                SpendDailyChart(group: self.group)
            }
            SpendDailyLedger(group: self.group, hidePersonalInfo: self.hidePersonalInfo)
        }
        .environment(\.timeZone, self.group.timeZone)
        .environment(\.calendar, self.group.calendar)
        .onChange(of: self.group.selectedDay) { _, selectedDay in
            self.selectedTrendSection = selectedDay != nil && !self.group.hourlyPoints.isEmpty
                ? .hourly : .daily
        }
    }
}

private struct SpendProjectPanel: View {
    let group: SpendDashboardModel.CurrencyGroup
    let hidePersonalInfo: Bool
    @State private var showsAllRows = false

    private static let collapsedRowCount = 8

    var body: some View {
        SpendDashboardPanel {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Projects")).font(.headline).padding(.bottom, 8)
                ForEach(self.visibleRows) { row in
                    if row.rank > 1 {
                        Divider()
                    }
                    HStack(spacing: 10) {
                        Text(spendDashboardRankText(row.rank))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 26, alignment: .leading)
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayIdentity(hidePersonalInfo: self.hidePersonalInfo).name).lineLimit(1)
                            Text(row.providerName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(spendDashboardMetricText(
                            cost: row.totalCost,
                            tokens: row.totalTokens,
                            currencyCode: self.group.currencyCode))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 9)
                }
                SpendPanelExpandButton(
                    rowCount: self.group.projects.count,
                    collapsedRowCount: Self.collapsedRowCount,
                    showsAllRows: self.$showsAllRows)
            }
        }
    }

    private var visibleRows: ArraySlice<SpendDashboardModel.ProjectRow> {
        self.group.projects.prefix(
            self.showsAllRows ? self.group.projects.count : Self.collapsedRowCount)
    }
}

private struct SpendPanelExpandButton: View {
    let rowCount: Int
    let collapsedRowCount: Int
    @Binding var showsAllRows: Bool

    var body: some View {
        if self.rowCount > self.collapsedRowCount {
            Button {
                self.showsAllRows.toggle()
            } label: {
                Text(
                    self.showsAllRows
                        ? L("Show less")
                        : L("Show all (%d)", self.rowCount))
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .padding(.top, 6)
        }
    }
}

struct SpendDailyChartPresentation: Equatable {
    enum Content: Equatable {
        case chart
        case unavailable
    }

    struct Series: Equatable {
        let name: String
        let provider: UsageProvider
    }

    let content: Content
    let series: [Series]
    let dayCount: Int

    init(dailyPoints: [SpendDashboardModel.DailyPoint], aggregateTotal: Double?) {
        self.content = dailyPoints.isEmpty && aggregateTotal == nil ? .unavailable : .chart
        self.dayCount = Set(dailyPoints.map(\.day)).count

        var seenNames: Set<String> = []
        self.series = dailyPoints.compactMap { point in
            guard seenNames.insert(point.providerName).inserted else { return nil }
            return Series(name: point.providerName, provider: point.provider)
        }
    }

    var accessibilityValue: String {
        L("%d days of usage data across %d services", self.dayCount, self.series.count)
    }
}

/// Finds the id of the highest-`stackEnd` point for each day/hour grouping key, independent of
/// how many providers contribute. Only that point should draw a rounded outer top.
func spendTopOfStackIDs<Point, Key: Hashable>(
    for points: [Point],
    key: (Point) -> Key,
    id: (Point) -> String,
    stackEnd: (Point) -> Double) -> Set<String>
{
    var bestByKey: [Key: (id: String, stackEnd: Double)] = [:]
    for point in points {
        let pointKey = key(point)
        let pointStackEnd = stackEnd(point)
        if let existing = bestByKey[pointKey], existing.stackEnd >= pointStackEnd {
            continue
        }
        bestByKey[pointKey] = (id(point), pointStackEnd)
    }
    return Set(bestByKey.values.map(\.id))
}

/// Only the outer top of a stacked bar should round; provider seams and the baseline stay flush.
private func spendStackedBarSegmentShape(isTopOfStack: Bool) -> UnevenRoundedRectangle {
    let topRadius: CGFloat = isTopOfStack ? 4 : 0
    return UnevenRoundedRectangle(
        topLeadingRadius: topRadius,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: topRadius,
        style: .continuous)
}

private struct SpendDailyChart: View {
    let group: SpendDashboardModel.CurrencyGroup

    var body: some View {
        let presentation = SpendDailyChartPresentation(
            dailyPoints: self.group.dailyPoints,
            aggregateTotal: self.group.totalCost)
        SpendDashboardPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Daily estimated spend")).font(.headline)
                if presentation.content == .unavailable {
                    ContentUnavailableView(L("Spend unavailable"), systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity, minHeight: 170)
                } else {
                    let topStackIDs = spendTopOfStackIDs(
                        for: self.group.dailyPoints,
                        key: \.day,
                        id: \.id,
                        stackEnd: \.stackEnd)
                    Chart(self.group.dailyPoints) { point in
                        BarMark(
                            x: .value(L("Day"), point.day, unit: .day, calendar: self.group.calendar),
                            yStart: .value(L("Estimated spend"), point.stackStart),
                            yEnd: .value(L("Estimated spend"), point.stackEnd),
                            width: .ratio(0.72))
                            .foregroundStyle(by: .value(L("Provider"), point.providerName))
                            // A clip cannot restore corners already removed by native mark rounding.
                            .cornerRadius(0)
                            .clipShape(spendStackedBarSegmentShape(isTopOfStack: topStackIDs.contains(point.id)))
                            .accessibilityLabel(Text(self.pointAccessibilityLabel(point)))
                            .accessibilityValue(Text(UsageFormatter.currencyString(
                                point.cost,
                                currencyCode: self.group.currencyCode)))
                    }
                    .chartXScale(domain: self.group.chartDomain)
                    .chartXAxis { AxisMarks(format: self.dayFormat) }
                    .chartForegroundStyleScale(
                        domain: presentation.series.map(\.name),
                        range: presentation.series.map { self.providerColor($0.provider) })
                    .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(UsageFormatter.compactCurrencyString(
                                        amount,
                                        currencyCode: self.group.currencyCode))
                                }
                            }
                        }
                    }
                    .frame(height: 170)
                    .accessibilityLabel(L("Daily estimated spend"))
                    .accessibilityValue(presentation.accessibilityValue)
                }
            }
        }
    }

    private func pointAccessibilityLabel(_ point: SpendDashboardModel.DailyPoint) -> String {
        let day = point.day.formatted(self.dayFormat)
        return "\(point.providerName), \(day)"
    }

    private var dayFormat: Date.FormatStyle {
        Date.FormatStyle(
            locale: codexBarLocalizedLocale(),
            calendar: self.group.calendar,
            timeZone: self.group.timeZone)
            .month(.abbreviated).day()
    }

    private func providerColor(_ provider: UsageProvider) -> Color {
        let color = ProviderAccentPalette.color(for: provider)
        return Color(red: color.red, green: color.green, blue: color.blue)
    }
}

struct SpendHourlyChartPresentation: Equatable {
    enum Content: Equatable {
        case chart
        case unavailable
    }

    struct Series: Equatable {
        let name: String
        let provider: UsageProvider
    }

    let content: Content
    let series: [Series]
    let hourCount: Int
    let includeDateInPointLabels: Bool

    init(hourlyPoints: [SpendDashboardModel.HourlyPoint], calendar: Calendar) {
        self.content = hourlyPoints.isEmpty ? .unavailable : .chart
        self.hourCount = Set(hourlyPoints.map(\.hour)).count
        self.includeDateInPointLabels = Set(hourlyPoints.map { calendar.startOfDay(for: $0.hour) }).count > 1
        var seenNames: Set<String> = []
        self.series = hourlyPoints.compactMap { point in
            guard seenNames.insert(point.providerName).inserted else { return nil }
            return Series(name: point.providerName, provider: point.provider)
        }
    }

    var accessibilityValue: String {
        spendDashboardHourlyChartAccessibilityValue(
            hourCount: self.hourCount,
            serviceCount: self.series.count)
    }
}

private struct SpendHourlyChart: View {
    let group: SpendDashboardModel.CurrencyGroup

    var body: some View {
        let calendar = self.group.calendar
        let presentation = SpendHourlyChartPresentation(
            hourlyPoints: self.group.hourlyPoints,
            calendar: calendar)
        SpendDashboardPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Hourly estimated spend")).font(.headline)
                if presentation.content == .unavailable {
                    ContentUnavailableView(L("Spend unavailable"), systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity, minHeight: 170)
                } else {
                    let topStackIDs = spendTopOfStackIDs(
                        for: self.group.hourlyPoints,
                        key: \.hour,
                        id: \.id,
                        stackEnd: \.stackEnd)
                    Chart(self.group.hourlyPoints) { point in
                        BarMark(
                            x: .value(L("Hour"), point.hour, unit: .hour, calendar: calendar),
                            yStart: .value(L("Estimated spend"), point.stackStart),
                            yEnd: .value(L("Estimated spend"), point.stackEnd),
                            width: .ratio(0.72))
                            .foregroundStyle(by: .value(L("Provider"), point.providerName))
                            .cornerRadius(0)
                            .clipShape(spendStackedBarSegmentShape(isTopOfStack: topStackIDs.contains(point.id)))
                            .accessibilityLabel(Text(self.pointAccessibilityLabel(
                                point,
                                includeDate: presentation.includeDateInPointLabels)))
                            .accessibilityValue(Text(UsageFormatter.currencyString(
                                point.cost,
                                currencyCode: self.group.currencyCode)))
                    }
                    .environment(\.timeZone, self.group.timeZone)
                    .environment(\.calendar, calendar)
                    .chartXScale(domain: self.group.hourlyChartDomain ?? self.group.chartDomain)
                    .chartForegroundStyleScale(
                        domain: presentation.series.map(\.name),
                        range: presentation.series.map { self.providerColor($0.provider) })
                    .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(UsageFormatter.compactCurrencyString(
                                        amount,
                                        currencyCode: self.group.currencyCode))
                                }
                            }
                        }
                    }
                    .frame(height: 170)
                    .accessibilityLabel(L("Hourly estimated spend"))
                    .accessibilityValue(presentation.accessibilityValue)
                }
            }
        }
    }

    private func pointAccessibilityLabel(
        _ point: SpendDashboardModel.HourlyPoint,
        includeDate: Bool) -> String
    {
        spendDashboardHourlyPointAccessibilityLabel(
            providerName: point.providerName,
            hour: point.hour,
            timeZone: self.group.timeZone,
            includeDate: includeDate)
    }

    private func providerColor(_ provider: UsageProvider) -> Color {
        let color = ProviderAccentPalette.color(for: provider)
        return Color(red: color.red, green: color.green, blue: color.blue)
    }
}

struct SpendProviderIcon: View {
    let provider: UsageProvider
    var sourceKind: SpendDashboardModel.SourceKind = .native
    var size: CGFloat = 20

    var body: some View {
        Group {
            if self.sourceKind == .openCodex {
                Image(systemName: "arrow.triangle.branch")
                    .font(.body.weight(.semibold))
            } else if let icon = ProviderBrandIcon.image(for: self.provider) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "circle.dotted")
            }
        }
        .frame(width: self.size, height: self.size)
        .accessibilityHidden(true)
    }
}

private struct SpendSessionPanel: View {
    let group: SpendDashboardModel.CurrencyGroup
    let hidePersonalInfo: Bool
    @State private var showsAllRows = false

    private static let collapsedRowCount = 8

    var body: some View {
        if !self.group.sessions.isEmpty {
            SpendDashboardPanel {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("Sessions")).font(.headline).padding(.bottom, 8)
                    ForEach(self.visibleRows) { row in
                        let identity = row.displayIdentity(hidePersonalInfo: self.hidePersonalInfo)
                        let subtitle = row.displaySubtitle(
                            hidePersonalInfo: self.hidePersonalInfo,
                            calendar: self.group.calendar)
                        if row.rank > 1 {
                            Divider()
                        }
                        HStack(spacing: 10) {
                            Text(spendDashboardRankText(row.rank))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 26, alignment: .leading)
                            SpendProviderIcon(provider: row.provider, sourceKind: .native)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(identity.name).lineLimit(1).help(identity.name)
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(spendDashboardMetricText(
                                cost: row.totalCost,
                                tokens: row.totalTokens,
                                currencyCode: self.group.currencyCode))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 9)
                    }
                    SpendPanelExpandButton(
                        rowCount: self.group.sessions.count,
                        collapsedRowCount: Self.collapsedRowCount,
                        showsAllRows: self.$showsAllRows)
                }
            }
        }
    }

    private var visibleRows: ArraySlice<SpendDashboardModel.SessionRow> {
        self.group.sessions.prefix(
            self.showsAllRows ? self.group.sessions.count : Self.collapsedRowCount)
    }
}

private struct SpendDashboardSourceFilter: View {
    @Bindable var settings: SettingsStore
    let model: SpendDashboardModel

    var body: some View {
        let ids = self.sourceIDs
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Sources")).font(.caption).foregroundStyle(.secondary)
                ForEach(ids, id: \.self) { sourceID in
                    Toggle(isOn: self.visibilityBinding(sourceID)) {
                        Text(self.label(for: sourceID)).lineLimit(1)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                }
            }
        }
    }

    private var sourceIDs: [String] {
        self.model.availableSources.map(\.id)
    }

    private func label(for sourceID: String) -> String {
        self.model.availableSources.first { $0.id == sourceID }?.displayName ?? sourceID
    }

    private func visibilityBinding(_ sourceID: String) -> Binding<Bool> {
        Binding(
            get: { !self.settings.spendDashboardHiddenSourceIDs.contains(sourceID) },
            set: { isVisible in
                var hidden = Set(self.settings.spendDashboardHiddenSourceIDs)
                if isVisible {
                    hidden.remove(sourceID)
                } else {
                    hidden.insert(sourceID)
                }
                self.settings.spendDashboardHiddenSourceIDs = Array(hidden)
            })
    }
}

struct SpendDashboardExportPayload: Encodable, Sendable {
    let requestedDays: Int
    let selectedDay: Date?
    let groups: [Group]
    let hiddenSourceIDs: [String]

    struct Group: Encodable, Sendable {
        let currencyCode: String
        let totalTokens: Int?
        let totalCost: Double?
        let meteredCost: Double?
        let provenance: String
        let coverage: CostUsageCoverageCounts
        let tokenMix: CostUsageTokenMix
        /// True when this group's totals are floors rather than exact values, so a consumer never
        /// mistakes a truncated or partly unpriced scan for complete history.
        let costIsLowerBound: Bool
        let tokensAreLowerBound: Bool
        let providers: [Provider]
        let models: [Model]
    }

    struct Provider: Encodable, Sendable {
        let id: String
        let displayName: String
        let sourceKind: String
        let totalTokens: Int?
        let totalCost: Double?
        let incompleteRequestCount: Int?
        let costIsLowerBound: Bool
        let tokensAreLowerBound: Bool
    }

    struct Model: Encodable, Sendable {
        let provider: String
        let modelName: String
        let totalTokens: Int?
        let totalCost: Double?
    }

    static func make(model: SpendDashboardModel, hiddenSourceIDs: [String]) -> Self {
        Self(
            requestedDays: model.requestedDays,
            selectedDay: model.selectedDay,
            groups: model.groups.map { group in
                Group(
                    currencyCode: group.currencyCode,
                    totalTokens: group.totalTokens,
                    totalCost: group.totalCost,
                    meteredCost: group.meteredCost,
                    provenance: group.provenance.rawValue,
                    coverage: group.coverage,
                    tokenMix: group.tokenMix,
                    costIsLowerBound: group.hasPartialCost,
                    tokensAreLowerBound: group.hasPartialTokens,
                    providers: group.providers.map {
                        Provider(
                            id: $0.id,
                            displayName: $0.displayName,
                            sourceKind: $0.sourceKind.rawValue,
                            totalTokens: $0.totalTokens,
                            totalCost: $0.totalCost,
                            incompleteRequestCount: $0.incompleteRequestCount > 0 ? $0.incompleteRequestCount : nil,
                            costIsLowerBound: $0.costIsLowerBound,
                            tokensAreLowerBound: $0.tokensAreLowerBound)
                    },
                    models: group.models.map {
                        Model(
                            provider: $0.provider.rawValue,
                            modelName: $0.modelName,
                            totalTokens: $0.totalTokens,
                            totalCost: $0.totalCost)
                    })
            },
            hiddenSourceIDs: hiddenSourceIDs)
    }
}

enum SpendDashboardJSONExporter {
    static func encodedData(model: SpendDashboardModel, hiddenSourceIDs: [String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(
            SpendDashboardExportPayload.make(model: model, hiddenSourceIDs: hiddenSourceIDs))
    }

    static func defaultFilename(days: Int) -> String {
        if days >= SpendDashboardSource.scanDays {
            return "quotakit-spend-all-time.json"
        }
        return "quotakit-spend-last-\(days)-days.json"
    }

    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    static func copyToPasteboard(
        model: SpendDashboardModel,
        hiddenSourceIDs: [String],
        pasteboard: NSPasteboard = .general) -> Bool
    {
        guard let data = try? self.encodedData(model: model, hiddenSourceIDs: hiddenSourceIDs),
              let json = String(bytes: data, encoding: .utf8)
        else {
            NSSound.beep()
            return false
        }
        pasteboard.clearContents()
        return pasteboard.setString(json, forType: .string)
    }

    @MainActor
    static func save(
        model: SpendDashboardModel,
        hiddenSourceIDs: [String],
        chooseDestination: ((String) -> URL?)? = nil) -> Bool
    {
        guard let data = try? self.encodedData(model: model, hiddenSourceIDs: hiddenSourceIDs) else {
            NSSound.beep()
            return false
        }
        let filename = self.defaultFilename(days: model.requestedDays)
        let url: URL?
        if let chooseDestination {
            url = chooseDestination(filename)
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = filename
            guard panel.runModal() == .OK else { return false }
            url = panel.url
        }
        guard let url else { return false }
        do {
            try self.write(data, to: url)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }
}

private struct SpendDashboardPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        self.content
            .padding(16)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35))
            }
    }
}

func spendDashboardGroupCostText(_ group: SpendDashboardModel.CurrencyGroup) -> String {
    guard let cost = group.totalCost else { return L("Spend unavailable") }
    let formatted = UsageFormatter.currencyString(cost, currencyCode: group.currencyCode)
    return group.hasPartialCost ? "~\(formatted)" : formatted
}

func spendDashboardGroupTokenText(_ group: SpendDashboardModel.CurrencyGroup) -> String {
    guard let tokens = group.totalTokens else { return "—" }
    let formatted = UsageFormatter.tokenCountString(tokens)
    return group.hasPartialTokens ? "~\(formatted)" : formatted
}

private func spendDashboardIncludesLocalHistory(_ group: SpendDashboardModel.CurrencyGroup) -> Bool {
    group.providers.contains { $0.sourceKind == .localHistory }
}

func spendDashboardProviderCountTitle(_ group: SpendDashboardModel.CurrencyGroup) -> String {
    spendDashboardIncludesLocalHistory(group) ? L("Sources") : L("Subscriptions")
}

func spendDashboardProviderPanelTitle(_ group: SpendDashboardModel.CurrencyGroup) -> String {
    spendDashboardIncludesLocalHistory(group) ? L("By source") : L("By subscription")
}

func spendDashboardPartialSourceCoverageText(_ group: SpendDashboardModel.CurrencyGroup) -> String {
    let template = spendDashboardIncludesLocalHistory(group)
        ? "%d of %d sources have spend" : "%d of %d subscriptions have spend"
    return L(template, group.pricedProviderCount, group.providers.count)
}

func spendDashboardHistoryCaption(
    _ group: SpendDashboardModel.CurrencyGroup,
    requestedDays: Int) -> String
{
    var parts: [String] = []
    if group.hasPartialCost || group.hasPartialTokens {
        parts.append(L("Partial estimate"))
        if group.hasUnpricedProviders {
            parts.append(spendDashboardPartialSourceCoverageText(group))
        }
    } else {
        parts.append(L("Local estimated history"))
    }
    parts.append(spendDashboardCoverageText(covered: group.coveredDayCount, requested: requestedDays))
    return parts.joined(separator: " · ")
}
