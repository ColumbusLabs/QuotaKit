import CodexBarCore
import CodexBarSync
import Foundation

extension SyncCoordinator {
    // MARK: - v0.26 envelope mappers

    static func mapOpenAIAPIDashboard(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncOpenAIAPIDashboard?
    {
        guard provider == .openai, let openai = snapshot?.openAIAPIUsage else { return nil }

        func summary(_ s: OpenAIAPIUsageSnapshot.Summary) -> SyncOpenAISummary {
            SyncOpenAISummary(
                totalCostUSD: s.costUSD,
                totalRequests: s.requests,
                totalTokens: s.totalTokens)
        }

        let dailyBuckets: [SyncOpenAIDailyBucket] = openai.daily.map { bucket in
            SyncOpenAIDailyBucket(
                dayKey: bucket.day,
                costUSD: bucket.costUSD,
                requests: bucket.requests,
                inputTokens: bucket.inputTokens,
                cachedInputTokens: bucket.cachedInputTokens,
                outputTokens: bucket.outputTokens,
                totalTokens: bucket.totalTokens)
        }

        // Top models — cost is not always exposed per-model by Admin
        // API; iOS can still rank by request count. Cap at 8 to keep
        // payload bounded.
        let topModels: [SyncOpenAIModelBreakdown] = Array(openai.topModels.prefix(8)).map { m in
            SyncOpenAIModelBreakdown(
                modelName: m.name,
                requests: m.requests,
                totalTokens: m.totalTokens,
                costUSD: 0)
        }

        let topLineItems: [SyncOpenAILineItem] = Array(openai.topLineItems.prefix(8)).map { li in
            SyncOpenAILineItem(name: li.name, costUSD: li.costUSD)
        }

        return SyncOpenAIAPIDashboard(
            last30Days: summary(openai.last30Days),
            last7Days: summary(openai.last7Days),
            latestDay: openai.daily.isEmpty ? nil : summary(openai.latestDay),
            dailyBuckets: dailyBuckets,
            topModels: topModels,
            topLineItems: topLineItems,
            historyDays: openai.historyDays)
    }

    static func mapZaiHourlyUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncZaiHourlyUsage?
    {
        guard provider == .zai, let model = snapshot?.zaiUsage?.modelUsage else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        let xTime: [Date] = model.xTime.compactMap { iso in
            formatter.date(from: iso) ?? fallback.date(from: iso)
        }
        // Skip if the time series didn't parse — iOS can't render
        // anything useful with mismatched x-axis.
        guard xTime.count == model.xTime.count, !xTime.isEmpty else { return nil }
        let series: [SyncZaiModelSeries] = model.modelDataList.compactMap { row in
            guard let name = row.modelName else { return nil }
            return SyncZaiModelSeries(modelName: name, tokens: row.tokensUsage)
        }
        guard !series.isEmpty else { return nil }
        return SyncZaiHourlyUsage(xTime: xTime, modelSeries: series)
    }

    static func mapKiroCredits(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncKiroCredits?
    {
        guard provider == .kiro, let k = snapshot?.kiroUsage else { return nil }
        // Percent: prefer Mac-computed; otherwise derive used / total.
        let percent: Double? = {
            if k.creditsTotal > 0 {
                return (k.creditsUsed / k.creditsTotal) * 100
            }
            return nil
        }()
        return SyncKiroCredits(
            planName: k.displayPlanName,
            creditsUsed: k.creditsUsed,
            creditsTotal: k.creditsTotal > 0 ? k.creditsTotal : nil,
            creditsPercent: percent,
            bonusUsed: k.bonusCreditsUsed,
            bonusTotal: k.bonusCreditsTotal,
            bonusExpiryDays: k.bonusExpiryDays,
            resetsAt: nil,
            overageCreditsUsed: k.overageCreditsUsed,
            estimatedOverageCostUSD: k.estimatedOverageCostUSD)
    }

    static func mapBedrockCost(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        providerCost: ProviderCostSnapshot?,
        region: String? = nil) -> SyncBedrockCost?
    {
        // Region comes from SettingsStore.bedrockRegion, not the composite
        // loginMethod display string. Token/request activity is preserved as a
        // structured BedrockUsageSnapshot when upstream publishes it.
        guard provider == .bedrock, let pc = providerCost else { return nil }
        let percent: Double? = pc.limit > 0
            ? min(max((pc.used / pc.limit) * 100, 0), 100)
            : nil
        return SyncBedrockCost(
            monthlySpendUSD: pc.used,
            monthlyBudgetUSD: pc.limit > 0 ? pc.limit : nil,
            inputTokens: snapshot?.bedrockUsage?.inputTokens,
            outputTokens: snapshot?.bedrockUsage?.outputTokens,
            requestCount: snapshot?.bedrockUsage?.requestCount,
            region: region,
            budgetUsedPercent: percent,
            updatedAt: snapshot?.updatedAt ?? Date())
    }

    static func mapMoonshotBalance(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        primaryWindow: SyncRateWindow?) -> SyncMoonshotBalance?
    {
        // Moonshot's upstream fetcher emits the API balance via
        // `loginMethod` as a localized string like "Balance: $58.40"
        // (or "Balance: $58.40 · $5 in deficit"). `providerCost` and
        // `primary` are BOTH nil in production — see
        // `MoonshotUsageSummary.toUsageSnapshot()`. We parse the
        // dollar amount out of loginMethod; fall back to nil when the
        // format drifts so iOS hides the card rather than show "0.00".
        guard provider == .moonshot else { return nil }
        let loginMethod = snapshot?.identity?.loginMethod ?? ""
        let parsed = Self.parseMoonshotBalance(from: loginMethod)
        // Fallback: if loginMethod isn't parseable (upstream changed
        // the format), keep trying providerCost / primaryWindow so a
        // future Moonshot version that exposes balance via providerCost
        // can land without a fork update.
        let amount = parsed?.amount
            ?? snapshot?.providerCost?.used
            ?? primaryWindow?.usedPercent
        guard let amount, amount > 0 else { return nil }
        return SyncMoonshotBalance(
            balanceAmount: amount,
            balanceCurrency: parsed?.currency ?? snapshot?.providerCost?.currencyCode,
            region: nil,
            updatedAt: snapshot?.updatedAt ?? Date())
    }

    /// Parses Moonshot's `loginMethod` display string into a structured
    /// (amount, currency) pair. The upstream string format is:
    ///
    ///     "Balance: $58.40"
    ///     "Balance: $58.40 · $5.00 in deficit"
    ///
    /// `UsageFormatter.usdString(58.40)` produces "$58.40" with a
    /// leading dollar sign. We strip the prefix label and currency
    /// symbol and parse the number. Returns nil for unrecognized
    /// formats (future-proof against upstream relabeling).
    static func parseMoonshotBalance(from loginMethod: String) -> (amount: Double, currency: String)? {
        // Match the first "Balance: <symbol><digits>.<digits>" token.
        // Range-bounded so we ignore the deficit suffix.
        guard let prefixRange = loginMethod.range(of: "Balance: ") else { return nil }
        let after = loginMethod[prefixRange.upperBound...]
        // Take up to the first separator (space, middle-dot, comma).
        let stopChars: Set<Character> = [" ", "·", ",", "\t"]
        let amountString = String(after.prefix(while: { !stopChars.contains($0) }))
        // Strip the leading currency symbol if present (USD only today).
        var currency = "USD"
        var digits = amountString
        if let first = digits.first, !first.isNumber, first != "-", first != "+" {
            switch first {
            case "$": currency = "USD"
            case "¥": currency = "CNY"
            case "€": currency = "EUR"
            default: break
            }
            digits.removeFirst()
        }
        guard let amount = Double(digits) else { return nil }
        return (amount, currency)
    }

    // MARK: - v0.27 envelope mappers

    static func mapGrokBilling(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncGrokBilling?
    {
        guard provider == .grok, let g = snapshot?.grokUsage else { return nil }
        // Prefer Grok CLI billing (richer — has cents-precise spend
        // and exact billing-period boundaries); fall back to grok.com
        // web billing if Mac took the web fallback path.
        let cliPercent = g.billing?.monthlyUsedPercent
        let webPercent = g.webBilling?.usedPercent
        let percent = cliPercent ?? webPercent
        // CLI exposes monthly cap + used-so-far as cents; convert to
        // USD here so iOS doesn't have to know about the cents wire
        // format. Web billing surfaces only a percentage so this lane
        // stays nil for web-billing-only Macs.
        let spend = g.billing?.usage?.totalUsed?.val.map { Double($0) / 100.0 }
        let limit = g.billing?.monthlyLimit?.val.map { Double($0) / 100.0 }
        let resetAt = g.billing?.billingPeriodEndDate
            ?? g.webBilling?.resetsAt
        // Upstream Grok does not surface a plan-tier string today;
        // wire field is reserved for a future Mac fetcher addition.
        let tier: String? = nil
        // Skip if no useful data — iOS will fall back to the generic
        // primary rate window.
        guard percent != nil || spend != nil else { return nil }
        return SyncGrokBilling(
            monthlyUsedPercent: percent,
            monthlySpendUSD: spend,
            monthlyLimitUSD: limit,
            billingPeriodEndDate: resetAt,
            planTier: tier,
            updatedAt: g.updatedAt)
    }

    static func mapElevenLabsCredits(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncElevenLabsCredits?
    {
        guard provider == .elevenlabs, let e = snapshot?.elevenLabsUsage else { return nil }
        return SyncElevenLabsCredits(
            tier: e.tier,
            characterCount: e.characterCount,
            characterLimit: e.characterLimit,
            usedPercent: e.usedPercent,
            voiceSlotsUsed: e.voiceSlotsUsed,
            voiceLimit: e.voiceLimit,
            professionalVoiceSlotsUsed: e.professionalVoiceSlotsUsed,
            professionalVoiceLimit: e.professionalVoiceLimit,
            resetsAt: e.resetsAt,
            updatedAt: e.updatedAt)
    }

    static func mapDeepgramUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncDeepgramUsage?
    {
        guard provider == .deepgram, let d = snapshot?.deepgramUsage else { return nil }
        return SyncDeepgramUsage(
            projectName: d.projectName,
            projectCount: d.projectCount,
            speechHours: d.hours,
            totalHours: d.totalHours,
            agentHours: d.agentHours,
            requests: d.requests,
            tokensIn: d.tokensIn,
            tokensOut: d.tokensOut,
            ttsCharacters: d.ttsCharacters,
            updatedAt: d.updatedAt)
    }

    static func mapGroqMetrics(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncGroqMetrics?
    {
        guard provider == .groq, let g = snapshot?.groqUsage else { return nil }
        return SyncGroqMetrics(
            requestsPerMinute: g.requestsPerMinute,
            tokensPerMinute: g.tokensPerMinute,
            cacheHitsPerMinute: g.cacheHitsPerMinute,
            updatedAt: g.updatedAt)
    }

    static func mapLLMProxyStats(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncLLMProxyStats?
    {
        guard provider == .llmproxy, let l = snapshot?.llmProxyUsage else { return nil }
        let topProviders = l.topProviders.prefix(3).map { p in
            SyncLLMProxyProviderSummary(
                name: p.name,
                requests: p.requests,
                tokens: p.tokens,
                approximateCostUSD: p.approximateCostUSD)
        }
        return SyncLLMProxyStats(
            providerCount: l.providerCount,
            credentialCount: l.credentialCount,
            activeCredentialCount: l.activeCredentialCount,
            exhaustedCredentialCount: l.exhaustedCredentialCount,
            totalRequests: l.totalRequests,
            totalTokens: l.totalTokens,
            approximateCostUSD: l.approximateCostUSD,
            minimumRemainingPercent: l.minimumRemainingPercent,
            nextResetAt: l.nextResetAt,
            topProviders: Array(topProviders),
            updatedAt: l.updatedAt)
    }

    // MARK: - v0.27 existing-provider extensions

    static func mapClaudeAdminUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncClaudeAdminUsage?
    {
        guard provider == .claude, let a = snapshot?.claudeAdminAPIUsage else { return nil }

        func mapWindow(_ s: ClaudeAdminAPIUsageSnapshot.Summary) -> SyncClaudeAdminWindowSummary {
            SyncClaudeAdminWindowSummary(
                costUSD: s.costUSD,
                totalTokens: s.totalTokens,
                inputTokens: s.inputTokens,
                outputTokens: s.outputTokens,
                cacheCreationInputTokens: s.cacheCreationInputTokens,
                cacheReadInputTokens: s.cacheReadInputTokens)
        }

        // Skip when there's literally no usage in the last 30 days —
        // iOS hides the Admin section in that case so we don't render
        // an empty card.
        let last30 = mapWindow(a.last30Days)
        if last30.totalTokens == 0, last30.costUSD == 0 { return nil }

        let topModels = Array(a.topModels.prefix(8)).map { m in
            SyncClaudeAdminModelBreakdown(name: m.name, totalTokens: m.totalTokens)
        }
        let topCostItems = Array(a.topCostItems.prefix(8)).map { c in
            SyncClaudeAdminCostItem(name: c.name, costUSD: c.costUSD)
        }
        return SyncClaudeAdminUsage(
            last30Days: last30,
            last7Days: mapWindow(a.last7Days),
            latestDay: a.daily.isEmpty ? nil : mapWindow(a.latestDay),
            topModels: topModels,
            topCostItems: topCostItems,
            updatedAt: a.updatedAt)
    }

    static func mapClaudeExtraUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        providerCost: ProviderCostSnapshot?) -> SyncClaudeExtraUsage?
    {
        guard provider == .claude else { return nil }
        // Claude extra-usage / spend-limit reaches `UsageSnapshot` via
        // two paths today and neither is structured:
        //   - OAuth → a RateWindow with `primaryWindowKind = .spendLimit`
        //     inside `ClaudeUsageFetcher` that gets flattened to the
        //     primary RateWindow before it lands on `UsageSnapshot`.
        //   - Web cookies → a `providerCost` with USD currency and
        //     `period` like "Last month" / "This month".
        //
        // We heuristically synthesise an envelope from `providerCost`
        // when both used + limit + USD currency are present. The
        // brittle OAuth path is deferred to a follow-up that adds a
        // structured field on `UsageSnapshot` to avoid string sniffing.
        // Until then, OAuth-only Claude accounts continue to surface
        // the spend-limit metric via the existing primary RateWindow.
        guard let cost = providerCost,
              cost.limit > 0,
              cost.currencyCode == "USD"
        else { return nil }

        let utilization = min(max((cost.used / cost.limit) * 100, 0), 100)
        let planTier: String? = {
            let login = snapshot?.identity?.loginMethod ?? ""
            if login.localizedCaseInsensitiveContains("enterprise") { return "Enterprise" }
            if login.localizedCaseInsensitiveContains("team") { return "Team" }
            if login.localizedCaseInsensitiveContains("max") { return "Max" }
            if login.localizedCaseInsensitiveContains("pro") { return "Pro" }
            return nil
        }()
        return SyncClaudeExtraUsage(
            utilization: utilization,
            monthlySpendUSD: cost.used,
            monthlyLimitUSD: cost.limit,
            isEnabled: true,
            planTier: planTier,
            updatedAt: snapshot?.updatedAt ?? cost.updatedAt)
    }

    static func mapOpenCodeGoZenBalance(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        providerCost: ProviderCostSnapshot?,
        workspaceID: String?) -> SyncOpenCodeGoZenBalance?
    {
        // Mac packs the Zen balance into `providerCost` with
        // `period = "Zen balance"` and currency USD (see
        // `OpenCodeGoUsageSnapshot.toUsageSnapshot()`). We detect that
        // signature rather than reading from a dedicated field so we
        // don't need to extend `UsageSnapshot` for this drop.
        guard provider == .opencodego,
              let cost = providerCost,
              cost.period == "Zen balance",
              cost.currencyCode == "USD"
        else { return nil }
        return SyncOpenCodeGoZenBalance(
            balanceUSD: cost.used,
            workspaceID: workspaceID,
            updatedAt: snapshot?.updatedAt ?? cost.updatedAt)
    }

    static func mapMiniMaxBilling(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncMiniMaxBillingHistory?
    {
        guard provider == .minimax,
              let b = snapshot?.minimaxUsage?.billingSummary
        else { return nil }
        let daily = b.daily.map { d in
            SyncMiniMaxBillingDay(day: d.day, tokens: d.tokens, cashUSD: d.cash)
        }
        let methods = b.topMethods.prefix(3).map { m in
            SyncMiniMaxBillingBreakdown(name: m.name, tokens: m.tokens, cashUSD: m.cash)
        }
        let models = b.topModels.prefix(3).map { m in
            SyncMiniMaxBillingBreakdown(name: m.name, tokens: m.tokens, cashUSD: m.cash)
        }
        // Skip when there's no signal at all — iOS keeps the existing
        // generic prompts card and we save wire bytes.
        if b.last30DaysTokens == 0, (b.last30DaysCash ?? 0) == 0, daily.isEmpty {
            return nil
        }
        return SyncMiniMaxBillingHistory(
            todayTokens: b.todayTokens,
            last30DaysTokens: b.last30DaysTokens,
            todayCashUSD: b.todayCash,
            last30DaysCashUSD: b.last30DaysCash,
            daily: daily,
            topMethods: Array(methods),
            topModels: Array(models),
            updatedAt: b.updatedAt)
    }

    /// Pure-function envelope builder extracted from `mapCodexWorkspace`
    /// for testability. Combines:
    ///   1) Workspace metadata from the active Codex account
    ///      (`workspaceLabel` + `workspaceAccountID`, set when
    ///      ManagedCodexAccountService resolves a ChatGPT-Account-Id
    ///      during sign-in).
    ///   2) Weekly pace derived from the snapshot's weekly RateWindow
    ///      via `UsagePace.weekly(window:)`. Mac uses the same code
    ///      path for its menu-bar pace caption so iOS sees identical
    ///      computation.
    ///
    /// Multi-account fan-out: the mapper is only called for the
    /// ACTIVE account's freshly-built snapshot. `expandCodexMultiAccount`
    /// caches that ProviderUsageSnapshot under the active account's
    /// UUID and later re-emits the cached value when the user looks at
    /// a different active account. So each cached snapshot's
    /// `codexWorkspace` reflects whatever was active at the time of
    /// build — correct per-account labelling without needing to
    /// thread account context into the mapper.
    static func buildCodexWorkspaceContext(
        activeAccount: ManagedCodexAccount?,
        snapshot: UsageSnapshot?) -> SyncCodexWorkspaceContext?
    {
        let workspaceLabel = activeAccount?.workspaceLabel
        let workspaceID = activeAccount?.workspaceAccountID

        let paceWindow = Self.codexWeeklyWindow(snapshot: snapshot)
        let pace = paceWindow.flatMap { UsagePace.weekly(window: $0) }
        let paceDelta: Double? = pace.map { $0.deltaPercent / 100.0 }
        let paceLabel: String? = pace.map { UsagePaceText.weeklySummary(pace: $0) }

        // Skip emitting an empty envelope so iOS doesn't render a
        // ghost row — every reader checks the optional.
        if workspaceLabel == nil, workspaceID == nil, paceDelta == nil {
            return nil
        }

        return SyncCodexWorkspaceContext(
            workspaceID: workspaceID,
            workspaceName: workspaceLabel,
            weeklyPaceDelta: paceDelta,
            weeklyPaceLabel: paceLabel,
            updatedAt: snapshot?.updatedAt ?? Date())
    }

    /// Picks the weekly-shaped rate window from a Codex snapshot.
    /// Codex builds put the weekly bucket in `secondary` today; fall
    /// back to scanning `primary` + `tertiary` if a future refactor
    /// shuffles the slots so the badge keeps rendering.
    private static func codexWeeklyWindow(snapshot: UsageSnapshot?) -> RateWindow? {
        let candidates: [RateWindow?] = [snapshot?.secondary, snapshot?.tertiary, snapshot?.primary]
        for window in candidates {
            guard let window else { continue }
            guard let minutes = window.windowMinutes else { continue }
            // Weekly window is 7 × 24 × 60 = 10080. Treat ≥ 1 day as
            // candidate so unusual upstream slots (5-day, 14-day, etc.)
            // still surface a pace badge.
            if minutes >= 24 * 60 { return window }
        }
        return nil
    }

    /// Builds a cost summary for Mistral from its native daily usage buckets
    /// (gap C). Mistral spend is API-billing based (no local token DB), so the
    /// generic token-DB `makeCostSummary` returns nil for it — without this,
    /// iOS only ever saw the one-line "API spend: $X" loginMethod. Feeding a
    /// SyncCostSummary lets iOS reuse the existing Cost dashboard (30-day chart
    /// + Model Mix) for Mistral, exactly like Codex/Claude. No envelope or iOS
    /// change needed — pure bridge plumbing.
    static func mapMistralCostSummary(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncCostSummary?
    {
        guard provider == .mistral, let m = snapshot?.mistralUsage, !m.daily.isEmpty else {
            return nil
        }
        let daily: [SyncDailyPoint] = m.daily.map { bucket in
            SyncDailyPoint(
                dayKey: bucket.day,
                costUSD: bucket.cost,
                totalTokens: bucket.totalTokens,
                modelBreakdowns: bucket.models
                    .filter { $0.cost > 0 }
                    .map { SyncCostBreakdown(label: $0.name, costUSD: $0.cost) }
                    .sorted { $0.costUSD > $1.costUSD },
                serviceBreakdowns: [],
                isEstimated: nil)
        }
        return SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: m.totalCost,
            last30DaysTokens: m.totalInputTokens + m.totalOutputTokens + m.totalCachedTokens,
            daily: daily,
            isEstimated: nil,
            currencyCode: m.currency)
    }

    /// Maps OpenRouter's native balance/credits + per-key usage windows into
    /// the wire envelope (gap D). Before this, all of OpenRouter's
    /// /api/v1/credits + /api/v1/key data collapsed to a "Balance: $X"
    /// loginMethod line on iOS.
    static func mapOpenRouter(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncOpenRouterStats?
    {
        guard provider == .openrouter, let o = snapshot?.openRouterUsage else { return nil }
        return SyncOpenRouterStats(
            balanceUSD: o.balance,
            totalCreditsUSD: o.totalCredits,
            totalUsageUSD: o.totalUsage,
            usedPercent: o.usedPercent,
            keyUsageDailyUSD: o.keyUsageDaily,
            keyUsageWeeklyUSD: o.keyUsageWeekly,
            keyUsageMonthlyUSD: o.keyUsageMonthly,
            keyLimitUSD: o.keyLimit,
            rateLimitRequests: o.rateLimit?.requests,
            rateLimitInterval: o.rateLimit?.interval,
            updatedAt: o.updatedAt)
    }

    /// Maps Azure OpenAI deployment identity into the wire envelope (gap E).
    /// Azure is a deployment-validation provider; before this the endpoint host
    /// was dropped (envelope has no accountOrganization) and the deployment
    /// only reached iOS as a loginMethod string.
    static func mapAzureOpenAIInfo(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncAzureOpenAIInfo?
    {
        guard provider == .azureopenai, let a = snapshot?.azureOpenAIUsage else { return nil }
        return SyncAzureOpenAIInfo(
            endpointHost: a.endpointHost,
            deploymentName: a.deploymentName,
            model: a.model,
            apiVersion: a.apiVersion,
            updatedAt: a.updatedAt)
    }

    /// Maps Alibaba Token Plan (Bailian) structured credit quota into the wire
    /// envelope (gap G). The quota % + a "credits used" string already cross via
    /// the generic RateWindow; this adds the structured numbers for a proper card.
    static func mapAlibabaTokenPlan(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncAlibabaTokenPlan?
    {
        guard provider == .alibabatokenplan, let a = snapshot?.alibabaTokenPlanUsage else { return nil }
        return SyncAlibabaTokenPlan(
            planName: a.planName,
            usedCredits: a.usedQuota,
            totalCredits: a.totalQuota,
            remainingCredits: a.remainingQuota,
            resetsAt: a.resetsAt,
            updatedAt: a.updatedAt)
    }

    /// Maps DeepSeek web-session usage + cost summary into the wire envelope
    /// (upstream v0.30.0 #1166). Balance stays on the generic primary
    /// RateWindow (a formatted string built in `toUsageSnapshot()`), so only
    /// the new usage/cost numbers cross here.
    static func mapDeepSeekUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncDeepSeekUsage?
    {
        guard provider == .deepseek, let ds = snapshot?.deepseekUsage else { return nil }
        return SyncDeepSeekUsage(
            todayTokens: ds.todayTokens,
            monthTokens: ds.currentMonthTokens,
            todayCost: ds.todayCost,
            monthCost: ds.currentMonthCost,
            todayRequests: ds.requestCount,
            monthRequests: ds.currentMonthRequestCount,
            topModel: ds.topModel,
            currency: ds.currency,
            totalBalanceUSD: nil,
            grantedBalanceUSD: nil,
            toppedUpBalanceUSD: nil,
            daily: ds.daily.map {
                SyncDeepSeekDaily(
                    dayKey: $0.date,
                    totalTokens: $0.totalTokens,
                    cost: $0.cost,
                    requestCount: $0.requestCount)
            },
            updatedAt: ds.updatedAt)
    }

    static func mapCrossModelUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncCrossModelUsage?
    {
        guard provider == .crossmodel, let usage = snapshot?.crossModelUsage else { return nil }
        return SyncCrossModelUsage(
            currency: usage.currency,
            balance: usage.balance,
            uncollected: usage.uncollected,
            daily: usage.daily.map(Self.mapCrossModelWindow),
            weekly: usage.weekly.map(Self.mapCrossModelWindow),
            monthly: usage.monthly.map(Self.mapCrossModelWindow),
            updatedAt: usage.updatedAt)
    }

    private static func mapCrossModelWindow(_ window: CrossModelUsageWindow) -> SyncCrossModelUsageWindow {
        SyncCrossModelUsageWindow(
            cost: window.cost,
            promptTokens: window.promptTokens,
            completionTokens: window.completionTokens,
            totalTokens: window.totalTokens,
            requestCount: window.requestCount,
            successCount: window.successCount)
    }
}
