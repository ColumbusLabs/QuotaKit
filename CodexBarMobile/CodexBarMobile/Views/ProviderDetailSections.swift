import CodexBarSync
import SwiftUI

enum ProviderDetailPrimarySection {
    case perplexity(SyncPerplexityCreditSummary)
    case suppressedByDedicatedCard
    case genericRateLimits
}

enum ProviderDetailSection: Identifiable {
    case kiro(SyncKiroCredits)
    case bedrock(SyncBedrockCost)
    case moonshot(SyncMoonshotBalance)
    case zai(SyncZaiHourlyUsage)
    case openAI(SyncOpenAIAPIDashboard)
    case antigravity(SyncMultiAccountList)
    case grok(SyncGrokBilling)
    case elevenLabs(SyncElevenLabsCredits)
    case deepgram(SyncDeepgramUsage)
    case groq(SyncGroqMetrics)
    case llmProxy(SyncLLMProxyStats)
    case openRouter(SyncOpenRouterStats)
    case azureOpenAI(SyncAzureOpenAIInfo)
    case alibabaTokenPlan(SyncAlibabaTokenPlan)
    case deepSeek(SyncDeepSeekUsage)
    case claudeAdmin(SyncClaudeAdminUsage)
    case claudeExtra(SyncClaudeExtraUsage)
    case openCodeGoZen(SyncOpenCodeGoZenBalance)
    case minimax(SyncMiniMaxBillingHistory)
    case codexWorkspace(SyncCodexWorkspaceContext, showsPace: Bool)

    var id: String {
        switch self {
        case .kiro:
            "kiro"
        case .bedrock:
            "bedrock"
        case .moonshot:
            "moonshot"
        case .zai:
            "zai"
        case .openAI:
            "openai"
        case .antigravity:
            "antigravity"
        case .grok:
            "grok"
        case .elevenLabs:
            "elevenlabs"
        case .deepgram:
            "deepgram"
        case .groq:
            "groq"
        case .llmProxy:
            "llmproxy"
        case .openRouter:
            "openrouter"
        case .azureOpenAI:
            "azureopenai"
        case .alibabaTokenPlan:
            "alibabatokenplan"
        case .deepSeek:
            "deepseek"
        case .claudeAdmin:
            "claude-admin"
        case .claudeExtra:
            "claude-extra"
        case .openCodeGoZen:
            "opencodego-zen"
        case .minimax:
            "minimax"
        case .codexWorkspace:
            "codex-workspace"
        }
    }
}

enum ProviderDetailSectionDispatcher {
    static func primarySection(for provider: ProviderUsageSnapshot) -> ProviderDetailPrimarySection {
        if provider.providerID == "perplexity",
           let credits = provider.perplexityCredits
        {
            return .perplexity(credits)
        }
        if Self.hasDedicatedPrimaryCard(provider) {
            return .suppressedByDedicatedCard
        }
        return .genericRateLimits
    }

    static func sections(
        for provider: ProviderUsageSnapshot,
        hasRateWindowPace: Bool) -> [ProviderDetailSection]
    {
        var sections: [ProviderDetailSection] = []

        if provider.providerID == "kiro", let value = provider.kiroCredits {
            sections.append(.kiro(value))
        }
        if provider.providerID == "bedrock", let value = provider.bedrockCost {
            sections.append(.bedrock(value))
        }
        if provider.providerID == "moonshot", let value = provider.moonshotBalance {
            sections.append(.moonshot(value))
        }
        if provider.providerID == "zai", let value = provider.zaiHourlyUsage {
            sections.append(.zai(value))
        }
        if provider.providerID == "openai", let value = provider.openAIAPIDashboard {
            sections.append(.openAI(value))
        }
        if provider.providerID == "antigravity",
           let value = provider.antigravityAccounts,
           value.accounts.count > 1
        {
            sections.append(.antigravity(value))
        }
        if provider.providerID == "grok", let value = provider.grokBilling {
            sections.append(.grok(value))
        }
        if provider.providerID == "elevenlabs", let value = provider.elevenLabsCredits {
            sections.append(.elevenLabs(value))
        }
        if provider.providerID == "deepgram", let value = provider.deepgramUsage {
            sections.append(.deepgram(value))
        }
        if provider.providerID == "groq", let value = provider.groqMetrics {
            sections.append(.groq(value))
        }
        if provider.providerID == "llmproxy", let value = provider.llmProxyStats {
            sections.append(.llmProxy(value))
        }
        if provider.providerID == "openrouter", let value = provider.openRouterStats {
            sections.append(.openRouter(value))
        }
        if provider.providerID == "azureopenai", let value = provider.azureOpenAIInfo {
            sections.append(.azureOpenAI(value))
        }
        if provider.providerID == "alibabatokenplan", let value = provider.alibabaTokenPlan {
            sections.append(.alibabaTokenPlan(value))
        }
        if provider.providerID == "deepseek", let value = provider.deepSeekUsage {
            sections.append(.deepSeek(value))
        }
        if provider.providerID == "claude", let value = provider.claudeAdminUsage {
            sections.append(.claudeAdmin(value))
        }
        if provider.providerID == "claude", let value = provider.claudeExtraUsage {
            sections.append(.claudeExtra(value))
        }
        if provider.providerID == "opencodego", let value = provider.openCodeGoZenBalance {
            sections.append(.openCodeGoZen(value))
        }
        if provider.providerID == "minimax", let value = provider.minimaxBilling {
            sections.append(.minimax(value))
        }
        if provider.providerID == "codex",
           let value = provider.codexWorkspace,
           (value.workspaceName?.isEmpty == false ||
               (!hasRateWindowPace && value.weeklyPaceLabel?.isEmpty == false))
        {
            sections.append(.codexWorkspace(value, showsPace: !hasRateWindowPace))
        }

        return sections
    }

    static func hasDedicatedPrimaryCard(_ provider: ProviderUsageSnapshot) -> Bool {
        switch provider.providerID {
        case "kiro" where provider.kiroCredits != nil:
            true
        case "bedrock" where provider.bedrockCost != nil:
            true
        case "moonshot" where provider.moonshotBalance != nil:
            true
        default:
            false
        }
    }
}

struct ProviderDetailPrimarySectionView<GenericContent: View>: View {
    let section: ProviderDetailPrimarySection
    let tintColor: Color
    let genericContent: GenericContent

    init(
        section: ProviderDetailPrimarySection,
        tintColor: Color,
        @ViewBuilder genericContent: () -> GenericContent)
    {
        self.section = section
        self.tintColor = tintColor
        self.genericContent = genericContent()
    }

    var body: some View {
        switch self.section {
        case .perplexity(let credits):
            PerplexityCreditsCard(credits: credits, tintColor: self.tintColor)
        case .suppressedByDedicatedCard:
            EmptyView()
        case .genericRateLimits:
            self.genericContent
        }
    }
}

struct ProviderDetailSectionView: View {
    let section: ProviderDetailSection
    let tintColor: Color

    var body: some View {
        switch self.section {
        case .kiro(let credits):
            KiroCreditsCard(credits: credits, tintColor: self.tintColor)
        case .bedrock(let cost):
            BedrockCostCard(cost: cost, tintColor: self.tintColor)
        case .moonshot(let balance):
            MoonshotBalanceCard(balance: balance, tintColor: self.tintColor)
        case .zai(let usage):
            ZaiHourlyChart(usage: usage, tintColor: self.tintColor)
        case .openAI(let dashboard):
            OpenAIDashboardSection(dashboard: dashboard, tintColor: self.tintColor)
        case .antigravity(let accounts):
            AntigravityAccountSwitcher(accounts: accounts, tintColor: self.tintColor)
        case .grok(let billing):
            GrokBillingCard(billing: billing, tintColor: self.tintColor)
        case .elevenLabs(let credits):
            ElevenLabsCreditsCard(credits: credits, tintColor: self.tintColor)
        case .deepgram(let usage):
            DeepgramUsageCard(usage: usage, tintColor: self.tintColor)
        case .groq(let metrics):
            GroqMetricsCard(metrics: metrics, tintColor: self.tintColor)
        case .llmProxy(let stats):
            LLMProxyStatsCard(stats: stats, tintColor: self.tintColor)
        case .openRouter(let stats):
            OpenRouterStatsCard(stats: stats, tintColor: self.tintColor)
        case .azureOpenAI(let info):
            AzureOpenAIInfoCard(info: info, tintColor: self.tintColor)
        case .alibabaTokenPlan(let plan):
            AlibabaTokenPlanCard(plan: plan, tintColor: self.tintColor)
        case .deepSeek(let usage):
            DeepSeekUsageCard(usage: usage, tintColor: self.tintColor)
        case .claudeAdmin(let usage):
            ClaudeAdminUsageCard(usage: usage, tintColor: self.tintColor)
        case .claudeExtra(let extraUsage):
            ClaudeExtraUsageCard(extraUsage: extraUsage, tintColor: self.tintColor)
        case .openCodeGoZen(let balance):
            OpenCodeGoZenBalanceCard(balance: balance, tintColor: self.tintColor)
        case .minimax(let billing):
            MiniMaxBillingCard(billing: billing, tintColor: self.tintColor)
        case .codexWorkspace(let context, let showsPace):
            CodexWorkspaceBadge(
                context: context,
                tintColor: self.tintColor,
                showsPace: showsPace)
        }
    }
}
