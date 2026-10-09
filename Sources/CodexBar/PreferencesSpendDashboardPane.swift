import AppKit
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
    case chats
    case sessions

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .providers: L("Providers")
        case .projects: L("Projects")
        case .chats: L("Independent chats")
        case .sessions: L("Sessions")
        }
    }
}

func spendDashboardAvailableDetailSections(
    hasProjects: Bool,
    hasSessions: Bool,
    hasChats: Bool = false) -> [SpendDashboardDetailSection]
{
    var sections: [SpendDashboardDetailSection] = [.providers]
    if hasProjects { sections.append(.projects) }
    if hasChats { sections.append(.chats) }
    if hasSessions { sections.append(.sessions) }
    return sections
}

/// Filter for display without regrouping ledger paths or changing any amounts.
func spendDashboardProjectRows(
    _ rows: [SpendDashboardModel.ProjectRow],
    isProjectless: Bool) -> [SpendDashboardModel.ProjectRow]
{
    rows.filter { $0.isProjectless == isProjectless }.enumerated().map { index, row in
        var ranked = row
        ranked.rank = index + 1
        return ranked
    }
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
        case .daily: L("Overview")
        case .hourly: L("Hour")
        }
    }
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
                SpendTimeZoneControls(settings: self.settings)
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
            self.controller.refreshIfStale()
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
            self.controller.refreshIfStale()
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

    var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Usage & Spend"))
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Text(L("Local estimated cost history across supported providers."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
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
            .frame(maxWidth: 480, alignment: .leading)
            .accessibilityIdentifier("spend-dashboard-range-picker")
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
                    onSelectDay: { self.controller.selectDay($0) },
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
    let onSelectDay: ((Date) -> Void)?
    let onClearSelectedDay: (() -> Void)?
    @State private var selectedDetailSection: SpendDashboardDetailSection
    @State private var selectedTrendSection: SpendDashboardTrendSection

    init(
        group: SpendDashboardModel.CurrencyGroup,
        requestedDays: Int,
        hidePersonalInfo: Bool = false,
        onSelectDay: ((Date) -> Void)? = nil,
        onClearSelectedDay: (() -> Void)? = nil,
        detailSection: SpendDashboardDetailSection = .providers)
    {
        self.group = group
        self.requestedDays = requestedDays
        self.hidePersonalInfo = hidePersonalInfo
        self.onSelectDay = onSelectDay
        self.onClearSelectedDay = onClearSelectedDay
        self._selectedDetailSection = State(initialValue: detailSection)
        self._selectedTrendSection = State(
            initialValue: group.selectedDay != nil && !group.hourlyPoints.isEmpty ? .hourly : .daily)
    }

    private var availableDetailSections: [SpendDashboardDetailSection] {
        spendDashboardAvailableDetailSections(
            hasProjects: self.group.projects.contains { !$0.isProjectless },
            hasSessions: !self.group.sessions.isEmpty,
            hasChats: self.group.projects.contains(where: \.isProjectless))
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
                SpendProjectPanel(group: self.group, hidePersonalInfo: self.hidePersonalInfo, isProjectless: false)
            } else if self.activeDetailSection == .chats {
                SpendProjectPanel(group: self.group, hidePersonalInfo: self.hidePersonalInfo, isProjectless: true)
            } else {
                SpendSessionPanel(group: self.group, hidePersonalInfo: self.hidePersonalInfo)
            }
            SpendDashboardTrendPanel(
                group: self.group,
                selection: self.$selectedTrendSection,
                onSelectDay: self.onSelectDay.map { onSelectDay in
                    { day in
                        self.selectedDetailSection = .providers
                        onSelectDay(day)
                    }
                },
                onClearSelectedDay: self.onClearSelectedDay)
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
    let isProjectless: Bool
    @State private var showsAllRows = false

    private static let collapsedRowCount = 8

    var body: some View {
        SpendDashboardPanel {
            VStack(alignment: .leading, spacing: 0) {
                Text(self.isProjectless ? L("Independent chats") : L("Projects")).font(.headline).padding(.bottom, 8)
                ForEach(self.visibleRows) { row in
                    let identity = row.displayIdentity(hidePersonalInfo: self.hidePersonalInfo)
                    let hasDuplicateLabel = row.needsPathDisambiguation(in: self.rows)
                    if row.rank > 1 {
                        Divider()
                    }
                    HStack(spacing: 10) {
                        Text(spendDashboardRankText(row.rank))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 26, alignment: .leading)
                        Image(systemName: row.isProjectless ? "bubble.left.and.bubble.right" : "folder")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(identity.name)
                                .lineLimit(1)
                                .help(identity.path ?? identity.name)
                            Text(row.providerName).font(.caption).foregroundStyle(.secondary)
                            if let path = identity.path, hasDuplicateLabel {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(path)
                            }
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
                    rowCount: self.rows.count,
                    collapsedRowCount: Self.collapsedRowCount,
                    showsAllRows: self.$showsAllRows)
            }
        }
    }

    private var visibleRows: ArraySlice<SpendDashboardModel.ProjectRow> {
        self.rows.prefix(self.showsAllRows ? self.rows.count : Self.collapsedRowCount)
    }

    private var rows: [SpendDashboardModel.ProjectRow] {
        spendDashboardProjectRows(self.group.projects, isProjectless: self.isProjectless)
    }
}

struct SpendPanelExpandButton: View {
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

struct SpendProviderIcon: View {
    let provider: UsageProvider
    var sourceKind: SpendDashboardModel.SourceKind = .native
    var style: ProviderBrandIcon.Style = .brand
    var size: CGFloat = 20

    var body: some View {
        Group {
            if self.sourceKind == .openCodex {
                Image(systemName: "arrow.triangle.branch")
                    .resizable().scaledToFit()
            } else if let icon = ProviderBrandIcon.image(for: self.provider, style: self.style) {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(icon.isTemplate ? .template : .original)
                    .scaledToFit()
                    .frame(
                        width: self.size * self.artworkScale(for: icon),
                        height: self.size * self.artworkScale(for: icon))
            } else {
                Image(systemName: "circle.dotted")
                    .resizable().scaledToFit()
            }
        }
        .foregroundStyle(.primary)
        .frame(width: self.size, height: self.size)
        .accessibilityHidden(true)
    }

    private func artworkScale(for icon: NSImage) -> CGFloat {
        switch self.provider {
        case .cursor: 1.25
        case .codex: icon.isTemplate ? 1.24 : 1.17
        case .antigravity: icon.isTemplate ? 1.14 : 1.38
        case .bedrock: icon.isTemplate ? 1 : 0.84
        case .muse, .vertexai: icon.isTemplate ? 1 : 1.08
        default: 1
        }
    }
}

struct SpendSessionPanel: View {
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
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 10) {
                                Text(spendDashboardRankText(row.rank))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 26, alignment: .leading)
                                SpendProviderIcon(provider: row.provider, sourceKind: .native)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(identity.name).fontWeight(.medium).lineLimit(1).help(identity.name)
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1).help(subtitle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(spendDashboardMetricText(
                                    cost: row.totalCost,
                                    tokens: row.totalTokens,
                                    currencyCode: self.group.currencyCode))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let performance = row.turnPerformance {
                                SpendSessionPerformanceView(summary: performance)
                            }
                            if let source = row.toolActivitySource {
                                SpendSessionToolActivityView(
                                    source: source,
                                    lastActivity: row.lastActivity,
                                    range: spendToolActivityRange(group: self.group),
                                    timeZone: self.group.timeZone,
                                    hidePersonalInfo: self.hidePersonalInfo)
                            }
                        }
                        .padding(.vertical, 12)
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
        let incompleteRequestCount: Int?
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
        let incompleteRequestCount: Int?
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
                    incompleteRequestCount: group.incompleteRequestCount > 0 ? group.incompleteRequestCount : nil,
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
                            totalCost: $0.totalCost,
                            incompleteRequestCount: $0.incompleteRequestCount > 0 ? $0.incompleteRequestCount : nil)
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

struct SpendDashboardPanel<Content: View>: View {
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
