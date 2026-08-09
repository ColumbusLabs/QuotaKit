import CodexBarCore
import CodexBarSync
import Foundation

extension SyncCoordinator {
    static func mapGrokBilling(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncGrokBilling?
    {
        guard provider == .grok, let grok = snapshot?.grokUsage else { return nil }

        let percent = grok.billing?.monthlyUsedPercent ?? grok.webBilling?.usedPercent
        let spend = grok.billing?.usage?.totalUsed?.val.map { Double($0) / 100.0 }
        let limit = grok.billing?.monthlyLimit?.val.map { Double($0) / 100.0 }
        let resetAt = grok.billing?.billingPeriodEndDate ?? grok.webBilling?.resetsAt
        guard percent != nil || spend != nil else { return nil }

        return SyncGrokBilling(
            monthlyUsedPercent: percent,
            monthlySpendUSD: spend,
            monthlyLimitUSD: limit,
            billingPeriodEndDate: resetAt,
            planTier: nil,
            updatedAt: grok.updatedAt)
    }

    static func mapClaudeAdminUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncClaudeAdminUsage?
    {
        guard provider == .claude, let admin = snapshot?.claudeAdminAPIUsage else { return nil }

        func mapWindow(_ summary: ClaudeAdminAPIUsageSnapshot.Summary) -> SyncClaudeAdminWindowSummary {
            SyncClaudeAdminWindowSummary(
                costUSD: summary.costUSD,
                totalTokens: summary.totalTokens,
                inputTokens: summary.inputTokens,
                outputTokens: summary.outputTokens,
                cacheCreationInputTokens: summary.cacheCreationInputTokens,
                cacheReadInputTokens: summary.cacheReadInputTokens)
        }

        let last30Days = mapWindow(admin.last30Days)
        guard last30Days.totalTokens != 0 || last30Days.costUSD != 0 else { return nil }

        return SyncClaudeAdminUsage(
            last30Days: last30Days,
            last7Days: mapWindow(admin.last7Days),
            latestDay: admin.daily.isEmpty ? nil : mapWindow(admin.latestDay),
            topModels: Array(admin.topModels.prefix(8)).map {
                SyncClaudeAdminModelBreakdown(name: $0.name, totalTokens: $0.totalTokens)
            },
            topCostItems: Array(admin.topCostItems.prefix(8)).map {
                SyncClaudeAdminCostItem(name: $0.name, costUSD: $0.costUSD)
            },
            updatedAt: admin.updatedAt)
    }

    static func mapClaudeExtraUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        providerCost: ProviderCostSnapshot?) -> SyncClaudeExtraUsage?
    {
        guard provider == .claude,
              let cost = providerCost,
              cost.currencyCode.caseInsensitiveCompare("USD") == .orderedSame,
              cost.limit > 0 || cost.balance != nil
        else { return nil }

        let hasSpendLimit = cost.limit > 0
        let utilization = hasSpendLimit
            ? min(max((cost.used / cost.limit) * 100, 0), 100)
            : nil
        let planTier: String? = {
            let loginMethod = snapshot?.identity?.loginMethod ?? ""
            if loginMethod.localizedCaseInsensitiveContains("enterprise") {
                return "Enterprise"
            }
            if loginMethod.localizedCaseInsensitiveContains("team") {
                return "Team"
            }
            if loginMethod.localizedCaseInsensitiveContains("max") {
                return "Max"
            }
            if loginMethod.localizedCaseInsensitiveContains("pro") {
                return "Pro"
            }
            return nil
        }()

        return SyncClaudeExtraUsage(
            utilization: utilization,
            monthlySpendUSD: hasSpendLimit ? cost.used : nil,
            monthlyLimitUSD: hasSpendLimit ? cost.limit : nil,
            balanceUSD: cost.balance,
            isEnabled: true,
            planTier: planTier,
            updatedAt: snapshot?.updatedAt ?? cost.updatedAt)
    }

    static func buildCodexWorkspaceContext(
        activeAccount: ManagedCodexAccount?,
        snapshot: UsageSnapshot?) -> SyncCodexWorkspaceContext?
    {
        let workspaceLabel = activeAccount?.workspaceLabel
        let workspaceID = activeAccount?.workspaceAccountID
        let paceWindow = Self.codexWeeklyWindow(snapshot: snapshot)
        let pace = paceWindow.flatMap { UsagePace.weekly(window: $0) }
        let paceDelta = pace.map { $0.deltaPercent / 100.0 }
        let paceLabel = pace.map { UsagePaceText.weeklySummary(provider: .codex, pace: $0) }

        guard workspaceLabel != nil || workspaceID != nil || paceDelta != nil else { return nil }

        return SyncCodexWorkspaceContext(
            workspaceID: workspaceID,
            workspaceName: workspaceLabel,
            weeklyPaceDelta: paceDelta,
            weeklyPaceLabel: paceLabel,
            updatedAt: snapshot?.updatedAt ?? Date())
    }

    private static func codexWeeklyWindow(snapshot: UsageSnapshot?) -> RateWindow? {
        let candidates = [snapshot?.secondary, snapshot?.tertiary, snapshot?.primary]
        return candidates.lazy.compactMap(\.self).first { window in
            guard let minutes = window.windowMinutes else { return false }
            return minutes >= 24 * 60
        }
    }
}
