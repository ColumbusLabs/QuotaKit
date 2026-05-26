import Foundation

// Provider-specific sync envelope blocks added in iOS 1.9.0 / Mac 0.29.0 to
// close Mac↔iOS display-parity gaps surfaced by the 2026-05-26 parity audit.
// All blocks are optional + decoded via synthesized `Codable` (a missing key
// decodes as `nil`), so they ride inside the existing zlib payload with no
// CloudKit schema change and stay wire-compatible both directions.

// MARK: - OpenRouter balance + credits + key usage (gap D)

/// OpenRouter account balance/credits plus per-API-key usage windows.
/// Populated only on the `openrouter` provider snapshot. Before this the Mac
/// reduced all of OpenRouter's `/api/v1/credits` + `/api/v1/key` data to a
/// single `loginMethod: "Balance: $X"` line; iOS now renders a dedicated card.
public struct SyncOpenRouterStats: Codable, Sendable, Equatable {
    /// Remaining credit balance in USD (`totalCredits - totalUsage`).
    public let balanceUSD: Double
    /// Lifetime credits purchased/granted in USD.
    public let totalCreditsUSD: Double
    /// Lifetime usage in USD.
    public let totalUsageUSD: Double
    /// 0–100 lifetime utilization (`totalUsage / totalCredits * 100`).
    public let usedPercent: Double
    /// Per-key usage in USD over the rolling day/week/month, when the
    /// `/api/v1/key` endpoint returned them (nil otherwise).
    public let keyUsageDailyUSD: Double?
    public let keyUsageWeeklyUSD: Double?
    public let keyUsageMonthlyUSD: Double?
    /// Per-key spend limit in USD, if the key is capped.
    public let keyLimitUSD: Double?
    /// Rate-limit allowance (e.g. `20` requests per `"10s"`), when present.
    public let rateLimitRequests: Int?
    public let rateLimitInterval: String?
    public let updatedAt: Date

    public init(
        balanceUSD: Double,
        totalCreditsUSD: Double,
        totalUsageUSD: Double,
        usedPercent: Double,
        keyUsageDailyUSD: Double?,
        keyUsageWeeklyUSD: Double?,
        keyUsageMonthlyUSD: Double?,
        keyLimitUSD: Double?,
        rateLimitRequests: Int?,
        rateLimitInterval: String?,
        updatedAt: Date)
    {
        self.balanceUSD = balanceUSD
        self.totalCreditsUSD = totalCreditsUSD
        self.totalUsageUSD = totalUsageUSD
        self.usedPercent = usedPercent
        self.keyUsageDailyUSD = keyUsageDailyUSD
        self.keyUsageWeeklyUSD = keyUsageWeeklyUSD
        self.keyUsageMonthlyUSD = keyUsageMonthlyUSD
        self.keyLimitUSD = keyLimitUSD
        self.rateLimitRequests = rateLimitRequests
        self.rateLimitInterval = rateLimitInterval
        self.updatedAt = updatedAt
    }
}

// MARK: - Azure OpenAI deployment info (gap E)

/// Azure OpenAI deployment identity. Populated only on the `azureopenai`
/// provider snapshot. Azure OpenAI is a deployment-validation provider (no
/// usage %), so before this iOS only saw the endpoint host folded into a
/// `loginMethod` string and the host was dropped entirely (the envelope has
/// no `accountOrganization`). iOS now renders the endpoint + deployment in a
/// small structured card.
public struct SyncAzureOpenAIInfo: Codable, Sendable, Equatable {
    /// API endpoint host, e.g. `my-resource.openai.azure.com`.
    public let endpointHost: String
    /// Deployment name configured in Azure.
    public let deploymentName: String
    /// Underlying model the deployment serves, when reported.
    public let model: String?
    /// Azure REST API version the probe used.
    public let apiVersion: String
    public let updatedAt: Date

    public init(
        endpointHost: String,
        deploymentName: String,
        model: String?,
        apiVersion: String,
        updatedAt: Date)
    {
        self.endpointHost = endpointHost
        self.deploymentName = deploymentName
        self.model = model
        self.apiVersion = apiVersion
        self.updatedAt = updatedAt
    }
}

// MARK: - Alibaba Token Plan (Bailian) structured quota (gap G)

/// Alibaba Token Plan (Bailian) structured credit quota. Populated only on the
/// `alibabatokenplan` provider snapshot. The quota % + a "credits used" string
/// already cross via the generic RateWindow; this block adds the structured
/// numbers + plan name so iOS can render a proper credits card.
public struct SyncAlibabaTokenPlan: Codable, Sendable, Equatable {
    public let planName: String?
    public let usedCredits: Double?
    public let totalCredits: Double?
    public let remainingCredits: Double?
    public let resetsAt: Date?
    public let updatedAt: Date

    public init(
        planName: String?,
        usedCredits: Double?,
        totalCredits: Double?,
        remainingCredits: Double?,
        resetsAt: Date?,
        updatedAt: Date)
    {
        self.planName = planName
        self.usedCredits = usedCredits
        self.totalCredits = totalCredits
        self.remainingCredits = remainingCredits
        self.resetsAt = resetsAt
        self.updatedAt = updatedAt
    }
}
