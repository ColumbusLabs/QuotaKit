import Foundation

// MARK: - Grok billing (upstream v0.27.0, NEW provider)

/// Grok (xAI) monthly billing summary. Populated only on the `grok`
/// provider snapshot.
///
/// Mac surfaces this from either the Grok CLI billing RPC
/// (`grok agent stdio`) or the grok.com web-billing fallback. Both
/// produce the same envelope shape so iOS doesn't care which source
/// the Mac chose.
public struct SyncGrokBilling: Codable, Sendable, Equatable {
    /// 0..100 monthly credit utilisation. Nil when neither source
    /// surfaced a percentage (rare — usually means an auth issue).
    public let monthlyUsedPercent: Double?
    /// USD spend in the current billing period. May be present
    /// even when `monthlyUsedPercent` is nil (e.g. pay-as-you-go
    /// with no fixed cap).
    public let monthlySpendUSD: Double?
    /// Monthly cap in USD; pairs with `monthlySpendUSD` to render
    /// a "X.XX / Y" gauge on iOS. Nil for pay-as-you-go accounts.
    public let monthlyLimitUSD: Double?
    /// End of the current billing period (renewal date). Nil when
    /// Mac could not parse the billing-period boundary.
    public let billingPeriodEndDate: Date?
    /// User-readable plan tier ("Pro", "Free", "Team", etc.). Nil
    /// when the CLI did not surface a tier string.
    public let planTier: String?
    public let updatedAt: Date

    public init(
        monthlyUsedPercent: Double?,
        monthlySpendUSD: Double?,
        monthlyLimitUSD: Double?,
        billingPeriodEndDate: Date?,
        planTier: String?,
        updatedAt: Date)
    {
        self.monthlyUsedPercent = monthlyUsedPercent
        self.monthlySpendUSD = monthlySpendUSD
        self.monthlyLimitUSD = monthlyLimitUSD
        self.billingPeriodEndDate = billingPeriodEndDate
        self.planTier = planTier
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.monthlyUsedPercent = try c.decodeIfPresent(Double.self, forKey: .monthlyUsedPercent)
        self.monthlySpendUSD = try c.decodeIfPresent(Double.self, forKey: .monthlySpendUSD)
        self.monthlyLimitUSD = try c.decodeIfPresent(Double.self, forKey: .monthlyLimitUSD)
        self.billingPeriodEndDate = try c.decodeIfPresent(Date.self, forKey: .billingPeriodEndDate)
        self.planTier = try c.decodeIfPresent(String.self, forKey: .planTier)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - ElevenLabs credits + voice slots (upstream v0.27.0, NEW provider)

/// ElevenLabs API subscription state. Populated only on the
/// `elevenlabs` provider snapshot.
///
/// ElevenLabs is character-credit based (not USD), so cost data is
/// not surfaced — iOS shows characters + voice slot counts instead.
public struct SyncElevenLabsCredits: Codable, Sendable, Equatable {
    /// Plan tier ("free", "starter", "creator", "pro", "scale",
    /// "business", "enterprise"). Display-name decision lives on
    /// iOS so it can localise.
    public let tier: String?
    /// Characters consumed in the current month.
    public let characterCount: Int
    /// Monthly character allowance. May be 0 for unlimited
    /// enterprise plans — render as "Unlimited" when 0.
    public let characterLimit: Int
    /// Pre-computed `characterCount / characterLimit * 100`,
    /// clamped 0..100. iOS could derive locally but Mac already
    /// does it for the menu bar.
    public let usedPercent: Double
    /// Standard voice slots used / limit. Nil pairs (e.g. free
    /// plan with no slot tracking) → hide voice-slot row.
    public let voiceSlotsUsed: Int?
    public let voiceLimit: Int?
    /// Professional voice slots used / limit. Separate from
    /// `voiceSlotsUsed` because the two pools are independent.
    public let professionalVoiceSlotsUsed: Int?
    public let professionalVoiceLimit: Int?
    /// Subscription renewal date.
    public let resetsAt: Date?
    public let updatedAt: Date

    public init(
        tier: String?,
        characterCount: Int,
        characterLimit: Int,
        usedPercent: Double,
        voiceSlotsUsed: Int?,
        voiceLimit: Int?,
        professionalVoiceSlotsUsed: Int?,
        professionalVoiceLimit: Int?,
        resetsAt: Date?,
        updatedAt: Date)
    {
        self.tier = tier
        self.characterCount = characterCount
        self.characterLimit = characterLimit
        self.usedPercent = usedPercent
        self.voiceSlotsUsed = voiceSlotsUsed
        self.voiceLimit = voiceLimit
        self.professionalVoiceSlotsUsed = professionalVoiceSlotsUsed
        self.professionalVoiceLimit = professionalVoiceLimit
        self.resetsAt = resetsAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Deepgram usage (upstream v0.27.0, NEW provider)

/// Deepgram speech/agent/TTS usage breakdown. Populated only on the
/// `deepgram` provider snapshot.
///
/// Deepgram is project-based — a single API key may have multiple
/// projects. The Mac fetcher picks the highest-volume project as
/// the primary view; `projectCount` lets iOS show "Project X (of N)"
/// to hint that there are more.
public struct SyncDeepgramUsage: Codable, Sendable, Equatable {
    public let projectName: String?
    /// Number of projects on this API key. ≥1.
    public let projectCount: Int
    /// Speech hours billed in the current window.
    public let speechHours: Double
    /// Sum of all billable hours (speech + agent + TTS).
    public let totalHours: Double
    /// Agent (LLM-augmented) hours, subset of totalHours.
    public let agentHours: Double
    /// Total request count for the window.
    public let requests: Int
    /// LLM input tokens (when agent mode produced any).
    public let tokensIn: Int
    /// LLM output tokens (when agent mode produced any).
    public let tokensOut: Int
    /// TTS character count.
    public let ttsCharacters: Int
    public let updatedAt: Date

    public init(
        projectName: String?,
        projectCount: Int,
        speechHours: Double,
        totalHours: Double,
        agentHours: Double,
        requests: Int,
        tokensIn: Int,
        tokensOut: Int,
        ttsCharacters: Int,
        updatedAt: Date)
    {
        self.projectName = projectName
        self.projectCount = projectCount
        self.speechHours = speechHours
        self.totalHours = totalHours
        self.agentHours = agentHours
        self.requests = requests
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.ttsCharacters = ttsCharacters
        self.updatedAt = updatedAt
    }
}

// MARK: - GroqCloud Prometheus metrics (upstream v0.27.0, NEW provider)

/// GroqCloud Enterprise Prometheus rate metrics. Populated only on
/// the `groq` provider snapshot.
///
/// GroqCloud Enterprise exposes per-second rates which Mac
/// pre-multiplies to per-minute numbers for human-friendly display.
/// Cache hit rate ≥0 indicates whether prompt caching is helping
/// — iOS renders it as a percentage when `requestsPerMinute` > 0.
public struct SyncGroqMetrics: Codable, Sendable, Equatable {
    public let requestsPerMinute: Double
    public let tokensPerMinute: Double
    public let cacheHitsPerMinute: Double
    public let updatedAt: Date

    public init(
        requestsPerMinute: Double,
        tokensPerMinute: Double,
        cacheHitsPerMinute: Double,
        updatedAt: Date)
    {
        self.requestsPerMinute = requestsPerMinute
        self.tokensPerMinute = tokensPerMinute
        self.cacheHitsPerMinute = cacheHitsPerMinute
        self.updatedAt = updatedAt
    }

    /// Convenience: cache-hit ratio as a percentage of total
    /// requests. Returns nil when requestsPerMinute ≤ 0 (avoid
    /// division by zero — iOS skips the badge in that case).
    public var cacheHitPercent: Double? {
        guard self.requestsPerMinute > 0 else { return nil }
        return (self.cacheHitsPerMinute / self.requestsPerMinute) * 100
    }
}

// MARK: - LLM Proxy aggregate (upstream v0.27.0, NEW provider)

/// Per-upstream-provider summary inside the LLM Proxy aggregate.
public struct SyncLLMProxyProviderSummary: Codable, Sendable, Equatable {
    public let name: String
    public let requests: Int
    public let tokens: Int
    public let approximateCostUSD: Double?

    public init(
        name: String,
        requests: Int,
        tokens: Int,
        approximateCostUSD: Double?)
    {
        self.name = name
        self.requests = requests
        self.tokens = tokens
        self.approximateCostUSD = approximateCostUSD
    }
}

/// LLM Proxy is a meta-provider that aggregates many upstream
/// providers; its envelope rolls the cross-provider stats into one
/// summary plus a top-N list. Populated only on the `llmproxy`
/// provider snapshot.
public struct SyncLLMProxyStats: Codable, Sendable, Equatable {
    /// Total upstream providers configured behind the proxy.
    public let providerCount: Int
    /// Number of API credentials configured.
    public let credentialCount: Int
    /// Credentials currently active (not exhausted).
    public let activeCredentialCount: Int
    /// Credentials that hit their quota and are temporarily out.
    public let exhaustedCredentialCount: Int
    /// Aggregate request count across all upstream providers.
    public let totalRequests: Int
    /// Aggregate token count across all upstream providers.
    public let totalTokens: Int
    /// Best-effort USD cost estimate (sum of per-provider
    /// approximate costs). Nil when no upstream surfaced cost.
    public let approximateCostUSD: Double?
    /// Lowest remaining-quota percent across all credentials —
    /// 0..100. iOS uses this as the headline "X% used" badge.
    public let minimumRemainingPercent: Double?
    /// Earliest credential reset across all upstream providers.
    public let nextResetAt: Date?
    /// Top upstream providers by request count, capped to 3 by Mac.
    public let topProviders: [SyncLLMProxyProviderSummary]
    public let updatedAt: Date

    public init(
        providerCount: Int,
        credentialCount: Int,
        activeCredentialCount: Int,
        exhaustedCredentialCount: Int,
        totalRequests: Int,
        totalTokens: Int,
        approximateCostUSD: Double?,
        minimumRemainingPercent: Double?,
        nextResetAt: Date?,
        topProviders: [SyncLLMProxyProviderSummary],
        updatedAt: Date)
    {
        self.providerCount = providerCount
        self.credentialCount = credentialCount
        self.activeCredentialCount = activeCredentialCount
        self.exhaustedCredentialCount = exhaustedCredentialCount
        self.totalRequests = totalRequests
        self.totalTokens = totalTokens
        self.approximateCostUSD = approximateCostUSD
        self.minimumRemainingPercent = minimumRemainingPercent
        self.nextResetAt = nextResetAt
        self.topProviders = topProviders
        self.updatedAt = updatedAt
    }
}

// MARK: - Claude Admin API spend (upstream v0.27.0, existing-provider extension)

/// Compact aggregate from Anthropic Admin API (`sk-ant-admin…`). Mirrors
/// the Mac-side `ClaudeAdminAPIUsageSnapshot` but trimmed to the
/// summaries iOS needs to render the dedicated "Admin API" section on
/// the Claude detail page. Populated only on the `claude` provider
/// snapshot when Mac has an Admin API key configured.
///
/// Wire compatibility: optional + `decodeIfPresent`. Pre-1.8.0 iOS
/// ignores the field; Mac without Admin API access never emits it.
public struct SyncClaudeAdminWindowSummary: Codable, Sendable, Equatable {
    /// Window cost in USD (sum of `daily.costUSD` for the selected window).
    public let costUSD: Double
    /// Total tokens billed in the window (input + output + cache).
    public let totalTokens: Int
    /// Input tokens (excludes cache-read which is billed at a lower rate).
    public let inputTokens: Int
    /// Output tokens.
    public let outputTokens: Int
    /// Cache creation tokens (subset of input, billed at a higher rate).
    public let cacheCreationInputTokens: Int
    /// Cache read tokens (subset of input, billed at a much lower rate).
    public let cacheReadInputTokens: Int

    public init(
        costUSD: Double,
        totalTokens: Int,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheReadInputTokens: Int)
    {
        self.costUSD = costUSD
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }
}

public struct SyncClaudeAdminModelBreakdown: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let totalTokens: Int

    public var id: String { self.name }

    public init(name: String, totalTokens: Int) {
        self.name = name
        self.totalTokens = totalTokens
    }
}

public struct SyncClaudeAdminCostItem: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let costUSD: Double

    public var id: String { self.name }

    public init(name: String, costUSD: Double) {
        self.name = name
        self.costUSD = costUSD
    }
}

public struct SyncClaudeAdminUsage: Codable, Sendable, Equatable {
    /// 30-day summary used as the headline metric on the Admin API
    /// section.
    public let last30Days: SyncClaudeAdminWindowSummary
    /// 7-day summary.
    public let last7Days: SyncClaudeAdminWindowSummary
    /// Latest day (today, or the last day with data). Nil when no daily
    /// data is available — iOS hides the "Today" card in that case.
    public let latestDay: SyncClaudeAdminWindowSummary?
    /// Top models sorted by total tokens descending. Capped to 8 by Mac
    /// mapper to keep payload bounded.
    public let topModels: [SyncClaudeAdminModelBreakdown]
    /// Top cost items (Anthropic surfaces these as `cost_items` such as
    /// "input_tokens", "output_tokens", "cache_*", "tools.*"). Capped
    /// to 8 by Mac.
    public let topCostItems: [SyncClaudeAdminCostItem]
    public let updatedAt: Date

    public init(
        last30Days: SyncClaudeAdminWindowSummary,
        last7Days: SyncClaudeAdminWindowSummary,
        latestDay: SyncClaudeAdminWindowSummary?,
        topModels: [SyncClaudeAdminModelBreakdown],
        topCostItems: [SyncClaudeAdminCostItem],
        updatedAt: Date)
    {
        self.last30Days = last30Days
        self.last7Days = last7Days
        self.latestDay = latestDay
        self.topModels = topModels
        self.topCostItems = topCostItems
        self.updatedAt = updatedAt
    }
}

// MARK: - Claude Enterprise spend-limit (upstream v0.27.0, existing-provider extension)

/// Anthropic OAuth `extra_usage` block — the spend-limit metric that
/// Enterprise (and Team-with-extra-usage) plans expose. Populated only
/// on the `claude` provider snapshot when Mac sees `extra_usage` in the
/// OAuth response, or when Web cookies reveal `overage_spend_limit`.
///
/// `monthlySpendUSD` may be present without `monthlyLimitUSD` (Team
/// plans without a cap). When `monthlyLimitUSD` is present, iOS
/// renders a "X.XX / Y" gauge using `utilization` as the visual fill.
public struct SyncClaudeExtraUsage: Codable, Sendable, Equatable {
    /// 0..100 utilization of the monthly extra-usage budget. iOS uses
    /// this directly for the bar; falls back to spend/limit computation
    /// when nil.
    public let utilization: Double?
    /// Current period spend in USD. May be nil for OAuth tokens that
    /// don't expose dollar amounts (some Pro tiers).
    public let monthlySpendUSD: Double?
    /// Configured monthly cap in USD. Nil for uncapped Team plans —
    /// iOS hides the "/ $X" suffix in that case.
    public let monthlyLimitUSD: Double?
    /// Whether the user has enabled extra-usage billing on the
    /// Anthropic console. When false, iOS shows a "Disabled" badge
    /// instead of a usage bar.
    public let isEnabled: Bool
    /// User-readable plan tier ("Pro", "Max", "Team", "Enterprise") to
    /// label the badge. Nil when Mac could not infer.
    public let planTier: String?
    public let updatedAt: Date

    public init(
        utilization: Double?,
        monthlySpendUSD: Double?,
        monthlyLimitUSD: Double?,
        isEnabled: Bool,
        planTier: String?,
        updatedAt: Date)
    {
        self.utilization = utilization
        self.monthlySpendUSD = monthlySpendUSD
        self.monthlyLimitUSD = monthlyLimitUSD
        self.isEnabled = isEnabled
        self.planTier = planTier
        self.updatedAt = updatedAt
    }
}

// MARK: - OpenCode Go Zen balance (upstream v0.27.0, existing-provider extension)

/// OpenCode Go Zen workspace balance — the pay-as-you-go USD balance
/// surfaced when the user has a Zen-enabled workspace. Populated only
/// on the `opencodego` provider snapshot when Mac is able to scrape
/// the workspace dashboard for a balance value.
///
/// When nil (no Zen workspace, or balance scrape failed), iOS keeps
/// rendering the existing rolling/weekly/monthly rate windows alone —
/// the Zen lane just doesn't appear.
public struct SyncOpenCodeGoZenBalance: Codable, Sendable, Equatable {
    /// Current Zen balance in USD. Always present when the struct is
    /// emitted — `nil` balances cause Mac to skip emitting the field
    /// at all (so iOS distinguishes "no Zen workspace" from "balance is
    /// zero" by field presence).
    public let balanceUSD: Double
    /// Workspace ID that this balance applies to. Lets iOS show the
    /// workspace name in the badge when more than one is configured.
    public let workspaceID: String?
    public let updatedAt: Date

    public init(balanceUSD: Double, workspaceID: String?, updatedAt: Date) {
        self.balanceUSD = balanceUSD
        self.workspaceID = workspaceID
        self.updatedAt = updatedAt
    }
}

// MARK: - MiniMax 30-day billing history (upstream v0.27.0, existing-provider extension)

/// One daily row inside `SyncMiniMaxBillingHistory.daily`. Cash is
/// optional because MiniMax's billing endpoint may return tokens-only
/// rows for accounts that haven't enabled USD billing.
public struct SyncMiniMaxBillingDay: Codable, Sendable, Equatable, Identifiable {
    public let day: String
    public let tokens: Int
    public let cashUSD: Double?

    public var id: String { self.day }

    public init(day: String, tokens: Int, cashUSD: Double?) {
        self.day = day
        self.tokens = tokens
        self.cashUSD = cashUSD
    }
}

/// One method / model breakdown row.
public struct SyncMiniMaxBillingBreakdown: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let tokens: Int
    public let cashUSD: Double?

    public var id: String { self.name }

    public init(name: String, tokens: Int, cashUSD: Double?) {
        self.name = name
        self.tokens = tokens
        self.cashUSD = cashUSD
    }
}

/// 30-day MiniMax billing summary. Populated only on the `minimax`
/// provider snapshot when Mac has an API key (Web-cookie accounts
/// don't have access to billing history). iOS renders this as a
/// 30-day token chart with top-3 method/model breakdowns beneath.
public struct SyncMiniMaxBillingHistory: Codable, Sendable, Equatable {
    public let todayTokens: Int
    public let last30DaysTokens: Int
    public let todayCashUSD: Double?
    public let last30DaysCashUSD: Double?
    /// Up to 30 daily rows ordered ascending by day. Days with no
    /// activity are omitted; iOS fills gaps client-side.
    public let daily: [SyncMiniMaxBillingDay]
    /// Top 3 method names by token volume.
    public let topMethods: [SyncMiniMaxBillingBreakdown]
    /// Top 3 models by token volume.
    public let topModels: [SyncMiniMaxBillingBreakdown]
    public let updatedAt: Date

    public init(
        todayTokens: Int,
        last30DaysTokens: Int,
        todayCashUSD: Double?,
        last30DaysCashUSD: Double?,
        daily: [SyncMiniMaxBillingDay],
        topMethods: [SyncMiniMaxBillingBreakdown],
        topModels: [SyncMiniMaxBillingBreakdown],
        updatedAt: Date)
    {
        self.todayTokens = todayTokens
        self.last30DaysTokens = last30DaysTokens
        self.todayCashUSD = todayCashUSD
        self.last30DaysCashUSD = last30DaysCashUSD
        self.daily = daily
        self.topMethods = topMethods
        self.topModels = topModels
        self.updatedAt = updatedAt
    }
}

// MARK: - Codex workspace + weekly pace (upstream v0.27.0, existing-provider extension)

/// Codex workspace context for the active account snapshot. Captures
/// the upstream v0.27.0 additions: workspace grouping (an account can
/// belong to a workspace separate from its personal context) and the
/// "weekly pace" metric (how fast you're burning the weekly quota
/// relative to a linear pace through the week).
///
/// Populated only on the `codex` provider snapshot when Mac has parsed
/// workspace data from the OpenAI dashboard. iOS shows the workspace
/// name as a small caption row beneath the account email and the pace
/// as a directional badge (e.g. "+12% ahead of pace" in orange when
/// burning fast, "-8% under pace" in green when slow).
public struct SyncCodexWorkspaceContext: Codable, Sendable, Equatable {
    /// Workspace ID surfaced by the OpenAI dashboard. Stable across
    /// reloads — safe to use as a stable iOS identifier.
    public let workspaceID: String?
    /// Human-readable workspace name. iOS prefers this for display.
    public let workspaceName: String?
    /// Weekly pace ratio — a signed value where 0 = on pace,
    /// +0.10 = 10% ahead of pace (burning faster), -0.10 = 10% below.
    /// Computed by Mac as `actualPercentSoFar / linearPaceTillNow - 1`.
    /// Nil when the week has just rolled over (insufficient data).
    public let weeklyPaceDelta: Double?
    /// Mac-resolved descriptive label for the pace (localized on Mac,
    /// e.g. "Ahead of pace" / "Under pace" / "On pace"). iOS shows
    /// this verbatim — it's already in the user's Mac locale and
    /// matches what the menu bar shows.
    public let weeklyPaceLabel: String?
    public let updatedAt: Date

    public init(
        workspaceID: String?,
        workspaceName: String?,
        weeklyPaceDelta: Double?,
        weeklyPaceLabel: String?,
        updatedAt: Date)
    {
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.weeklyPaceDelta = weeklyPaceDelta
        self.weeklyPaceLabel = weeklyPaceLabel
        self.updatedAt = updatedAt
    }
}
