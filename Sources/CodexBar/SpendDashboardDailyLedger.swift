import CodexBarCore
import Foundation
import SwiftUI

func spendDashboardLedgerDateText(_ day: Date, timeZone: TimeZone, accessibility: Bool = false) -> String {
    var format = accessibility
        ? Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).year()
        : Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
    format.locale = codexBarLocalizedLocale()
    format.timeZone = timeZone
    return day.formatted(format)
}

func spendDashboardLedgerCostText(_ summary: SpendDashboardModel.DailySummary, currencyCode: String) -> String {
    guard let cost = summary.totalCost else { return "—" }
    let formatted = UsageFormatter.currencyString(cost, currencyCode: currencyCode)
    return summary.hasPartialCost ? "~\(formatted)" : formatted
}

func spendDashboardLedgerTokenText(_ summary: SpendDashboardModel.DailySummary) -> String {
    spendDashboardLedgerCountText(
        summary.totalTokens,
        isLowerBound: summary.hasPartialCounts,
        format: UsageFormatter.tokenCountString)
}

func spendDashboardLedgerRequestText(_ summary: SpendDashboardModel.DailySummary) -> String {
    // A missing source count makes only the request total a floor. Token totals keep their own flag.
    spendDashboardLedgerCountText(
        summary.requestCount,
        isLowerBound: summary.hasPartialCounts || summary.requestsAreLowerBound,
        format: codexBarLocalizedInteger)
}

func spendDashboardLedgerCountText(
    _ count: Int?,
    isLowerBound: Bool,
    format: (Int) -> String) -> String
{
    guard let count else { return "—" }
    let text = format(count)
    return isLowerBound ? "≥\(text)" : text
}

private enum SpendDailyLedgerLayout {
    static let dayWidth: CGFloat = 112
    static let providerMinimumWidth: CGFloat = 96
    static let trackedTokensWidth: CGFloat = 90
    static let requestsWidth: CGFloat = 72
    static let estimatedSpendWidth: CGFloat = 116
    static let columnSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 8
    static let minimumTableWidth: CGFloat =
        dayWidth
            + providerMinimumWidth
            + trackedTokensWidth
            + requestsWidth
            + estimatedSpendWidth
            + (columnSpacing * 4)
            + (horizontalPadding * 2)
}

/// Bound initial layout while keeping the complete ledger available on demand.
func spendDailyLedgerVisibleSummaries(
    _ summaries: [SpendDashboardModel.DailySummary],
    showsAllRows: Bool,
    collapsedRowCount: Int) -> [SpendDashboardModel.DailySummary]
{
    Array(summaries.suffix(showsAllRows ? summaries.count : collapsedRowCount).reversed())
}

struct SpendDailyLedger: View {
    let group: SpendDashboardModel.CurrencyGroup
    let hidePersonalInfo: Bool
    @State private var showsAllRows = false

    static let collapsedRowCount = 30

    private var visibleSummaries: [SpendDashboardModel.DailySummary] {
        spendDailyLedgerVisibleSummaries(
            self.group.dailySummaries,
            showsAllRows: self.showsAllRows,
            collapsedRowCount: Self.collapsedRowCount)
    }

    var body: some View {
        SpendDashboardPanel {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Daily estimated spend"))
                    .font(.headline)
                    .padding(.bottom, 10)

                if self.group.dailySummaries.isEmpty {
                    ContentUnavailableView(
                        L("Spend unavailable"),
                        systemImage: "calendar.badge.exclamationmark")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            self.header
                            Divider()
                            VStack(spacing: 0) {
                                ForEach(Array(self.visibleSummaries.enumerated()), id: \.element.id) { index, summary in
                                    if index > 0 {
                                        Divider()
                                    }
                                    SpendDailyLedgerRow(
                                        summary: summary,
                                        currencyCode: self.group.currencyCode,
                                        timeZone: self.group.timeZone,
                                        hidePersonalInfo: self.hidePersonalInfo)
                                }
                            }
                        }
                        .frame(minWidth: SpendDailyLedgerLayout.minimumTableWidth, alignment: .leading)
                    }
                    SpendPanelExpandButton(
                        rowCount: self.group.dailySummaries.count,
                        collapsedRowCount: Self.collapsedRowCount,
                        showsAllRows: self.$showsAllRows)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: SpendDailyLedgerLayout.columnSpacing) {
            Text(L("Day")).frame(width: SpendDailyLedgerLayout.dayWidth, alignment: .leading)
            Text(L("Providers")).frame(
                minWidth: SpendDailyLedgerLayout.providerMinimumWidth,
                maxWidth: .infinity,
                alignment: .leading)
            Text(L("Tracked tokens")).frame(
                width: SpendDailyLedgerLayout.trackedTokensWidth,
                alignment: .trailing)
            Text(L("Requests")).frame(
                width: SpendDailyLedgerLayout.requestsWidth,
                alignment: .trailing)
            Text(L("Estimated spend")).frame(
                width: SpendDailyLedgerLayout.estimatedSpendWidth,
                alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, SpendDailyLedgerLayout.horizontalPadding)
        .padding(.vertical, 6)
    }
}

private struct SpendDailyLedgerRow: View {
    let summary: SpendDashboardModel.DailySummary
    let currencyCode: String
    let timeZone: TimeZone
    let hidePersonalInfo: Bool

    var body: some View {
        HStack(spacing: SpendDailyLedgerLayout.columnSpacing) {
            Text(spendDashboardLedgerDateText(self.summary.day, timeZone: self.timeZone))
                .frame(width: SpendDailyLedgerLayout.dayWidth, alignment: .leading)
            self.providerMix
                .frame(
                    minWidth: SpendDailyLedgerLayout.providerMinimumWidth,
                    maxWidth: .infinity,
                    alignment: .leading)
            Text(spendDashboardLedgerTokenText(self.summary))
                .frame(width: SpendDailyLedgerLayout.trackedTokensWidth, alignment: .trailing)
            Text(spendDashboardLedgerRequestText(self.summary))
                .frame(width: SpendDailyLedgerLayout.requestsWidth, alignment: .trailing)
            Text(spendDashboardLedgerCostText(self.summary, currencyCode: self.currencyCode))
                .fontWeight(.medium)
                .frame(width: SpendDailyLedgerLayout.estimatedSpendWidth, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.horizontal, SpendDailyLedgerLayout.horizontalPadding)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.accessibilityLabel)
    }

    @ViewBuilder
    private var providerMix: some View {
        if self.activeProviders.isEmpty {
            Text(L("No usage yet"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 5) {
                ForEach(self.activeProviders.prefix(4)) { row in
                    SpendProviderIcon(provider: row.provider)
                }
                if self.activeProviders.count > 4 {
                    Text("+\(codexBarLocalizedInteger(self.activeProviders.count - 4))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .help(self.activeProviders.map { self.sourceName($0.displayName) }.joined(separator: ", "))
        }
    }

    private var activeProviders: [SpendDashboardModel.DailyProviderRow] {
        self.summary.providers.filter { !$0.isKnownIdle }
    }

    private func sourceName(_ name: String) -> String {
        PersonalInfoRedactor.redactEmails(in: name, isEnabled: self.hidePersonalInfo) ?? name
    }

    private var accessibilityLabel: String {
        let day = spendDashboardLedgerDateText(self.summary.day, timeZone: self.timeZone, accessibility: true)
        let providers = self.activeProviders.isEmpty
            ? L("No usage yet")
            : self.activeProviders.map { self.sourceName($0.displayName) }.joined(separator: ", ")
        let tokens = spendDashboardLedgerTokenText(self.summary)
        let requests = spendDashboardLedgerRequestText(self.summary)
        let spend = spendDashboardLedgerCostText(self.summary, currencyCode: self.currencyCode)
        return "\(day), \(L("Providers")): \(providers), \(L("Tracked tokens")): \(tokens), "
            + "\(L("Requests")): \(requests), \(L("Estimated spend")): \(spend)"
    }
}
