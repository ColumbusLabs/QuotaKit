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
