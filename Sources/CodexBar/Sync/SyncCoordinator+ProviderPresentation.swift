import CodexBarCore
import CodexBarSync
import Foundation

extension SyncCoordinator {
    static func syncedStatusMessage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        providerCost: ProviderCostSnapshot?,
        error: String?,
        rateWindows: [SyncRateWindow]) -> String?
    {
        if let error {
            return error
        }
        if provider == .aiand || provider == .fireworks, let providerCost {
            let amount = String(format: "%.2f", providerCost.used)
            let period = providerCost.period ?? "Last 30 days"
            return "\(period) spend: \(providerCost.currencyCode) \(amount)"
        }
        if provider == .opencode, let providerCost, providerCost.limit <= 0 {
            let spend = String(format: "%.2f", providerCost.used)
            let period = providerCost.period ?? "Monthly"
            if let balance = providerCost.balance {
                return "\(period) spend: \(providerCost.currencyCode) \(spend) · Balance: " +
                    "\(providerCost.currencyCode) \(String(format: "%.2f", balance))"
            }
            return "\(period) spend: \(providerCost.currencyCode) \(spend)"
        }
        if provider == .xai, let xaiUsage = snapshot?.xaiUsage {
            let amount = String(format: "%.2f", xaiUsage.balanceUSD)
            return "Prepaid credits: USD \(amount)"
        }
        if provider == .lithosai, let providerCost {
            let amount = String(format: "%.2f", providerCost.used)
            return "Prepaid balance: \(providerCost.currencyCode) \(amount)"
        }
        if provider == .xapi, let balance = providerCost?.balance {
            let amount = String(format: "%.2f", balance)
            return "Prepaid credits: USD \(amount)"
        }
        if provider == .grok,
           let providerCost,
           providerCost.currencyCode == "USD",
           let balance = providerCost.balance,
           balance.isFinite,
           balance >= 0
        {
            let amount = String(format: "%.2f", balance)
            return "Prepaid balance: USD \(amount)"
        }
        guard provider == .copilot,
              rateWindows.isEmpty,
              let plan = snapshot?.identity?.loginMethod?.trimmingCharacters(in: .whitespacesAndNewlines),
              !plan.isEmpty
        else { return nil }
        // Unlimited and token-billed Copilot plans intentionally have no metered windows. Keep a
        // meaningful signal on the wire so QuotaKit's Mac/iOS ghost filters retain the provider.
        return "Plan: \(plan)"
    }

    static func syncBudgetSnapshot(
        provider: UsageProvider,
        providerCost: ProviderCostSnapshot?) -> SyncBudgetSnapshot?
    {
        // ZenMux, Neuralwatt, LithosAI, and xAI report remaining balances through
        // ProviderCostSnapshot with a zero limit. Those are not used/limit
        // budgets and would render on iOS as the false statement "$balance / $0".
        guard provider != .zenmux,
              provider != .neuralwatt,
              provider != .aiand,
              provider != .fireworks,
              provider != .lithosai,
              provider != .xapi,
              provider != .xai
        else {
            return nil
        }
        if provider == .claude,
           let providerCost,
           providerCost.limit <= 0,
           providerCost.balance != nil
        {
            return nil
        }
        if provider == .grok,
           let providerCost,
           providerCost.limit <= 0,
           providerCost.balance != nil
        {
            // Grok's purchased credits are a wallet, not a spend-only $0 budget.
            return nil
        }
        if provider == .opencode || provider == .codex,
           let providerCost,
           providerCost.limit <= 0
        {
            // A standalone Codex workspace credit pool is a balance, not a $0 budget.
            return nil
        }
        return providerCost.map { pc in
            SyncBudgetSnapshot(
                usedAmount: pc.used,
                limitAmount: pc.limit,
                currencyCode: pc.currencyCode,
                period: pc.period,
                resetsAt: pc.resetsAt,
                personalUsedAmount: pc.personalUsed)
        }
    }
}
