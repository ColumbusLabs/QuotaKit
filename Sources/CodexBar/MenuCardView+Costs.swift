import CodexBarCore
import Foundation
import SwiftUI

struct ProviderCostContent: View {
    let section: UsageMenuCardView.Model.ProviderCostSection
    let progressColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        if self.section.presentation == .inlineValue {
            HStack(alignment: .firstTextBaseline) {
                Text(self.section.title)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Text(self.section.spendLine)
                    .font(.footnote)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(self.section.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let balanceLine = self.section.balanceLine {
                        Spacer(minLength: 8)
                        Text(balanceLine)
                            .font(.footnote)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                if let percentUsed = self.section.percentUsed {
                    UsageProgressBar(
                        percent: percentUsed,
                        tint: self.progressColor,
                        accessibilityLabel: L("Extra usage spent"))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(self.section.spendLine).font(.footnote).lineLimit(1)
                    Spacer()
                    if let percentLine = self.section.percentLine {
                        Text(percentLine)
                            .font(.footnote)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                    }
                }
                if let personalSpendLine = self.section.personalSpendLine {
                    Text(personalSpendLine)
                        .font(.footnote).foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted)).lineLimit(1)
                }
            }
        }
    }
}

extension UsageMenuCardView.Model.ProviderCostSection {
    enum Presentation: Equatable {
        case detail
        case inlineValue
    }

    init(
        title: String,
        percentUsed: Double?,
        spendLine: String,
        percentLine: String?,
        balanceLine: String? = nil,
        presentation: Presentation = .detail,
        showsInProviderDetails: Bool = true)
    {
        self.init(
            title: title,
            percentUsed: percentUsed,
            spendLine: spendLine,
            percentLine: percentLine,
            balanceLine: balanceLine,
            personalSpendLine: nil,
            presentation: presentation,
            showsInProviderDetails: showsInProviderDetails)
    }
}

extension UsageMenuCardView.Model {
    static func tokenUsageSnapshot(input: Input) -> CostUsageTokenSnapshot? {
        if usesProviderCostHistoryAsPrimaryDashboard(input.provider), input.snapshot != nil {
            return primaryCostHistorySnapshot(input: input)
        }
        return input.tokenSnapshot
    }

    static func creditsLine(
        metadata: ProviderMetadata,
        snapshot: UsageSnapshot?,
        credits: CreditsSnapshot?,
        error: String?,
        preferredCurrencyCode: String = "auto") -> String?
    {
        guard metadata.supportsCredits else { return nil }
        let visibility = ProviderDescriptorRegistry.descriptor(for: metadata.id).presentation.menuCard.creditsVisibility
        if visibility == .hidden ||
            (visibility == .requiresValueOrError && credits == nil && error == nil) ||
            (visibility == .hiddenWhenUsageSnapshotPresent && snapshot != nil)
        {
            return nil
        }
        if let credits {
            if let creditLimit = credits.codexCreditLimit {
                return UsageFormatter.creditsString(from: creditLimit.remaining)
            }
            return UsageFormatter.creditsString(from: credits.remaining)
        }
        if let error, !error.isEmpty {
            return error.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return L(metadata.creditsHint)
    }

    static func creditsProgressPercent(credits: CreditsSnapshot?) -> Double? {
        credits?.codexCreditLimit?.remainingPercent
    }

    static func creditsScaleText(credits: CreditsSnapshot?) -> String? {
        guard let limit = credits?.codexCreditLimit else { return nil }
        return L("of %@", UsageFormatter.creditsNumberString(from: limit.limit))
    }

    static func codexCreditLimitDetail(credits: CreditsSnapshot?, now: Date) -> String? {
        guard let limit = credits?.codexCreditLimit else { return nil }
        var parts = [
            L("%@ used", UsageFormatter.creditsNumberString(from: limit.used)),
        ]
        if let resetsAt = limit.resetsAt {
            parts.append(L("resets %@", UsageFormatter.resetDescription(from: resetsAt, now: now)))
        }
        return parts.joined(separator: " · ")
    }

    static func tokenUsageSection(
        provider: UsageProvider,
        enabled: Bool,
        isRefreshing: Bool = false,
        comparisonPeriodsEnabled: Bool,
        snapshot: CostUsageTokenSnapshot?,
        error: String?,
        preferredCurrencyCode: String = "auto") -> TokenUsageSection?
    {
        guard ProviderDescriptorRegistry.descriptor(for: provider).tokenCost.supportsTokenCost else {
            return nil
        }
        guard enabled else { return nil }
        guard let snapshot else { return nil }

        let sessionCost = snapshot.sessionCostUSD.map {
            UsageFormatter.convertedCostString(
                $0,
                preferredCurrency: preferredCurrencyCode,
                providerCurrency: snapshot.currencyCode)
        } ?? "—"
        let sessionTokens = snapshot.sessionTokens.map { UsageFormatter.tokenCountString($0) }
        let sessionLabel = L("Today")
        let sessionLine: String = {
            if let sessionTokens {
                return String(format: L("%@: %@ · %@ tokens"), sessionLabel, sessionCost, sessionTokens)
            }
            return "\(sessionLabel): \(sessionCost)"
        }()

        let monthCost = snapshot.last30DaysCostUSD.map {
            UsageFormatter.convertedCostString(
                $0,
                preferredCurrency: preferredCurrencyCode,
                providerCurrency: snapshot.currencyCode)
        } ?? "—"
        let fallbackTokens = snapshot.daily.compactMap(\.totalTokens).reduce(0, +)
        let monthTokensValue = snapshot.last30DaysTokens ?? (fallbackTokens > 0 ? fallbackTokens : nil)
        let monthTokens = monthTokensValue.map { UsageFormatter.tokenCountString($0) }
        let windowLabel = if let historyLabel = snapshot.historyLabel {
            historyLabel
        } else {
            Self.costHistoryWindowLabel(days: snapshot.historyDays)
        }
        let monthLine: String = {
            if let monthTokens {
                return String(format: L("%@: %@ · %@ tokens"), windowLabel, monthCost, monthTokens)
            }
            return "\(windowLabel): \(monthCost)"
        }()
        // Plan-metered spend over the same window (what the provider actually deducts);
        // only providers that report it (currently Cursor) populate `meteredCostUSD`.
        let meteredLine: String? = snapshot.meteredCostUSD.map {
            let amount = UsageFormatter.convertedCostString(
                $0,
                preferredCurrency: preferredCurrencyCode,
                providerCurrency: snapshot.currencyCode)
            return String(format: L("Cursor-metered: %@ (%@)"), amount, windowLabel.lowercased())
        }
        let err = (error?.isEmpty ?? true) ? nil : error
        return TokenUsageSection(
            isRefreshing: isRefreshing,
            sessionLine: sessionLine,
            monthLine: monthLine,
            meteredLine: meteredLine,
            comparisonLines: comparisonPeriodsEnabled
                ? snapshot.comparisonSummaries().map {
                    Self.costWindowLine(
                        summary: $0,
                        currencyCode: UsageFormatter.effectiveCurrencyCode(
                            preferred: preferredCurrencyCode,
                            providerCurrency: snapshot.currencyCode),
                        sourceCurrencyCode: snapshot.currencyCode)
                }
                : [],
            hintLine: Self.tokenUsageHint(provider: provider),
            errorLine: err,
            errorCopyText: (error?.isEmpty ?? true) ? nil : error)
    }

    static func costWindowLine(
        summary: CostUsageWindowSummary,
        currencyCode: String,
        sourceCurrencyCode: String? = nil) -> String
    {
        let label = Self.costHistoryWindowLabel(days: summary.days)
        let cost = summary.totalCostUSD.map {
            UsageFormatter.convertedCostString(
                $0,
                preferredCurrency: currencyCode,
                providerCurrency: sourceCurrencyCode ?? currencyCode)
        } ?? "—"
        guard let totalTokens = summary.totalTokens else { return "\(label): \(cost)" }
        return String(
            format: L("%@: %@ · %@ tokens"),
            label,
            cost,
            UsageFormatter.tokenCountString(totalTokens))
    }

    static func tokenUsageHint(provider: UsageProvider) -> String? {
        let lines = Self.tokenUsageHintLines(provider: provider)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func tokenUsageHeader(provider _: UsageProvider) -> String {
        L("Cost")
    }

    static func tokenUsageHintLines(provider: UsageProvider) -> [String] {
        ProviderDescriptorRegistry.descriptor(for: provider).tokenCost.menuHintLines.map { hint in
            switch hint {
            case let .localized(key): L(key)
            case .estimate: UsageFormatter.costEstimateHint(provider: provider)
            case let .literal(text): L(text)
            }
        }
    }

    static func costHistoryWindowLabel(days: Int) -> String {
        days == 1 ? L("Today") : String(format: L("Last %d days"), days)
    }

    static func providerCostSection(
        cost: ProviderCostSnapshot?,
        style: ProviderCostMenuCardStyle,
        isClaudeAdminAPI: Bool = false,
        preferredCurrencyCode: String = "auto") -> ProviderCostSection?
    {
        guard style != .hidden else { return nil }
        guard let cost else { return nil }

        /// Formats a cost value using the user's currency preference.
        func formatCost(_ value: Double, providerCurrency: String? = nil) -> String {
            UsageFormatter.convertedCostString(
                value,
                preferredCurrency: preferredCurrencyCode,
                providerCurrency: providerCurrency ?? cost.currencyCode)
        }

        if style == .extraUsageBalance {
            let balance = formatCost(cost.used)
            return ProviderCostSection(
                title: L("Extra usage"),
                percentUsed: nil,
                spendLine: "\(L("Balance")): \(balance)",
                percentLine: nil)
        }

        if style == .claude {
            if isClaudeAdminAPI {
                let spend = formatCost(cost.used)
                let periodLabel = Self.localizedPeriodLabel(cost.period ?? "Last 30 days")
                return ProviderCostSection(
                    title: L("API spend"),
                    percentUsed: nil,
                    spendLine: "\(periodLabel): \(spend)",
                    percentLine: nil)
            }

            if cost.limit <= 0 {
                guard let balance = cost.balance else { return nil }
                let value = formatCost(balance)
                return ProviderCostSection(
                    title: L("Credits"),
                    percentUsed: nil,
                    spendLine: value,
                    percentLine: nil,
                    presentation: .inlineValue,
                    showsInProviderDetails: false)
            }

            let used = formatCost(cost.used)
            let limit = formatCost(cost.limit)
            let percentUsed = Self.clamped((cost.used / cost.limit) * 100)
            let periodLabel = Self.localizedPeriodLabel(cost.period ?? "This month")
            let balanceLine = cost.balance.map {
                "\(L("Balance")): \(formatCost($0))"
            }
            return ProviderCostSection(
                title: L("Extra usage"),
                percentUsed: percentUsed,
                spendLine: "\(periodLabel): \(used) / \(limit)",
                percentLine: String(format: L("%.0f%% used"), min(100, max(0, percentUsed))),
                balanceLine: balanceLine,
                showsInProviderDetails: false)
        }

        guard cost.limit > 0 else { return nil }

        let used: String
        let limit: String
        let title: String

        if cost.currencyCode == "Quota" {
            title = L("Quota usage")
            used = String(format: "%.0f", cost.used)
            limit = String(format: "%.0f", cost.limit)
        } else {
            title = L("Extra usage")
            used = formatCost(cost.used)
            limit = formatCost(cost.limit)
        }

        let percentUsed = Self.clamped((cost.used / cost.limit) * 100)
        let periodLabel = Self.localizedPeriodLabel(cost.period ?? "This month")

        // When the headline budget is a shared pool (e.g. Cursor team on-demand), show the
        // account's own contribution underneath it.
        let personalSpendLine: String? = cost.personalUsed.flatMap { personal in
            personal > 0
                ? "\(L("Your spend")): \(formatCost(personal))"
                : nil
        }

        return ProviderCostSection(
            title: title,
            percentUsed: percentUsed,
            spendLine: "\(periodLabel): \(used) / \(limit)",
            percentLine: String(format: L("%.0f%% used"), min(100, max(0, percentUsed))),
            balanceLine: nil,
            personalSpendLine: personalSpendLine)
    }

    private static func localizedPeriodLabel(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "last 30 days":
            return L("Last 30 days")
        case "this month":
            return L("This month")
        case "today":
            return L("Today")
        default:
            return L(trimmed)
        }
    }

    static func clamped(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
